import 'package:flutter/material.dart';

import 'theme.dart';

/// 「水杯休眠中」橫幅:連線且休眠中時顯示在連線面板與水位面板之間。
///
/// 用夜間色(靛藍)而非警示色,讓人一眼看出是正常的休眠,而不是斷線或故障。
class DozeBanner extends StatelessWidget {
  const DozeBanner({super.key, required this.dozingFor});

  /// 已休眠多久;null 時不顯示時間那一行。
  final Duration? dozingFor;

  @override
  Widget build(BuildContext context) {
    final duration = dozingFor;
    return Semantics(
      container: true,
      child: Material(
        color: AppColors.nightBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.nightBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.night.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bedtime,
                  color: AppColors.night,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '水杯休眠中',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.nightInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '藍牙保持連線 · 拿起杯子就會喚醒',
                      style: TextStyle(fontSize: 13, color: AppColors.night),
                    ),
                    if (duration != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '已休眠 ${fmtDuration(duration)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.nightInk,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
