import 'package:flutter/material.dart';

import '../services/ble_service.dart';
import '../state/cup_connection_manager.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.manager});

  final CupConnectionManager manager;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('智慧水杯'),
          actions: [
            if (manager.rememberedDevice != null)
              IconButton(
                tooltip: '忘記此裝置',
                icon: const Icon(Icons.link_off),
                onPressed: () => _confirmForget(context),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusBanner(manager: manager),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (manager.state) {
      case CupConnectionState.ready:
        return _ReadyView(manager: manager);
      case CupConnectionState.notFound:
        return _NotFoundView(manager: manager);
      case CupConnectionState.connecting:
      case CupConnectionState.connected:
      case CupConnectionState.serviceDiscovered:
        return _Progress(
          text: '正在連線「${manager.connectingName ?? ''}」…',
          onCancel: manager.disconnect,
        );
      case CupConnectionState.scanning:
      case CupConnectionState.idle:
        if (manager.flow == CupFlow.reconnect &&
            manager.state == CupConnectionState.scanning) {
          return _Progress(
            text: '正在尋找「${_name(manager.rememberedDevice?.name)}」…',
            onCancel: manager.disconnect,
          );
        }
        if (manager.flow == CupFlow.reconnect ||
            (manager.rememberedDevice != null &&
                manager.scanResults.isEmpty &&
                !manager.pairingScanActive)) {
          return _IdleRememberedView(manager: manager);
        }
        return _PairingView(manager: manager);
    }
  }

  Future<void> _confirmForget(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('忘記此裝置?'),
        content: Text(
          '將清除「${_name(manager.rememberedDevice?.name)}」的記憶,'
          '之後需重新配對。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('忘記'),
          ),
        ],
      ),
    );
    if (ok == true) await manager.forgetDevice();
  }
}

String _name(String? name) =>
    (name == null || name.isEmpty) ? '智慧水杯' : name;

String _stateLabel(CupConnectionState s) => switch (s) {
      CupConnectionState.idle => '閒置',
      CupConnectionState.scanning => '掃描中',
      CupConnectionState.connecting => '連線中',
      CupConnectionState.connected => '已連線',
      CupConnectionState.serviceDiscovered => '初始化中',
      CupConnectionState.ready => '就緒',
      CupConnectionState.notFound => '找不到裝置',
    };

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.manager});

  final CupConnectionManager manager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = manager.state == CupConnectionState.ready;
    return Material(
      color: ready ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ready ? Icons.bluetooth_connected : Icons.bluetooth,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _stateLabel(manager.state),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  manager.flow == CupFlow.pairing ? '手動配對' : '自動重連',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            if (manager.rememberedDevice case final d?)
              Text(
                '記憶裝置:${_name(d.name)}(${d.id})',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (manager.message case final msg?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(msg, style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.text, required this.onCancel});

  final String text;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(text),
          const SizedBox(height: 16),
          TextButton(onPressed: onCancel, child: const Text('取消')),
        ],
      ),
    );
  }
}

class _PairingView extends StatelessWidget {
  const _PairingView({required this.manager});

  final CupConnectionManager manager;

  @override
  Widget build(BuildContext context) {
    final results = manager.scanResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  manager.pairingScanActive
                      ? '正在搜尋附近的智慧水杯…'
                      : '掃描已結束,點選裝置進行配對',
                ),
              ),
              if (manager.pairingScanActive)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton.icon(
                  onPressed: manager.startPairingScan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新掃描'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: results.isEmpty
              ? const Center(child: Text('尚未找到裝置'))
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _ScanTile(
                    result: results[i],
                    onTap: () => manager.connectTo(results[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.result, required this.onTap});

  final BleDeviceInfo result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.local_drink),
      title: Text(_name(result.deviceName)),
      subtitle: Text(result.deviceId),
      trailing: Text('${result.rssi} dBm'),
      onTap: onTap,
    );
  }
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView({required this.manager});

  final CupConnectionManager manager;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 48),
            const SizedBox(height: 16),
            Text('找不到「${_name(manager.rememberedDevice?.name)}」'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: manager.startAutoReconnect,
              child: const Text('重試'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: manager.startPairingScan,
              child: const Text('切換回手動配對'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdleRememberedView extends StatelessWidget {
  const _IdleRememberedView({required this.manager});

  final CupConnectionManager manager;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: manager.startAutoReconnect,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text('連線「${_name(manager.rememberedDevice?.name)}」'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: manager.startPairingScan,
            child: const Text('手動配對其他裝置'),
          ),
        ],
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.manager});

  final CupConnectionManager manager;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final latest = manager.log.lastOrNull;
    final status = manager.deviceStatus;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('最新資料(dummy)', style: text.labelLarge),
                const SizedBox(height: 8),
                Text(
                  latest == null ? '--' : '${latest.packet.value}',
                  style: text.displayMedium,
                ),
                if (latest != null)
                  Text('裝置時間:${_fmt(latest.packet.time)}'),
                Text('已接收 ${manager.receivedCount} 筆'),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.battery_std),
            title: Text(
              status == null ? '裝置狀態讀取中…' : '電量 ${status.batteryPercent}%',
            ),
            subtitle: status == null
                ? null
                : Text('韌體版本 ${status.firmwareVersion}'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: manager.disconnect,
          icon: const Icon(Icons.bluetooth_disabled),
          label: const Text('中斷連線'),
        ),
        const SizedBox(height: 16),
        Text('接收紀錄', style: text.titleSmall),
        for (final e in manager.log.reversed)
          ListTile(
            dense: true,
            title: Text('value=${e.packet.value}'),
            subtitle: Text('ts=${e.packet.timestamp} · 收到 ${_fmt(e.receivedAt)}'),
            trailing: Icon(
              e.acked ? Icons.done_all : Icons.schedule,
              size: 18,
            ),
          ),
      ],
    );
  }

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
