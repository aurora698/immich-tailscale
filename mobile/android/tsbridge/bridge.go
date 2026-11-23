// Package tsbridge embeds a userspace Tailscale node (tsnet) into the Immich
// Android app and exposes it through a gomobile-friendly API.
//
// The node never creates a VPN interface and never touches VpnService. Instead
// the bridge runs a small HTTP proxy on 127.0.0.1 that dials every request
// through the tailnet, so the app's own HTTP stacks (OkHttp, HttpURLConnection)
// can be pointed at it with a ProxySelector. Nothing else on the phone is
// affected, and the system VPN slot stays free.
//
// The proxy requires a random per-process token: loopback ports are reachable
// by every app on the device, so an unauthenticated proxy would hand the
// tailnet to any other app.
package tsbridge

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"os"
	"strings"
	"sync"
	"time"

	"tailscale.com/envknob"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/netmon"
	"tailscale.com/tsnet"
)

// pingTries is how many dials PingPeer measures after a warm-up.
const pingTries = 3

// preferredProxyPort is stable across restarts so configured clients stay valid.
const preferredProxyPort = 48113

const (
	dialAttemptTimeout = 4 * time.Second
	dialRetryPause     = 250 * time.Millisecond
	dialTotalTimeout   = 30 * time.Second
	statusTimeout      = 5 * time.Second
	logoutTimeout      = 15 * time.Second
)

var (
	mu        sync.Mutex
	server    *tsnet.Server
	proxyLn   net.Listener
	proxyTok  string
	lastError string
)

// Start brings the tailnet node up and starts the loopback proxy. It returns
// as soon as the node begins starting: poll Status for progress and for the
// interactive login URL. authKey may be empty when the node is already logged
// in from a previous run.
func Start(stateDir, hostname, authKey, interfaces string) error {
	mu.Lock()
	defer mu.Unlock()
	if server != nil {
		return nil
	}
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return err
	}

	// Android apps have no HOME or TMPDIR, and parts of Tailscale expect them.
	os.Setenv("HOME", stateDir)
	os.Setenv("TMPDIR", stateDir)
	// Log uploads to log.tailscale.com cannot resolve on Android (Go has no
	// resolv.conf there) and are not wanted for a personal build.
	envknob.SetNoLogsNoSupport()

	// Register the interface list before the node starts: netmon asks for it
	// while initialising, and Android denies the netlink socket that Go would
	// otherwise use. Doing it here removes any ordering assumption on the caller.
	ifaces := parseInterfaces(interfaces)
	netmon.RegisterInterfaceGetter(func() ([]netmon.Interface, error) { return ifaces, nil })
	log.Printf("tsbridge: start with %d interfaces", len(ifaces))

	srv := &tsnet.Server{
		Dir:      stateDir,
		Hostname: hostname,
		AuthKey:  authKey,
		UserLogf: log.Printf,
		Logf:     log.Printf,
	}
	if err := srv.Start(); err != nil {
		lastError = err.Error()
		return err
	}

	// Prefer a fixed port: background_downloader stores the proxy address in a
	// global config we cannot refresh from Kotlin on every restart, so a stable
	// port keeps its tasks working across restarts. Fall back to any port.
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", preferredProxyPort))
	if err != nil {
		ln, err = net.Listen("tcp", "127.0.0.1:0")
	}
	if err != nil {
		srv.Close()
		lastError = err.Error()
		return err
	}

	token := make([]byte, 24)
	if _, err := rand.Read(token); err != nil {
		ln.Close()
		srv.Close()
		lastError = err.Error()
		return err
	}

	server, proxyLn, proxyTok, lastError = srv, ln, hex.EncodeToString(token), ""
	go func() {
		_ = http.Serve(ln, &proxyHandler{node: srv, token: proxyTok})
	}()
	return nil
}

// Stop shuts the node down but keeps its state directory, so the next Start
// resumes without another login.
func Stop() {
	mu.Lock()
	defer mu.Unlock()
	stopLocked()
}

func stopLocked() {
	if proxyLn != nil {
		_ = proxyLn.Close()
		proxyLn = nil
	}
	if server != nil {
		_ = server.Close()
		server = nil
	}
}

// Logout removes the node from the tailnet and stops it.
func Logout() error {
	mu.Lock()
	defer mu.Unlock()
	if server == nil {
		return errors.New("node is not running")
	}
	lc, err := server.LocalClient()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), logoutTimeout)
	defer cancel()
	err = lc.Logout(ctx)
	stopLocked()
	return err
}


