import 'package:flutter/material.dart';

import '../models/resident.dart';
import '../services/device_store.dart';
import '../state/care_store.dart';
import '../state/cup_connection_manager.dart';
import 'theme.dart';

/// 住民與其配對水杯之間的連線狀況。
enum CupLink {
  /// 尚未配對水杯。
  none,

  /// 已配對但未連線。
  offline,

  /// 尋找/連線中。
  linking,

  /// 自動重連逾時找不到。
  notFound,
  connected,
}

CupLink cupLinkOf(CupConnectionManager m, Resident r) {
  final id = r.cupId;
  if (id == null) return CupLink.none;
  final isTarget = m.activeDeviceId == id ||
      (m.flow == CupFlow.reconnect && m.rememberedDevice?.id == id);
  if (!isTarget) return CupLink.offline;
  return switch (m.state) {
    CupConnectionState.ready =>
      m.activeDeviceId == id ? CupLink.connected : CupLink.offline,
    CupConnectionState.notFound => CupLink.notFound,
    CupConnectionState.idle => CupLink.offline,
    _ => CupLink.linking,
  };
}

String cupDisplayName(String? name) =>
    (name == null || name.isEmpty) ? '智慧水杯' : name;

(String, Color) _linkStyle(CupLink link) => switch (link) {
      CupLink.none => ('未配對', AppColors.muted),
      CupLink.offline => ('未連線', AppColors.muted),
      CupLink.linking => ('連線中', AppColors.orange),
      CupLink.notFound => ('找不到水杯', AppColors.red),
      CupLink.connected => ('已連線', AppColors.teal),
    };

/// 水杯連線狀態標籤。
class CupStatusPill extends StatelessWidget {
  const CupStatusPill({super.key, required this.link});

  final CupLink link;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _linkStyle(link);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            link == CupLink.connected
                ? Icons.bluetooth_connected
                : Icons.local_drink_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// 連線到住民已配對的水杯。
void connectCup(CupConnectionManager manager, Resident r) {
  final id = r.cupId;
  if (id == null) return;
  manager.reconnectTo(RememberedDevice(id: id, name: r.cupName ?? ''));
}

/// 解除住民與水杯的配對(確認後)。
Future<void> unpairCup(
  BuildContext context,
  CupConnectionManager manager,
  CareStore store,
  Resident r,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('解除水杯配對?'),
      content: Text(
        '將解除「${r.name}」與「${cupDisplayName(r.cupName)}」的配對,'
        '之後需重新配對。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('解除配對'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await releaseCup(manager, store, r);
}

/// 移除配對;若該水杯是目前記憶/連線的水杯則一併斷線並忘記。
Future<void> releaseCup(
  CupConnectionManager manager,
  CareStore store,
  Resident r,
) async {
  final cupId = r.cupId;
  if (cupId == null) return;
  await store.unassignCup(r.id);
  if (manager.rememberedDevice?.id == cupId ||
      manager.activeDeviceId == cupId) {
    await manager.forgetDevice();
  }
}

/// 為 [resident] 掃描並配對水杯;連線成功後寫入配對並關閉。
Future<void> showCupPairingDialog(
  BuildContext context,
  CupConnectionManager manager,
  CareStore store,
  Resident resident,
) async {
  manager.beginPairing();
  final paired = await showDialog<bool>(
    context: context,
    builder: (context) => _CupPairingDialog(
      manager: manager,
      store: store,
      resident: resident,
    ),
  );
  if (paired != true) await manager.cancelPairing();
}

class _CupPairingDialog extends StatefulWidget {
  const _CupPairingDialog({
    required this.manager,
    required this.store,
    required this.resident,
  });

  final CupConnectionManager manager;
  final CareStore store;
  final Resident resident;

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
        widget.store
            .assignCup(widget.resident.id, pending, m.connectingName ?? '');
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
      title: Text('為「${widget.resident.name}」配對水杯'),
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
                        final owner = widget.store.ownerOfCup(d.deviceId);
                        final movedFrom =
                            owner != null && owner.id != widget.resident.id
                                ? owner
                                : null;
                        return ListTile(
                          enabled: !connecting,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 24),
                          leading: const Icon(Icons.local_drink,
                              color: AppColors.teal),
                          title: Text(cupDisplayName(d.deviceName)),
                          subtitle: Text(
                            movedFrom == null
                                ? d.deviceId
                                : '${d.deviceId}\n目前配對給 ${movedFrom.name},'
                                    '選擇後改配給 ${widget.resident.name}',
                            style: mutedSmall,
                          ),
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
