import 'package:flutter/material.dart';

import '../services/ble_service.dart';
import '../state/cup_connection_manager.dart';
import 'theme.dart';

/// 水杯目前水量(主數字 + 10 格刻度)與姿態。資料直接取自韌體,不做換算。
class CupReading extends StatelessWidget {
  const CupReading({super.key, required this.manager, required this.now});

  final CupConnectionManager manager;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final water = manager.latestWater;
    final stale = manager.isWaterStale(now);
    final color = water == null || stale ? AppColors.muted : AppColors.teal;
    final updatedAt = manager.latestWaterAt;
    final pose = manager.latestPose;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              water == null ? '--' : water.fillPercent.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('%', style: TextStyle(fontSize: 14, color: color)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LevelBar(level: water?.level ?? 0, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          water == null
              ? '尚未收到水量'
              : stale
                  ? '資料過期 · 更新於 ${fmtTime(updatedAt!)}'
                  : '刻度 ${water.level}/${WaterPacket.maxLevel} · '
                      '更新於 ${fmtTime(updatedAt!)}',
          style: mutedSmall.copyWith(
              color: stale && water != null ? AppColors.orange : null),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.screen_rotation_alt,
                size: 15, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(
              pose == null
                  ? '姿態 --'
                  : '姿態 ${pose.pose.label} · '
                      '傾斜 ${pose.tiltDegrees.toStringAsFixed(1)}° · '
                      '${pose.moving ? '移動中' : '靜止'}',
              style: mutedSmall,
            ),
          ],
        ),
      ],
    );
  }
}

/// 0..[WaterPacket.maxLevel] 的 10 格刻度。
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.level, required this.color});

  final int level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= WaterPacket.maxLevel; i++) ...[
          Expanded(
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: i <= level ? color : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < WaterPacket.maxLevel) const SizedBox(width: 2),
        ],
      ],
    );
  }
}

/// 接收紀錄一行的文字。
String describePacket(CupDataPacket p) => switch (p) {
      WaterPacket() =>
        '水量 ${p.fillPercent.toStringAsFixed(2)}% · 刻度 ${p.level}',
      RawPacket() => '原始值 ${p.count}',
      PosePacket() =>
        '姿態 ${p.pose.label} · ${p.tiltDegrees.toStringAsFixed(1)}°'
            '${p.moving ? ' · 移動中' : ''}',
      DummyDataPacket() => '測試值 ${p.value}',
      UnknownPacket() =>
        '未知 type 0x${p.type.toRadixString(16)} · ${p.value}',
    };
