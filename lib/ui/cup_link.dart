import 'package:flutter/material.dart';

import '../state/cup_connection_manager.dart';
import 'theme.dart';

String cupDisplayName(String? name) =>
    (name == null || name.isEmpty) ? '智慧水杯' : name;

String cupStateLabel(CupConnectionState s) => switch (s) {
      CupConnectionState.idle => '未連線',
      CupConnectionState.scanning => '搜尋中',
      CupConnectionState.connecting => '連線中',
      CupConnectionState.connected => '已連線,初始化中',
      CupConnectionState.serviceDiscovered => '初始化中',
      CupConnectionState.ready => '已連線',
      CupConnectionState.notFound => '找不到水杯',
    };

/// 忘記目前的水杯(確認後):斷線並清除記憶,之後需重新配對。
Future<void> confirmForgetCup(
  BuildContext context,
  CupConnectionManager manager,
) async {
  final name = cupDisplayName(
      manager.connectingName ?? manager.rememberedDevice?.name);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('忘記此水杯?'),
      content: Text('將中斷並忘記「$name」,之後需重新配對。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('忘記'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await manager.forgetDevice();
}

/// 掃描並配對水杯;連線成功後關閉,取消則回頭連線先前的水杯。
Future<void> showCupPairingDialog(
  BuildContext context,
  CupConnectionManager manager,
) async {
  manager.beginPairing();
  final paired = await showDialog<bool>(
    context: context,
    builder: (context) => _CupPairingDialog(manager: manager),
  );
  if (paired != true) await manager.cancelPairing();
}

class _CupPairingDialog extends StatefulWidget {
  const _CupPairingDialog({required this.manager});

  final CupConnectionManager manager;

  @override
  State<_CupPairingDialog> createState() => _CupPairingDialogState();
}

class _CupPairingDialogState extends State<_CupPairingDialog> {
  /// 使用者選擇、正在連線的水杯。
  String? _pendingId;

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_onManager);
  }

  @override
  void dispose() {
    widget.manager.removeListener(_onManager);
    super.dispose();
  }

  void _onManager() {
    if (!mounted) return;
    final m = widget.manager;
    final pending = _pendingId;
    if (pending != null) {
      if (m.state == CupConnectionState.ready && m.activeDeviceId == pending) {
        _pendingId = null;
        Navigator.pop(context, true);
        return;
      }
      if (m.state == CupConnectionState.idle ||
          m.state == CupConnectionState.notFound) {
        _pendingId = null;
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final connecting = _pendingId != null;
    return AlertDialog(
      title: const Text('配對水杯'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 420,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      connecting
                          ? '正在連線「${cupDisplayName(m.connectingName)}」…'
                          : m.pairingScanActive
                              ? '正在搜尋附近的智慧水杯…'
                              : '掃描已結束,點選水杯進行配對',
                      style: mutedSmall.copyWith(fontSize: 13),
                    ),
                  ),
                  if (connecting || m.pairingScanActive)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton.icon(
                      onPressed: m.startPairingScan,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重新掃描'),
                    ),
                ],
              ),
            ),
            if (m.message case final msg?)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                child: Text(msg,
                    style: const TextStyle(fontSize: 13, color: AppColors.red)),
              ),
            const SizedBox(height: 8),
            const Divider(),
            Expanded(
              child: m.scanResults.isEmpty
                  ? const Center(
                      child: Text('尚未找到水杯\n請確認水杯已開機並靠近手機',
                          textAlign: TextAlign.center, style: mutedSmall),
                    )
                  : ListView.separated(
                      itemCount: m.scanResults.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final d = m.scanResults[i];
                        return ListTile(
                          enabled: !connecting,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 24),
                          leading: const Icon(Icons.local_drink,
                              color: AppColors.teal),
                          title: Text(cupDisplayName(d.deviceName)),
                          subtitle: Text(d.deviceId, style: mutedSmall),
                          trailing: Text('${d.rssi} dBm', style: mutedSmall),
                          onTap: () {
                            setState(() => _pendingId = d.deviceId);
                            m.connectTo(d);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
