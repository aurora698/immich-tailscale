# Immich + Embedded Tailscale

<p>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-3F51B5?style=flat-square"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white">
  <img alt="Upstream" src="https://img.shields.io/badge/upstream-immich--app%2Fimmich-555?style=flat-square">
</p>

**English** · [简体中文](README.zh.md)

An Immich fork that compiles a **Tailscale node directly into the Android client**.

Install the APK and your phone can reach the Immich server at home from any network — no public IP, no port forwarding, no system-wide VPN. The tunnel only carries this app's traffic.

Built on [immich-app/immich](https://github.com/immich-app/immich) (AGPL-3.0). The **server is unchanged** — deploy stock Immich.

> This README replaces the upstream one; the original is still in git history (`git show 2acfe9e^:README.md`).

---

## Why this fork

| | Upstream Immich | This fork |
|---|---|---|
| Remote access | Needs public exposure, or the Tailscale app on the phone | Tailnet node inside the app; only Immich traffic is tunnelled |
| System VPN | The third-party Tailscale app occupies the VPN slot | Slot stays free, other apps unaffected |
| Home Wi-Fi | — | Bypasses the tunnel and goes over LAN, which is faster |
| Build | Generated sources are gitignored, codegen required | Generated sources are vendored; `flutter build apk` works from a fresh clone |
| Signing | CI uses org secrets | Fixed keystores in-repo, so builds update each other |

Branches: `main` is the merged result; `tailnet` / `release` are the feature branches. Pushing `tailnet` builds a debug APK, pushing `release` builds a signed release APK.

---

## Features

- **One switch** — Settings → Networking → Tailscale remote access starts a userspace node inside the app process.
- **Two ways to sign in** — browser authorization, or paste a `tskey-auth-…` key.
- **Precise routing** — only `*.ts.net`, `100.64.0.0/10`, `fd7a:115c:a1e0::/48` and `100.100.100.100` go through the node. Localhost, LAN and public hosts stay direct.
- **Diagnostics** — node state, tailnet name, node IP / MagicDNS name, login account; "Test latency" measures a real connection to the server and reports whether it took a **direct path, a DERP relay or a peer relay**.
- **Background work too** — foreground requests, background backup and the upload queue share the same tunnel.
- **Clean teardown** — turning the switch off stops the node and frees the port; signing out removes the device from the tailnet; Wi-Fi ↔ cellular switches notify the node to re-probe immediately.

---

## Use cases

1. **Self-hosted Immich on a home NAS, backing up from anywhere.** Home connections rarely have a public IPv4, so services behind carrier NAT are unreachable from outside. Flip the switch and it works; at home it falls back to the LAN automatically.
2. **Not wanting a global VPN for one app.** A system-wide tunnel takes over every other app's traffic and trips alarms in some banking apps. Here only Immich's own tailnet requests are affected.
3. **Sharing one Immich with family.** Put them in the same tailnet, install the APK, point them all at the same `https://<host>.<tailnet>.ts.net`.
4. **Judging link quality on a bad network.** The panel shows whether traffic is P2P or pushed onto a DERP relay, and how much latency that costs.
5. **Rolling your own private build.** Signing keys and a complete CI workflow ship with the repo — fork, rename, keep producing APKs.

---

## Getting started

**Install** (Releases)
- `apk-latest-release` — package `app.alextran.immich`, **replaces the store version**
- `apk-latest` — debug build, package `…immich.debug`, coexists with the store version

**Server**: install Tailscale and join it to your tailnet, enable MagicDNS. Immich's default `0.0.0.0:2283` is enough.

**Client**: enter `https://<host>.<tailnet>.ts.net` as the server URL (the full name is required — short MagicDNS names are deliberately not tunnelled) → turn the switch on → sign in → run "Test latency" to confirm the path.

---

## Building

Generated sources are vendored, so no bootstrap step is needed:

```bash
bash mobile/tooling/build-apk.sh            # debug
bash mobile/tooling/build-apk.sh --release
```

Toolchain: Flutter 3.47.9, JDK 21, NDK 28.2.13676358, Rust 1.99.1.

Changed the Go bridge (`mobile/android/tsbridge/`)? Rebuild the AAR:

```bash
bash mobile/android/tsbridge/build.sh       # -> app/libs/tsbridge.aar
```

Changed a pigeon or drift schema? `bash mobile/tooling/bootstrap.sh`.

CI (`.github/workflows/build-tailnet-apk.yml`) provisions everything itself — no org secrets, no self-hosted runner — and attaches the failing build log to the commit on failure.

---

## How it works

```
Dart/Flutter ──pigeon──▶ Kotlin TailnetManager
                           ├─ ProxySelector ──▶ 127.0.0.1:48113 (local HTTP proxy)
                           └─ OkHttp/Cronet/          │
                              HttpURLConnection       ▼
                                                 Go tsnet node ──▶ tailnet
```

- **A userspace node, not a VPN.** `tsnet` runs the node in-process; gomobile binds it into an AAR. It never touches `VpnService`, so the system VPN slot stays empty.
- **A loopback proxy carries the traffic.** Go serves an HTTP proxy on `127.0.0.1:48113` (fixed when possible) supporting `CONNECT` and plain forwarding; every outbound connection dials through `tsnet.Server.Dial`. The proxy demands Basic Auth with a per-process random token — loopback ports are reachable by any app on the device.
- **Java only decides what gets tunnelled.** The `ProxySelector` returns the local proxy for tailnet destinations and `NO_PROXY` for everything else.
- **Three HTTP stacks to satisfy.** OkHttp uses the ProxySelector plus an interceptor that waits for the node on cold start; Cronet has no proxy support, so media falls back to OkHttp; `background_downloader` runs on HttpURLConnection, which ignores ProxySelectors and needs an explicit proxy plus the JVM-wide `Authenticator` answering 407.
- **Two Android quirks.** Apps get no netlink socket, so the interface table comes from `java.net.NetworkInterface` and is fed to `netmon`, with `InjectEvent()` on network changes. And since there is no `HOME`/`TMPDIR`, both are pointed at app-private storage.

---

## Limitations

- **Android only.** iOS has nothing but the empty pigeon binding.
- **arm64 builds only.** The AAR ships arm64 and amd64; the APK targets arm64.
- **Short MagicDNS names are not tunnelled** — use the full `<host>.<tailnet>.ts.net`.
- **Signing keys are committed** (passwords in `build.gradle`). That keeps in-place updates working, but anyone can sign an APK with the same package id. Fine for personal sideloading, not for distribution.
- **Generated sources are vendored**, which makes the repo considerably larger than upstream.

---

## Layout

```
mobile/android/app/src/main/kotlin/.../tailnet/   node lifecycle, routing, pigeon impl
mobile/android/tsbridge/bridge.go                 tsnet + loopback proxy (Go)
mobile/android/app/libs/tsbridge.aar              prebuilt AAR (8 MB)
mobile/lib/providers/tailnet.provider.dart        state polling and actions
mobile/lib/widgets/settings/.../tailnet_preference.dart   settings card
mobile/pigeon/tailnet_api.dart                    native API definition
.github/workflows/build-tailnet-apk.yml           APK CI
```

---

## License

[AGPL-3.0](LICENSE), inherited from upstream. Fork changes are released under the same terms.
