import 'package:flutter/material.dart';

import '../state/cup_connection_manager.dart';
import 'cup_link.dart';
import 'cup_reading.dart';
import 'theme.dart';

/// 水杯裝置:目前連線、水量/姿態與接收紀錄。App 一次連線一個水杯。
class CupPage extends StatelessWidget {
  const CupPage({super.key, required this.manager, required this.now});

  final CupConnectionManager manager;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _connectionPanel(context),
        const SizedBox(height: 12),
        // 水位圖永遠顯示;未連線或資料過期時以灰色呈現。
        Panel(child: CupReading(manager: manager, now: now)),
        const SizedBox(height: 12),
        _logPanel(),
      ],
    );
  }

  Widget _connectionPanel(BuildContext context) {
    final m = manager;
    final ready = m.state == CupConnectionState.ready;
    final busy = m.state == CupConnectionState.scanning ||
        m.state == CupConnectionState.connecting ||
        m.state == CupConnectionState.connected ||
        m.state == CupConnectionState.serviceDiscovered;
    final remembered = m.rememberedDevice;
    final cupId = m.activeDeviceId ?? remembered?.id;
    final cupName =
        m.activeDeviceId != null ? m.connectingName : remembered?.name;
    final battery = m.deviceStatus?.batteryPercent;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.bluetooth_connected : Icons.bluetooth,
                color: ready ? AppColors.teal : AppColors.muted,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('目前連線:${cupStateLabel(m.state)}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (cupId != null)
                      Text(
                        [
                          cupDisplayName(cupName),
                          cupId,
                          if (ready && battery != null) '電量 $battery%',
                        ].join(' · '),
                        style: mutedSmall,
                      )
                    else
                      const Text('尚未配對水杯,按「配對水杯」搜尋附近的水杯',
                          style: mutedSmall),
                    if (m.message case final msg?)
                      Text(msg,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.red)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (ready || busy)
                OutlinedButton(
                  onPressed: m.disconnect,
                  child: Text(ready ? '中斷連線' : '取消'),
                )
              else if (remembered != null)
                FilledButton(
                  onPressed: m.startAutoReconnect,
                  child: Text(m.state == CupConnectionState.notFound
                      ? '重試'
                      : '連線'),
                ),
              if (!busy)
                FilledButton.tonalIcon(
                  onPressed: () => showCupPairingDialog(context, m),
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: Text(remembered == null ? '配對水杯' : '配對其他水杯'),
                ),
              if (!busy && remembered != null)
                TextButton(
                  onPressed: () => confirmForgetCup(context, m),
                  child: const Text('忘記此水杯'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _logPanel() {
    final log = manager.log.reversed.toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('水杯資料接收紀錄',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Text(
            '水量與姿態來自韌體;原始值僅供除錯 · '
            '已接收 ${manager.receivedCount} 筆',
            style: mutedSmall,
          ),
          const SizedBox(height: 8),
          if (log.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('尚未收到資料', style: mutedSmall),
            ),
          for (final e in log)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(e.acked ? Icons.done_all : Icons.schedule,
                      size: 16, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(describePacket(e.packet))),
                  Text('${fmtTime(e.receivedAt)} 收到', style: mutedSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
