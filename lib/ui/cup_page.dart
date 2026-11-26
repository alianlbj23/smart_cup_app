import 'package:flutter/material.dart';

import '../state/cup_connection_manager.dart';
import 'battery_badge.dart';
import 'cup_attitude.dart';
import 'cup_link.dart';
import 'cup_reading.dart';
import 'doze_banner.dart';
import 'theme.dart';

/// 水杯裝置:目前連線、水量與姿態。App 一次連線一個水杯。
class CupPage extends StatelessWidget {
  const CupPage({super.key, required this.manager, required this.now});

  final CupConnectionManager manager;
  final DateTime now;

  /// 休眠橫幅出現/消失的淡入淡出時間。
  static const dozeTransition = Duration(milliseconds: 350);

  bool get _ready => manager.state == CupConnectionState.ready;

  @override
  Widget build(BuildContext context) {
    final dozing = _ready && manager.isDozing(now);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _connectionPanel(context, dozing: dozing),
        const SizedBox(height: 12),
        // 連線且休眠中:醒目的休眠橫幅,進入/離開時淡入淡出並展開/收合。
        AnimatedSwitcher(
          duration: dozeTransition,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: dozing
              ? Padding(
                  key: const ValueKey('doze-banner'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: const DozeBanner(),
                )
              : const SizedBox(key: ValueKey('awake'), width: double.infinity),
        ),
        // 水位圖永遠顯示;未連線或資料過期時以灰色呈現(休眠中照常顯示)。
        Panel(child: CupReading(manager: manager, now: now)),
        const SizedBox(height: 12),
        // 姿態面板同樣永遠顯示;未連線或資料過期時以灰色呈現。
        Panel(child: CupAttitude(manager: manager, now: now)),
      ],
    );
  }

  Widget _connectionPanel(BuildContext context, {required bool dozing}) {
    final m = manager;
    final ready = _ready;
    final busy = m.state == CupConnectionState.scanning ||
        m.state == CupConnectionState.connecting ||
        m.state == CupConnectionState.connected ||
        m.state == CupConnectionState.serviceDiscovered;
    final remembered = m.rememberedDevice;
    final cupId = m.activeDeviceId ?? remembered?.id;
    final cupName =
        m.activeDeviceId != null ? m.connectingName : remembered?.name;
    final status = m.deviceStatus;
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
                    // 休眠中連線仍保持,只在狀態後面加註「休眠中」。
                    Text.rich(
                      TextSpan(
                        text: '目前連線:${cupStateLabel(m.state)}',
                        children: [
                          if (dozing)
                            const TextSpan(
                              text: ' · 休眠中',
                              style: TextStyle(color: AppColors.night),
                            ),
                        ],
                      ),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    if (cupId != null)
                      Text(
                        '${cupDisplayName(cupName)} · $cupId',
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
              // 電量:連線且讀到 Device Status 後才顯示
              if (ready && status != null) ...[
                const SizedBox(width: 12),
                BatteryBadge(percent: status.batteryPercent),
              ],
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
}
