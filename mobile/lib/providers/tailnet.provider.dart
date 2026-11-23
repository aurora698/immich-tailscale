import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/tailnet/tailnet_peer.model.dart';
import 'package:immich_mobile/models/tailnet/tailnet_status.model.dart';
import 'package:immich_mobile/platform/tailnet_api.g.dart';

final tailnetApiProvider = Provider<TailnetApi>((_) => TailnetApi());

/// Whether the user has the embedded node turned on.
final tailnetEnabledProvider = FutureProvider.autoDispose<bool>((ref) => ref.watch(tailnetApiProvider).isEnabled());

/// Polls the node while something is watching (the settings page), so a
/// backgrounded app does not keep waking up.
final tailnetStatusProvider = StreamProvider.autoDispose<TailnetStatus>((ref) async* {
  final api = ref.watch(tailnetApiProvider);
  while (true) {
    try {
      final raw = await api.status();
      yield TailnetStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      yield TailnetStatus(state: 'Stopped', error: error.toString());
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
});

/// Actions the settings card needs, kept in one place so the widget stays dumb.
class TailnetActions {
  const TailnetActions(this._api);

  final TailnetApi _api;

  Future<void> setEnabled(bool enabled) => _api.setEnabled(enabled);

  Future<void> signIn(String authKey) => _api.start(authKey.trim());

  Future<void> stop() => _api.stop();

  Future<void> signOut() => _api.logout();

  /// Peers of the tailnet plus how traffic reaches each of them.
  Future<List<TailnetPeer>> peers() async {
    final raw = await _api.peersJSON();
    final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    return list.map(TailnetPeer.fromJson).toList();
  }

  /// Round-trip time to [hostPort], measured through the node.
  Future<TailnetPing> ping(String hostPort) async {
    final raw = await _api.pingPeer(hostPort);
    return TailnetPing.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

/// Peers are only interesting while the node runs, so this refreshes with it.
final tailnetPeersProvider = FutureProvider.autoDispose<List<TailnetPeer>>((ref) async {
  final status = ref.watch(tailnetStatusProvider).valueOrNull;
  if (status == null || !status.isRunning) {
    return const [];
  }
  return ref.watch(tailnetActionsProvider).peers();
});

final tailnetActionsProvider = Provider<TailnetActions>((ref) => TailnetActions(ref.watch(tailnetApiProvider)));

/// Points background_downloader's tasks at the embedded proxy.
///
/// Uploads and downloads run on HttpURLConnection, which ignores the platform
/// proxy selector, so they need the proxy set explicitly. Credentials are not
/// part of the config: the JVM-wide authenticator answers the proxy's 407.
Future<void> applyTailnetProxyToDownloader(TailnetApi api) async {
  final enabled = await api.isEnabled();
  final port = await api.proxyPort();
  if (!enabled || port <= 0) {
    await FileDownloader().configure(globalConfig: [(Config.proxy, false)]);
    return;
  }
  await FileDownloader().configure(globalConfig: [(Config.proxy, ('127.0.0.1', port))]);
}
