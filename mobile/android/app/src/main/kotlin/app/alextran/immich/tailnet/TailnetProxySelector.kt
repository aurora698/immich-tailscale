package app.alextran.immich.tailnet

import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.SocketAddress
import java.net.URI

/**
 * Routes the hosts that only exist inside the tailnet through the embedded
 * node's loopback proxy, and leaves everything else alone.
 *
 * LAN, loopback and link-local addresses always go direct: the node has no
 * subnet routes for them, and when the phone is at home talking to the server
 * over the LAN is both faster and works with the node stopped.
 */
object TailnetProxySelector : ProxySelector() {
  private val tailnetCarrierSuffixes = listOf(".ts.net")

  override fun select(uri: URI): List<Proxy> {
    val proxy = TailnetManager.proxy
    if (!TailnetManager.enabled.value || proxy == null) return listOf(Proxy.NO_PROXY)
    val host = uri.host ?: return listOf(Proxy.NO_PROXY)
    if (!shouldTunnel(host)) return listOf(Proxy.NO_PROXY)
    return listOf(Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", proxy.port)))
  }

  override fun connectFailed(uri: URI, sa: SocketAddress, ioe: IOException) = Unit

  fun shouldTunnel(host: String): Boolean {
    val normalized = host.trim().lowercase().removeSurrounding("[", "]")
    if (normalized.isEmpty() || normalized == "localhost") return false
    if (normalized.endsWith(".local") || normalized.endsWith(".localhost")) return false
    if (tailnetCarrierSuffixes.any { normalized.endsWith(it) }) return true
    if (normalized == "100.100.100.100") return true // MagicDNS resolver
    val literal = parseIpv4(normalized)
    if (literal != null) return isTailnetIpv4(literal)
    if (normalized.contains(':')) return isTailnetIpv6(normalized)
    // Anything else is a normal internet host: leave it alone. MagicDNS short
    // names are not tunnelled on purpose — use the full <host>.ts.net name.
    return false
  }

  /** 100.64.0.0/10 is the CGNAT range Tailscale hands out. */
  private fun isTailnetIpv4(octets: IntArray): Boolean = octets[0] == 100 && octets[1] in 64..127

  /** Tailscale IPv6 addresses live in fd7a:115c:a1e0::/48. */
  private fun isTailnetIpv6(host: String): Boolean =
    host.startsWith("fd7a:115c:a1e0") || host.startsWith("fd7a:115c:a1e0:")

  private fun parseIpv4(host: String): IntArray? {
    val parts = host.split('.')
    if (parts.size != 4) return null
    val octets = IntArray(4)
    for (index in 0 until 4) {
      val value = parts[index].toIntOrNull() ?: return null
      if (value !in 0..255) return null
      octets[index] = value
    }
    return octets
  }
}
