import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const teal = Color(0xFF0E8A84);
  static const tealSoft = Color(0xFFD5EEEB);
  static const orange = Color(0xFFD9691E);
  static const red = Color(0xFFC0392B);
  static const bg = Color(0xFFF1F6F6);
  static const sidebar = Color(0xFFEAF3F2);
  static const border = Color(0xFFDFE8E7);
  static const track = Color(0xFFE3EAEA);
  static const ink = Color(0xFF1F2D2D);
  static const muted = Color(0xFF6B7A7A);
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

/// 圓角進度條;[value] 超過 1 時顯示為滿格。
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.color = AppColors.teal,
    this.height = 5,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0).toDouble(),
        minHeight: height,
        color: color,
        backgroundColor: AppColors.track,
      ),
    );
  }
}

const mutedSmall = TextStyle(fontSize: 12, color: AppColors.muted);

/// 千分位格式,例如 1500 → 1,500。
String fmtMl(int ml) => ml.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

String fmtTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
