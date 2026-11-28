/// A peer of the tailnet, with the path traffic takes to it right now.
class TailnetPeer {
  final String hostName;
  final String? dnsName;
  final String ip;
  final bool online;
  final String? os;

  /// direct, derp, peer-relay or unknown.
  final String via;
  final String? endpoint;
  final String? relay;

  const TailnetPeer({
    required this.hostName,
    this.dnsName,
    this.ip = '',
    this.online = false,
    this.os,
    this.via = 'unknown',
    this.endpoint,
    this.relay,
  });

  factory TailnetPeer.fromJson(Map<String, dynamic> json) => TailnetPeer(
    hostName: json['hostName'] as String? ?? '?',
    dnsName: json['dnsName'] as String?,
    ip: json['ip'] as String? ?? '',
    online: json['online'] == true || json['online'] == 'true',
    os: json['os'] as String?,
    via: json['via'] as String? ?? 'unknown',
    endpoint: json['endpoint'] as String?,
    relay: json['relay'] as String?,
  );
}

/// Result of tapping "measure latency": round-trip time plus the path used.
class TailnetPing {
  final bool ok;
  final double? latencyMs;
  final String? via;
  final String? endpoint;
  final String? relay;
  final String? error;

  const TailnetPing({required this.ok, this.latencyMs, this.via, this.endpoint, this.relay, this.error});

  factory TailnetPing.fromJson(Map<String, dynamic> json) => TailnetPing(
    ok: json['ok'] == true || json['ok'] == 'true',
    latencyMs: (json['latencyMs'] as num?)?.toDouble(),
    via: json['via'] as String?,
    endpoint: json['endpoint'] as String?,
    relay: json['relay'] as String?,
    error: json['error'] as String?,
  );
}

/// Human label for a path kind reported by the node.
String tailnetViaLabel(String? via) => switch (via) {
  'direct' => '直连',
  'derp' => 'DERP 中继',
  'peer-relay' => '对等中继',
  _ => '未知',
};
