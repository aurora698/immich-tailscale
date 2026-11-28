package app.alextran.immich.tailnet

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.SystemClock
import android.util.Log
import app.alextran.immich.BuildConfig
import app.alextran.immich.tsbridge.Tsbridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

/**
 * Owns the embedded Tailscale node.
 *
 * The node is a userspace one (tsnet): it never creates a VPN interface, so the
 * system VPN slot stays free and no other app is affected. All Immich traffic
 * reaches the tailnet through a loopback HTTP proxy that this class hands out.
 *
 * The node runs whenever the switch is on: the switch is the single source of
 * truth, so enabling it also covers background backups. Idle teardown (stop the
 * node when the app is backgrounded on battery) is a later optimisation.
 */
object TailnetManager {
  private const val TAG = "TailnetManager"
  private const val INTERFACE_DEBOUNCE_MS = 600L
  private const val PROXY_WAIT_MS = 8_000L
  private const val POLL_INTERVAL_MS = 50L

  private lateinit var appContext: Context
  private lateinit var stateDir: File
  private lateinit var connectivity: ConnectivityManager
  private var scope: CoroutineScope? = null

  private val lock = Mutex()
  private val json = Json { ignoreUnknownKeys = true }

  private val _status = MutableStateFlow(TailnetStatus())
  val status: StateFlow<TailnetStatus> = _status.asStateFlow()

  private val _enabled = MutableStateFlow(false)

  /** Whether the user wants tailnet access. Persisted by [TailnetSettings]. */
  val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

  /** The loopback proxy of the running node, or null when it is stopped. */
  @Volatile
  var proxy: TailnetProxy? = null
    private set

  @Volatile
  private var statusAt = 0L

  @Volatile
  private var initialized = false

  @Volatile
  private var lastPushedInterfaces: String? = null

  private var pushJob: Job? = null