// PeersJSON reports every peer in the tailnet together with the path traffic
// currently takes to it: a direct endpoint, a DERP relay, or a peer relay.
func PeersJSON() string {
	mu.Lock()
	srv := server
	mu.Unlock()
	if srv == nil {
		return "[]"
	}
	lc, err := srv.LocalClient()
	if err != nil {
		return "[]"
	}
	ctx, cancel := context.WithTimeout(context.Background(), statusTimeout)
	defer cancel()
	st, err := lc.Status(ctx)
	if err != nil {
		return "[]"
	}
	out := make([]map[string]any, 0, len(st.Peer))
	for _, peer := range st.Peer {
		via, endpoint, relay := peerPath(peer)
		ip := ""
		if len(peer.TailscaleIPs) > 0 {
			ip = peer.TailscaleIPs[0].String()
		}
		out = append(out, map[string]any{
			"hostName": peer.HostName,
			"dnsName":  strings.TrimSuffix(peer.DNSName, "."),
			"ip":       ip,
			"online":   peer.Online,
			"os":       peer.OS,
			"via":      via,
			"endpoint": endpoint,
			"relay":    relay,
		})
	}
	encoded, err := json.Marshal(out)
	if err != nil {
		return "[]"
	}
	return string(encoded)
}

// peerPath classifies how traffic reaches a peer right now.
func peerPath(peer *ipnstate.PeerStatus) (via, endpoint, relay string) {
	switch {
	case peer.PeerRelay != "":
		return "peer-relay", peer.PeerRelay, ""
	case peer.CurAddr != "":
		return "direct", peer.CurAddr, ""
	case peer.Relay != "":
		return "derp", "", peer.Relay
	default:
		return "unknown", "", ""
	}
}

// PingPeer measures how long a connection to hostPort takes through the node,
// and reports the path the peer is reached over. The first dial is a warm-up
// (it may have to open a path), the reported figure is the best of [pingTries].
func PingPeer(hostPort string) string {
	mu.Lock()
	srv := server
	mu.Unlock()
	fail := func(msg string) string {
		encoded, _ := json.Marshal(map[string]any{"ok": false, "error": msg})
		return string(encoded)
	}
	if srv == nil {
		return fail("node is not running")
	}
	hostPort = strings.TrimSpace(hostPort)
	if !strings.Contains(hostPort, ":") {
		return fail("expected host:port")
	}

	via, endpoint, relay := "unknown", "", ""
	if lc, err := srv.LocalClient(); err == nil {
		ctx, cancel := context.WithTimeout(context.Background(), statusTimeout)
		if st, err := lc.Status(ctx); err == nil {
			host, _, _ := net.SplitHostPort(hostPort)
			for _, peer := range st.Peer {
				if peerMatches(peer, host) {
					via, endpoint, relay = peerPath(peer)
					break
				}
			}
		}
		cancel()
	}

	dial := func() (time.Duration, error) {
		ctx, cancel := context.WithTimeout(context.Background(), dialAttemptTimeout)
		defer cancel()
		start := time.Now()
		conn, err := srv.Dial(ctx, "tcp", hostPort)
		elapsed := time.Since(start)
		if err != nil {
			return 0, err
		}
		_ = conn.Close()
		return elapsed, nil
	}

	if _, err := dial(); err != nil {
		// The first dial may have to open a path; one retry before giving up.
		if _, retryErr := dial(); retryErr != nil {
			return fail(retryErr.Error())
		}
	}
	best := time.Duration(0)
	for i := 0; i < pingTries; i++ {
		elapsed, err := dial()
		if err != nil {
			continue
		}
		if best == 0 || elapsed < best {
			best = elapsed
		}
	}
	if best == 0 {
		return fail("no reply")
	}
	encoded, _ := json.Marshal(map[string]any{
		"ok":        true,
		"latencyMs": float64(best.Microseconds()) / 1000.0,
		"via":       via,
		"endpoint":  endpoint,
		"relay":     relay,
	})
	return string(encoded)
}

func peerMatches(peer *ipnstate.PeerStatus, host string) bool {
	for _, ip := range peer.TailscaleIPs {
		if ip.String() == host {
			return true
		}
	}
	dns := strings.TrimSuffix(peer.DNSName, ".")
	short := strings.Split(dns, ".")[0]
	return host == dns || host == short || host == peer.HostName
}

// ProxyPort is the loopback port of the proxy, or 0 when the node is stopped.
func ProxyPort() int {
	mu.Lock()
	defer mu.Unlock()
	if proxyLn == nil {
		return 0
	}
	return proxyLn.Addr().(*net.TCPAddr).Port
}

// ProxyToken is the basic-auth password clients must send (any user name).
func ProxyToken() string {
	mu.Lock()
	defer mu.Unlock()
	return proxyTok
}

