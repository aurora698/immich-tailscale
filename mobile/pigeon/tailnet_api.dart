import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/tailnet_api.g.dart',
    swiftOut: 'ios/Runner/Core/Tailnet.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut:
        'android/app/src/main/kotlin/app/alextran/immich/tailnet/Tailnet.g.kt',
    kotlinOptions: KotlinOptions(package: 'app.alextran.immich.tailnet', includeErrorClass: true),
    dartOptions: DartOptions(),
    dartPackageName: 'immich_mobile',
  ),
)
/// Host side of the embedded Tailscale node (see TailnetManager on Android).
///
/// Only Android implements it: the node is a userspace one, so iOS would need a
/// different transport and is out of scope.
@HostApi()
abstract class TailnetApi {
  /// Whether the user wants Immich traffic to reach the tailnet.
  bool isEnabled();

  /// Turns the node on or off and persists the choice. Async so callers can
  /// wait for the node to come up before pointing other clients at the proxy.
  @async
  void setEnabled(bool enabled);

  /// Backend state as JSON: state, authUrl, ips, dnsName, tailnet, loginName, error.
  String status();

  /// Starts the node; a non-blank auth key logs in without the browser.
  @async
  void start(String authKey);

  @async
  void stop();

  /// Removes the node from the tailnet; the next start asks for a new login.
  @async
  void logout();

  /// Loopback proxy port, or 0 while the node is stopped.
  int proxyPort();

  /// Password for the proxy's basic auth (any user name works).
  String proxyToken();

  /// Peers of the tailnet plus the path traffic takes to each, as JSON.
  @async
  String peersJSON();

  /// Measures round-trip time to host:port through the node, as JSON.
  @async
  String pingPeer(String hostPort);
}