  fun initialize(context: Context, coroutineScope: CoroutineScope) {
    if (initialized) return
    synchronized(this) {
      if (initialized) return
      appContext = context.applicationContext
      stateDir = File(appContext.noBackupFilesDir, "tailnet")
      connectivity = appContext.getSystemService(ConnectivityManager::class.java)
      scope = coroutineScope
      _enabled.value = TailnetSettings.isEnabled(appContext)
      if (_enabled.value) coroutineScope.launch(Dispatchers.IO) { start() }
      initialized = true
    }
    connectivity.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
      override fun onAvailable(network: Network) = scheduleInterfacePush()

      override fun onLinkPropertiesChanged(network: Network, linkProperties: android.net.LinkProperties) =
        scheduleInterfacePush()

      override fun onLost(network: Network) = scheduleInterfacePush()
    })
  }

  /**
   * Waits (blocking) until the loopback proxy is ready. OkHttp interceptors run
   * on plain threads, and after the process is reclaimed the first requests
   * would otherwise race the node and fail — which is what made the backup and
   * profile icons flash an error for a few seconds when the app came back.
   *
   * Returns null when the node cannot serve traffic (switch off, or a login is
   * still required), so those requests fail fast instead of stalling.
   */
  fun awaitProxyBlocking(timeoutMs: Long = PROXY_WAIT_MS): TailnetProxy? {
    proxy?.let { return it }
    if (!_enabled.value) return null
    val state = _status.value.state
    if (state == "NeedsLogin" || state == "NeedsMachineAuth") return null

    val deadline = SystemClock.elapsedRealtime() + timeoutMs
    while (SystemClock.elapsedRealtime() < deadline) {
      proxy?.let { return it }
      Thread.sleep(POLL_INTERVAL_MS)
    }
    proxy?.let { return it }
    Log.w(TAG, "proxy still not ready after ${timeoutMs}ms")
    return null
  }

  suspend fun setEnabled(enabled: Boolean) {
    _enabled.value = enabled
    TailnetSettings.setEnabled(appContext, enabled)
    if (enabled) start() else stop()
  }

  /** Starts the node; a non-blank [authKey] logs in without the browser. */
  suspend fun start(authKey: String = ""): Unit = lock.withLock {
    withContext(Dispatchers.IO) {
      if (authKey.isNotBlank()) runCatching { Tsbridge.stop() }
      val interfaces = NetworkInterfaces.describe()
      lastPushedInterfaces = interfaces
      runCatching { Tsbridge.setInterfaces(interfaces) }
      runCatching { Tsbridge.start(stateDir.absolutePath, hostname(), authKey.trim(), interfaces) }
        .onFailure { Log.w(TAG, "start failed", it) }
      val port = Tsbridge.proxyPort().toInt()
      proxy = if (port > 0) TailnetProxy(port, Tsbridge.proxyToken()) else null
      proxy?.let {
        Log.i(TAG, "proxy on 127.0.0.1:${it.port}")
        if (BuildConfig.DEBUG) Log.d(TAG, "proxy token ${it.token}")
      }
      refreshStatus()
    }
  }

  suspend fun stop(): Unit = lock.withLock {
    withContext(Dispatchers.IO) {
      proxy = null
      lastPushedInterfaces = null
      runCatching { Tsbridge.stop() }.onFailure { Log.w(TAG, "stop failed", it) }
      refreshStatus()
    }
  }

  suspend fun logout(): Unit = lock.withLock {
    withContext(Dispatchers.IO) {
      proxy = null
      lastPushedInterfaces = null
      runCatching { Tsbridge.logout() }.onFailure { Log.w(TAG, "logout failed", it) }
      refreshStatus()
    }
  }

  /**
   * Signs out and, if the switch is still on, brings the node back up so a
   * fresh login URL is available. Leaving it stopped while the switch reads
   * "on" is what made the card sit at "starting" forever.
   */
  suspend fun signOutAndRestart() {
    logout()
    if (_enabled.value) start()
  }

  fun refreshStatus(): TailnetStatus {
    val parsed = runCatching { decode(Tsbridge.statusJSON()) }
      .getOrElse { TailnetStatus(state = "Stopped", error = it.message) }
    _status.value = parsed
    statusAt = SystemClock.elapsedRealtime()
    return parsed
  }

  private fun decode(raw: String): TailnetStatus {
    val root = json.parseToJsonElement(raw).jsonObject
    fun str(key: String) = root[key]?.jsonPrimitive?.contentOrNull
    val ips = root["ips"]?.jsonArray?.mapNotNull { it.jsonPrimitive.contentOrNull } ?: emptyList()
    return TailnetStatus(
      state = str("state") ?: "Stopped",
      authUrl = str("authUrl"),
      ips = ips,
      dnsName = str("dnsName"),
      tailnet = str("tailnet"),
      loginName = str("loginName"),
      error = str("error"),
    )
  }

  /**
   * Coalesces the burst of callbacks a network change produces. Pushing on
   * every callback makes netmon treat each one as a change, which restarts
   * netcheck and costs battery.
   */
  private fun scheduleInterfacePush() {
    pushJob?.cancel()
    pushJob = scope?.launch(Dispatchers.IO) {
      delay(INTERFACE_DEBOUNCE_MS)
      pushInterfaces()
    }
  }

  private fun pushInterfaces() {
    val description = runCatching { NetworkInterfaces.describe() }.getOrNull() ?: return
    if (description == lastPushedInterfaces) return
    lastPushedInterfaces = description
    runCatching { Tsbridge.setInterfaces(description) }
      .onFailure { Log.w(TAG, "cannot pass interfaces to the node", it) }
  }

  private fun hostname(): String {
    val model = android.os.Build.MODEL.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')
    return "immich-${model.ifEmpty { "android" }}".take(60)
  }
}

data class TailnetProxy(val port: Int, val token: String)

data class TailnetStatus(
  /** Backend state: Stopped, NoState, NeedsLogin, NeedsMachineAuth, Starting, Running. */
  val state: String = "Stopped",
  val authUrl: String? = null,
  val ips: List<String> = emptyList(),
  val dnsName: String? = null,
  val tailnet: String? = null,
  val loginName: String? = null,
  val error: String? = null,
) {
  val isRunning: Boolean get() = state == "Running"
  val needsUser: Boolean get() = state == "NeedsLogin" || state == "NeedsMachineAuth"
}

/** Small persisted flag store; keeps the tailnet switch across restarts. */
object TailnetSettings {
  private const val PREFS = "immich.tailnet"
  private const val KEY_ENABLED = "enabled"

  fun isEnabled(context: Context): Boolean =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

  fun setEnabled(context: Context, enabled: Boolean) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, enabled).apply()
  }
}
