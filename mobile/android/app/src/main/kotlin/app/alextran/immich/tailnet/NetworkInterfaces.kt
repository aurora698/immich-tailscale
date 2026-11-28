package app.alextran.immich.tailnet

import android.util.Log
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.NetworkInterface

/**
 * Serialises the device's network interfaces for the Go side.
 *
 * Go's net.Interfaces reads netlink, which Android denies to apps, so the node
 * would otherwise see no interfaces at all — and netmon would only notice a
 * network change on its ten-minute poll.
 *
 * Line format, one per interface:
 *   name index mtu up broadcast loopback pointToPoint multicast | addr/prefix ...
 */
object NetworkInterfaces {
  private const val TAG = "NetworkInterfaces"

  fun describe(): String {
    val builder = StringBuilder()
    val interfaces = runCatching { NetworkInterface.getNetworkInterfaces() }.getOrNull()
      ?: return ""
    for (iface in interfaces) {
      val addresses = runCatching { iface.inetAddresses?.toList().orEmpty() }.getOrDefault(emptyList())
      if (addresses.isEmpty()) continue
      val flags = runCatching { iface.isUp to iface.isLoopback }.getOrDefault(false to false)
      val mtu = runCatching { iface.mtu }.getOrDefault(0)
      val broadcast = addresses.any { it is Inet4Address && !it.isLoopbackAddress }
      builder.append(iface.name)
        .append(' ').append(runCatching { iface.index }.getOrDefault(0))
        .append(' ').append(if (mtu > 0) mtu else 1500)
        .append(' ').append(flags.first)
        .append(' ').append(broadcast)
        .append(' ').append(flags.second)
        .append(' ').append(false)
        .append(' ').append(addresses.any { it is Inet6Address && it.isMulticastAddress })
        .append(" |")
      for (address in addresses) {
        // java.net does not expose the prefix length; the usual host sizes are
        // enough for the node to pick a usable source address.
        val bits = when (address) {
          is Inet4Address -> 24
          is Inet6Address -> 64
          else -> continue
        }
        builder.append(' ').append("${address.hostAddress}/$bits")
      }
      builder.append('\n')
    }
    if (builder.isEmpty()) Log.i(TAG, "no interfaces described")
    return builder.toString()
  }
}
