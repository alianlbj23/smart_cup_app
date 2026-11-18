import 'package:flutter/material.dart';

import '../services/ble_service.dart';
import '../state/cup_connection_manager.dart';
import 'theme.dart';

/// 水杯目前水量(連續水位圖 + 數值)。資料直接取自韌體,不做換算。
///
/// 姿態顯示在另一個面板(`cup_attitude.dart`)。
class CupReading extends StatelessWidget {
  const CupReading({super.key, required this.manager, required this.now});

  final CupConnectionManager manager;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final water = manager.latestWater;
    final connected = manager.state == CupConnectionState.ready;
    final stale = !connected || manager.isWaterStale(now);
    final color = water == null || stale ? AppColors.muted : AppColors.teal;
    final updatedAt = manager.latestWaterAt;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupGauge(fraction: water?.fillFraction ?? 0, color: color),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 窄螢幕放不下時縮小字級,不溢位。
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        water == null
                            ? '--'
                            : water.fillPercent.toStringAsFixed(4),
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: color,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child:
                        Text('%', style: TextStyle(fontSize: 14, color: color)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                !connected
                    ? (water == null
                        ? '水杯未連線'
                        : '水杯未連線 · 最後更新 ${fmtTime(updatedAt!)}')
                    : water == null
                        ? '已連線,等待第一筆水量…'
                        : stale
                            ? '資料過期 · 更新於 ${fmtTime(updatedAt!)}'
                            : 'fill25 ${water.fill25} · 刻度 ${water.level} · '
                                '更新於 ${fmtTime(updatedAt!)}',
                style: mutedSmall.copyWith(
                    color: stale && water != null ? AppColors.orange : null),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 連續水位圖:杯形容器,水面高度 = [fraction](0..1),變化時有動畫。
class CupGauge extends StatelessWidget {
  const CupGauge({
    super.key,
    required this.fraction,
    required this.color,
    this.width = 72,
    this.height = 120,
  });

  final double fraction;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border, width: 2),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(6),
          bottom: Radius.circular(18),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          widthFactor: 1,
          heightFactor: f,
          child: Container(color: color.withValues(alpha: 0.85)),
        ),
      ),
    );
  }
}

/// 接收紀錄一行的文字。
String describePacket(CupDataPacket p) => switch (p) {
      WaterPacket() =>
        '水量 ${p.fillPercent.toStringAsFixed(4)}% · 刻度 ${p.level} · '
            'fill25 ${p.fill25}',
      RawPacket() => '原始值 ${p.count}',
      PosePacket() =>
        '姿態 ${p.pose.label} · ${p.tiltDegrees.toStringAsFixed(1)}°'
            '${p.moving ? ' · 移動中' : ''}',
      // 即時資料不會寫入接收紀錄,此處僅為 switch 完整性。
      AttitudePacket() =>
        '姿態角 pitch ${p.pitchDegrees.toStringAsFixed(1)}° · '
            'roll ${p.rollDegrees.toStringAsFixed(1)}°',
      DummyDataPacket() => '測試值 ${p.value}',
      UnknownPacket() =>
        '未知 type 0x${p.type.toRadixString(16)} · ${p.value}',
    };
