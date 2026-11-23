package app.alextran.immich.tailnet

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Pigeon host for [TailnetManager]; see pigeon/tailnet_api.dart. */
class TailnetApiImpl(private val scope: CoroutineScope) : TailnetApi {
  fun attach(context: Context) {
    // The manager is initialised from MainActivity.registerPlugins so that the
    // background engine shares the same node.
    TailnetManager.initialize(context, scope)
  }

  override fun isEnabled(): Boolean = TailnetManager.enabled.value

  override fun setEnabled(enabled: Boolean, callback: (Result<Unit>) -> Unit) {
    scope.launch { callback(runCatching { TailnetManager.setEnabled(enabled) }) }
  }

  // Read fresh: the cached flow is only updated by pushes we do not subscribe
  // to from Dart, so polling it would show a stale state forever.
  override fun status(): String = TailnetManager.refreshStatus().toJson()

  override fun start(authKey: String, callback: (Result<Unit>) -> Unit) {
    scope.launch { callback(runCatching { TailnetManager.start(authKey) }) }
  }

  override fun stop(callback: (Result<Unit>) -> Unit) {
    scope.launch { callback(runCatching { TailnetManager.stop() }) }
  }

  override fun logout(callback: (Result<Unit>) -> Unit) {
    scope.launch { callback(runCatching { TailnetManager.signOutAndRestart() }) }
  }

  override fun proxyPort(): Long = (TailnetManager.proxy?.port ?: 0).toLong()

  override fun proxyToken(): String = TailnetManager.proxy?.token ?: ""

  override fun peersJSON(callback: (Result<String>) -> Unit) {
    scope.launch { callback(runCatching { Tsbridge.peersJSON() }) }
  }

  override fun pingPeer(hostPort: String, callback: (Result<String>) -> Unit) {
    scope.launch { callback(runCatching { Tsbridge.pingPeer(hostPort) }) }
  }

  private fun TailnetStatus.toJson(): String {
    val escaped = { value: String? ->
      value?.replace("\\", "\\\\")?.replace("\"", "\\\"")
    }
    val ipsJson = ips.joinToString(",") { "\"${escaped(it)}\"" }
    return buildString {
      append("{\"state\":\"${escaped(state)}\"")
      authUrl?.let { append(",\"authUrl\":\"${escaped(it)}\"") }
      append(",\"ips\":[$ipsJson]")
      dnsName?.let { append(",\"dnsName\":\"${escaped(it)}\"") }
      tailnet?.let { append(",\"tailnet\":\"${escaped(it)}\"") }
      loginName?.let { append(",\"loginName\":\"${escaped(it)}\"") }
      error?.let { append(",\"error\":\"${escaped(it)}\"") }
      append("}")
    }
  }
}