type status struct {
	// State is the Tailscale backend state: Stopped, NoState, NeedsLogin,
	// NeedsMachineAuth, Starting or Running.
	State     string   `json:"state"`
	AuthURL   string   `json:"authUrl,omitempty"`
	IPs       []string `json:"ips,omitempty"`
	DNSName   string   `json:"dnsName,omitempty"`
	Tailnet   string   `json:"tailnet,omitempty"`
	LoginName string   `json:"loginName,omitempty"`
	Error     string   `json:"error,omitempty"`
}

// StatusJSON reports the node state as JSON, for the Kotlin side to parse.
func StatusJSON() string {
	mu.Lock()
	srv, errStr := server, lastError
	mu.Unlock()

	st := status{State: "Stopped", Error: errStr}
	if srv != nil {
		readStatus(srv, &st)
	}
	out, err := json.Marshal(st)
	if err != nil {
		return `{"state":"Stopped","error":"cannot encode status"}`
	}
	return string(out)
}

func readStatus(srv *tsnet.Server, st *status) {
	lc, err := srv.LocalClient()
	if err != nil {
		st.Error = err.Error()
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), statusTimeout)
	defer cancel()
	netStatus, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		st.Error = err.Error()
		return
	}
	st.State = netStatus.BackendState
	st.AuthURL = netStatus.AuthURL
	for _, ip := range netStatus.TailscaleIPs {
		st.IPs = append(st.IPs, ip.String())
	}
	if netStatus.Self != nil {
		st.DNSName = strings.TrimSuffix(netStatus.Self.DNSName, ".")
	}
	if netStatus.CurrentTailnet != nil {
		st.Tailnet = netStatus.CurrentTailnet.Name
	}
	if netStatus.Self != nil {
		if user, ok := netStatus.User[netStatus.Self.UserID]; ok {
			st.LoginName = user.LoginName
		}
	}
}

// SetInterfaces hands the device's interfaces to Tailscale and nudges the
// running node to re-evaluate the network.
//
// Android denies apps the netlink socket that Go's net.Interfaces uses, so the
// list comes from java.net.NetworkInterface instead. One line per interface:
//
//	name index mtu up broadcast loopback pointToPoint multicast | addr/prefix ...
func SetInterfaces(desc string) {
	parsed := parseInterfaces(desc)
	log.Printf("tsbridge: setInterfaces %d", len(parsed))
	netmon.RegisterInterfaceGetter(func() ([]netmon.Interface, error) { return parsed, nil })
	nudgeNetwork()
}

// nudgeNetwork asks the running node to re-check the network now. Without it
// netmon only polls every ten minutes, which is far too slow for a phone that
// switches between Wi-Fi and cellular.
func nudgeNetwork() {
	mu.Lock()
	srv := server
	mu.Unlock()
	if srv == nil {
		return
	}
	if nm, ok := srv.Sys().NetMon.GetOK(); ok {
		nm.InjectEvent()
	}
}

func parseInterfaces(desc string) []netmon.Interface {
	var out []netmon.Interface
	for _, line := range strings.Split(desc, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		head, addrPart, _ := strings.Cut(line, "|")
		var name string
		var index, mtu int
		var up, broadcast, loopback, pointToPoint, multicast bool
		if _, err := fmt.Sscan(head, &name, &index, &mtu, &up, &broadcast, &loopback, &pointToPoint, &multicast); err != nil {
			continue
		}
		var flags net.Flags
		for flag, set := range map[net.Flags]bool{
			net.FlagUp:          up,
			net.FlagRunning:     up,
			net.FlagBroadcast:   broadcast,
			net.FlagLoopback:    loopback,
			net.FlagPointToPoint: pointToPoint,
			net.FlagMulticast:   multicast,
		} {
			if set {
				flags |= flag
			}
		}
		// AltAddrs must never be nil: netmon falls back to the real
		// net.Interface.Addrs, which needs netlink and fails on Android.
		addrs := make([]net.Addr, 0, 4)
		for _, field := range strings.Fields(addrPart) {
			// Android reports link-local IPv6 as fe80::1%wlan0, which
			// net.ParseCIDR rejects; the zone is meaningless here.
			host, bits, hasBits := strings.Cut(field, "/")
			if !hasBits {
				continue
			}
			if zone := strings.IndexByte(host, '%'); zone >= 0 {
				host = host[:zone]
			}
			ip, network, err := net.ParseCIDR(host + "/" + bits)
			if err != nil {
				continue
			}
			network.IP = ip
			addrs = append(addrs, network)
		}
		out = append(out, netmon.Interface{
			Interface: &net.Interface{Index: index, MTU: mtu, Name: name, Flags: flags},
			AltAddrs:  addrs,
		})
	}
	return out
}

