import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/tailnet/tailnet_peer.model.dart';
import 'package:immich_mobile/models/tailnet/tailnet_status.model.dart';
import 'package:immich_mobile/providers/tailnet.provider.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:url_launcher/url_launcher.dart';

/// Card for the embedded Tailscale node that lives inside this app.
///
/// The node is a userspace one: it never takes the system VPN slot, and only
/// traffic to the tailnet is routed through it. See TailnetProxySelector on the
/// Android side.
class TailnetPreference extends HookConsumerWidget {
  const TailnetPreference({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledAsync = ref.watch(tailnetEnabledProvider);
    final status = ref.watch(tailnetStatusProvider).valueOrNull ?? const TailnetStatus();
    final enabled = enabledAsync.valueOrNull ?? false;
    final peers = ref.watch(tailnetPeersProvider).valueOrNull ?? const <TailnetPeer>[];
    final authKeyController = useTextEditingController();
    final busy = useState(false);
    final ping = useState<TailnetPing?>(null);

    Future<void> run(Future<void> Function() action) async {
      busy.value = true;
      try {
        await action();
        // background_downloader keeps its own proxy setting; keep it in sync.
        await applyTailnetProxyToDownloader(ref.read(tailnetApiProvider));
        ref.invalidate(tailnetEnabledProvider);
      } on Exception catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
        }
      } finally {
        busy.value = false;
      }
    }

    Future<void> measure() async {
      final target = _serverHostPort();
      if (target == null) {
        ping.value = const TailnetPing(ok: false, error: '还没有配置服务器地址');
        return;
      }
      busy.value = true;
      try {
        ping.value = await ref.read(tailnetActionsProvider).ping(target);
      } finally {
        busy.value = false;
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: context.colorScheme.surfaceContainerHighest, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: enabled,
            onChanged: busy.value
                ? null
                : (value) => run(() => ref.read(tailnetActionsProvider).setEnabled(value)),
            title: const Text('Tailscale 远程访问'),
            subtitle: Text(_describe(status, enabled)),
            secondary: Icon(
              enabled ? Icons.vpn_lock_outlined : Icons.vpn_lock_rounded,
              color: enabled ? context.primaryColor : null,
            ),
          ),
          if (enabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _Details(
                status: status,
                busy: busy.value,
                authKeyController: authKeyController,
                peers: peers,
                ping: ping.value,
                onPing: measure,
                onSignIn: () => run(() => ref.read(tailnetActionsProvider).signIn(authKeyController.text)),
                onSignOut: () => run(() => ref.read(tailnetActionsProvider).signOut()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// host:port of the server the app is currently talking to, if any.
  String? _serverHostPort() {
    final url = getServerUrl();
    if (url == null) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return '${uri.host}:$port';
  }

  String _describe(TailnetStatus status, bool enabled) {
    if (!enabled) {
      return '开启后仅本应用的请求走隧道，不占系统 VPN';
    }
    if (status.isRunning) {
      return '已连接${status.tailnet != null ? ' · ${status.tailnet}' : ''}';
    }
    if (status.needsSignIn) {
      return '需要在浏览器完成一次登录';
    }
    if (status.state == 'Stopped') {
      return '已断开，可在下方重新连接';
    }
    if (status.error != null) {
      return '连接失败：${status.error}';
    }
    return '正在连接…';
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.status,
    required this.busy,
    required this.authKeyController,
    required this.peers,
    required this.ping,
    required this.onPing,
    required this.onSignIn,
    required this.onSignOut,
  });

  final TailnetStatus status;
  final bool busy;
  final TextEditingController authKeyController;
  final List<TailnetPeer> peers;
  final TailnetPing? ping;
  final Future<void> Function() onPing;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    if (status.isRunning) {
      final online = peers.where((p) => p.online).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line(context, '地址', status.ips.isEmpty ? status.dnsName ?? '--' : status.ips.join(', ')),
          if (status.loginName != null) _line(context, '账号', status.loginName!),
          if (online.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('连接方式', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            for (final peer in online.take(4)) _peerLine(context, peer),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : () => unawaited(onPing()),
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: const Text('测试延迟'),
              ),
              const SizedBox(width: 8),
              Expanded(child: _pingLabel(context)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: busy ? null : () => unawaited(onSignOut()),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('退出登录'),
            ),
          ),
        ],
      );
    }

    if (status.needsSignIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('这个 tailnet 需要给本机授权一次。两种方式选一个：'),
          const SizedBox(height: 8),
          if (status.authUrl != null)
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(status.authUrl!), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('在浏览器中登录'),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: authKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '或者粘贴 auth key',
              hintText: 'tskey-auth-…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: busy ? null : () => unawaited(onSignIn()),
              child: const Text('用密钥登录'),
            ),
          ),
        ],
      );
    }

    if (status.state == 'Stopped') {
      return Row(
        children: [
          const Icon(Icons.link_off_rounded, size: 18),
          const SizedBox(width: 12),
          const Expanded(child: Text('节点已停止')),
          FilledButton.tonal(
            onPressed: busy ? null : () => unawaited(onSignIn()),
            child: const Text('重新连接'),
          ),
        ],
      );
    }

    return Row(
      children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(child: Text(status.error ?? '正在启动内嵌节点…')),
      ],
    );
  }

  Widget _pingLabel(BuildContext context) {
    final result = ping;
    if (result == null) {
      return const Text('尚未测试', style: TextStyle(fontSize: 12));
    }
    if (!result.ok) {
      return Text(
        '失败：${result.error ?? '无响应'}',
        style: const TextStyle(fontSize: 12, color: Colors.red),
      );
    }
    final latency = result.latencyMs;
    final ms = latency == null ? '--' : latency.toStringAsFixed(latency < 10 ? 1 : 0);
    final detail = result.via == 'derp' && result.relay != null
        ? '${tailnetViaLabel(result.via)} ${result.relay}'
        : tailnetViaLabel(result.via);
    return Text(
      '$ms ms · $detail',
      style: TextStyle(fontSize: 12, color: context.primaryColor),
    );
  }

  Widget _peerLine(BuildContext context, TailnetPeer peer) {
    final detail = peer.via == 'derp'
        ? '${tailnetViaLabel(peer.via)}${peer.relay != null ? ' ${peer.relay}' : ''}'
        : '${tailnetViaLabel(peer.via)}${peer.endpoint != null ? ' ${peer.endpoint}' : ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(peer.hostName, style: const TextStyle(fontSize: 12)),
          ),
          Text(detail, style: TextStyle(fontSize: 12, color: context.primaryColor)),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 48, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: SelectableText(value, style: TextStyle(fontSize: 12, color: context.primaryColor)),
        ),
      ],
    ),
  );
}
