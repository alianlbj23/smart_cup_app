import 'package:flutter/material.dart';

import 'theme.dart';

/// 電量標示:電池圖示(格數跟著電量變)+ 大字百分比,依電量變色。
///
/// - 40% 以上:teal
/// - 20～39%:橘色
/// - 低於 20%:紅色,圖示改成警告
/// - [percent] 為 null(韌體回報未知,例如沒接電池):灰色「--」
class BatteryBadge extends StatelessWidget {
  const BatteryBadge({super.key, required this.percent});

  final int? percent;

  static const lowThreshold = 20;
  static const mediumThreshold = 40;

  /// 電量對應的顏色。
  static Color colorFor(int? percent) {
    if (percent == null) return AppColors.muted;
    if (percent < lowThreshold) return AppColors.red;
    if (percent < mediumThreshold) return AppColors.orange;
    return AppColors.teal;
  }

  /// 電量對應的圖示。
  static IconData iconFor(int? percent) {
    if (percent == null) return Icons.battery_unknown;
    if (percent < lowThreshold) return Icons.battery_alert;
    if (percent >= 95) return Icons.battery_full;
    const bars = [
      Icons.battery_0_bar,
      Icons.battery_1_bar,
      Icons.battery_2_bar,
      Icons.battery_3_bar,
      Icons.battery_4_bar,
      Icons.battery_5_bar,
      Icons.battery_6_bar,
    ];
    return bars[(percent * 7 ~/ 100).clamp(0, bars.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(percent);
    return Semantics(
      label: percent == null ? '電量未知' : '電量 $percent%',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(percent), color: color, size: 30),
          const SizedBox(width: 2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                percent == null ? '--' : '$percent%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(percent == null ? '電量未知' : '電量', style: mutedSmall),
            ],
          ),
        ],
      ),
    );
  }
}