// proxyHandler is a minimal HTTP forward proxy (plain requests and CONNECT)
// whose upstream connections all go through the tailnet.
type proxyHandler struct {
	node  *tsnet.Server
	token string
	rp    *httputil.ReverseProxy
	once  sync.Once
}

func (h *proxyHandler) authorized(r *http.Request) bool {
	auth := r.Header.Get("Proxy-Authorization")
	r.Header.Del("Proxy-Authorization")
	// Reuse BasicAuth parsing without pulling a dependency.
	probe := &http.Request{Header: http.Header{"Authorization": {auth}}}
	_, password, ok := probe.BasicAuth()
	return ok && password == h.token
}

func (h *proxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if !h.authorized(r) {
		w.Header().Set("Proxy-Authenticate", `Basic realm="immich-tailnet"`)
		http.Error(w, "proxy authentication required", http.StatusProxyAuthRequired)
		return
	}
	if r.Method == http.MethodConnect {
		log.Printf("proxy: CONNECT %s", r.Host)
		h.connect(w, r)
		return
	}
	sw := &statusWriter{ResponseWriter: w, code: http.StatusOK}
	log.Printf("proxy: %s %s%s", r.Method, r.Host, r.URL.Path)
	if r.URL.Host == "" {
		http.Error(w, "absolute-form request required", http.StatusBadRequest)
		return
	}
	h.once.Do(func() {
		h.rp = &httputil.ReverseProxy{
			Rewrite:       func(pr *httputil.ProxyRequest) { pr.Out.URL = pr.In.URL },
			FlushInterval: -1,
			Transport: &http.Transport{
				DialContext:           h.dial,
				MaxIdleConnsPerHost:   4,
				IdleConnTimeout:       90 * time.Second,
				ResponseHeaderTimeout: 10 * time.Minute,
			},
		}
	})
	h.rp.ServeHTTP(sw, r)
	log.Printf("proxy: %s %s -> %d", r.Method, r.URL.Path, sw.code)
}

// statusWriter remembers the status code so the log can show it.
type statusWriter struct {
	http.ResponseWriter
	code int
}

func (w *statusWriter) WriteHeader(code int) {
	w.code = code
	w.ResponseWriter.WriteHeader(code)
}

// Hijack keeps WebSocket upgrades working: the socket.io stream needs the raw
// connection, and a bare wrapper would hide http.Hijacker from the proxy.
func (w *statusWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	hijacker, ok := w.ResponseWriter.(http.Hijacker)
	if !ok {
		return nil, nil, fmt.Errorf("response writer does not support hijacking")
	}
	return hijacker.Hijack()
}

func (w *statusWriter) Flush() {
	if flusher, ok := w.ResponseWriter.(http.Flusher); ok {
		flusher.Flush()
	}
}

func (h *proxyHandler) dial(ctx context.Context, network, addr string) (net.Conn, error) {
	ctx, cancel := context.WithTimeout(ctx, dialTotalTimeout)
	defer cancel()
	// Right after start the node works from a cached netmap without peers, and
	// a dial begun then never recovers once the peers arrive; short attempts are
	// what eventually gets through. The same covers network switches.
	for {
		attemptCtx, cancelAttempt := context.WithTimeout(ctx, dialAttemptTimeout)
		conn, err := h.node.Dial(attemptCtx, network, addr)
		cancelAttempt()
		if err == nil {
			return conn, nil
		}
		select {
		case <-ctx.Done():
			return nil, err
		case <-time.After(dialRetryPause):
		}
	}
}

func (h *proxyHandler) connect(w http.ResponseWriter, r *http.Request) {
	upstream, err := h.dial(r.Context(), "tcp", r.Host)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		upstream.Close()
		http.Error(w, "hijacking unsupported", http.StatusInternalServerError)
		return
	}
	client, buffered, err := hijacker.Hijack()
	if err != nil {
		upstream.Close()
		return
	}
	if _, err := client.Write([]byte("HTTP/1.1 200 Connection established\r\n\r\n")); err != nil {
		client.Close()
		upstream.Close()
		return
	}
	go func() {
		// The client may already have sent TLS bytes that the server buffered.
		if n := buffered.Reader.Buffered(); n > 0 {
			if pending, _ := buffered.Reader.Peek(n); len(pending) > 0 {
				_, _ = upstream.Write(pending)
			}
		}
		_, _ = io.Copy(upstream, client)
		upstream.Close()
	}()
	_, _ = io.Copy(client, upstream)
	client.Close()
}
