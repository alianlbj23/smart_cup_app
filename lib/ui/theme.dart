import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const teal = Color(0xFF0E8A84);
  static const orange = Color(0xFFD9691E);
  static const red = Color(0xFFC0392B);
  static const bg = Color(0xFFF1F6F6);
  static const border = Color(0xFFDFE8E7);
  static const ink = Color(0xFF1F2D2D);
  static const muted = Color(0xFF6B7A7A);

  // 夜間色(水杯休眠中):柔和的靛藍,和警示用的橘/紅區隔,不會讓人以為出錯。
  /// 休眠的主色:圖示、強調文字。
  static const night = Color(0xFF4A55C4);

  /// 休眠的深色字:橫幅大標題。
  static const nightInk = Color(0xFF2A3178);

  /// 休眠時的柔和灰靛:淡化顯示最後的姿態。
  static const nightMuted = Color(0xFF9097C2);

  /// 休眠橫幅底色與外框。
  static const nightBg = Color(0xFFEEF0FC);
  static const nightBorder = Color(0xFFD3D7F4);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    primary: AppColors.teal,
    surface: Colors.white,
    onSurface: AppColors.ink,
    error: AppColors.red,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    filledButtonTheme:
        FilledButtonThemeData(style: FilledButton.styleFrom(shape: shape)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// 白底圓角卡片,對應設計稿的區塊外框。
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // 用 Material 而非 DecoratedBox,內部 ListTile/InkWell 的水波紋才看得到。
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

const mutedSmall = TextStyle(fontSize: 12, color: AppColors.muted);

String fmtTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 經過時間:「12 秒」、「3 分 05 秒」、「2 小時 07 分」。負值視為 0。
String fmtDuration(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600, m = total % 3600 ~/ 60, s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  if (h > 0) return '$h 小時 ${two(m)} 分';
  if (m > 0) return '$m 分 ${two(s)} 秒';
  return '$s 秒';
}
