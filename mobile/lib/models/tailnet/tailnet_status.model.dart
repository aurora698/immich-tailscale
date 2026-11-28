/// State of the embedded Tailscale node (userspace tsnet).
///
/// Mirrors what `TailnetManager.statusJSON()` reports on the Android side.
class TailnetStatus {
  /// Backend state: Stopped, NoState, NeedsLogin, NeedsMachineAuth, Starting, Running.
  final String state;
  final String? authUrl;
  final List<String> ips;
  final String? dnsName;
  final String? tailnet;
  final String? loginName;
  final String? error;

  const TailnetStatus({
    this.state = 'Stopped',
    this.authUrl,
    this.ips = const [],
    this.dnsName,
    this.tailnet,
    this.loginName,
    this.error,
  });

  factory TailnetStatus.fromJson(Map<String, dynamic> json) => TailnetStatus(
    state: json['state'] as String? ?? 'Stopped',
    authUrl: json['authUrl'] as String?,
    ips: (json['ips'] as List<dynamic>? ?? const []).whereType<String>().toList(),
    dnsName: json['dnsName'] as String?,
    tailnet: json['tailnet'] as String?,
    loginName: json['loginName'] as String?,
    error: json['error'] as String?,
  );

  bool get isRunning => state == 'Running';

  /// The node is up but this device still has to finish signing in.
  bool get needsSignIn => state == 'NeedsLogin' || state == 'NeedsMachineAuth';

  bool get isStarting => state == 'Starting' || state == 'NoState';
}
