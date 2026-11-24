import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

/// 統計圖表共用的樣式與格式。
///
/// 依資料視覺化原則:資料用主色(teal)且線條細;格線與座標軸是淡灰細線;
/// 參考線(目標、理想進度)用灰色虛線,讓資料本身最醒目。
class ChartStyle {
  ChartStyle._();

  /// 資料主色。
  static const data = AppColors.teal;

  /// 面積填色:主色約 10% 透明度。
  static final dataWash = AppColors.teal.withValues(alpha: 0.10);

  /// 清醒時段(06–20)底色:比面積更淡。
  static final wakingBand = AppColors.teal.withValues(alpha: 0.05);

  /// 參考線(理想進度、目標)。
  static const reference = Color(0xFF8C9A9A);

  /// 格線:比卡片外框再淡一點的實線。
  static const grid = Color(0xFFE9EFEE);

  /// 座標軸文字。
  static const axisText = TextStyle(fontSize: 11, color: AppColors.muted);

  /// 左側 Y 軸保留寬度;上下兩張日圖必須一致,X 軸才對得齊。
  static const leftReserved = 40.0;

  static const lineWidth = 2.0;
  static const dotRadius = 4.0;
}

final _ml = NumberFormat('#,##0');

/// 1250 → 「1,250」。
String fmtMl(num ml) => _ml.format(ml.round());

/// Duration → 「h:mm」。
String fmtDuration(Duration d) {
  final m = d.inMinutes;
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 「11/23(一)」。
String fmtMonthDay(DateTime d) =>
    '${d.month}/${d.day}(${weekdayNames[d.weekday - 1]})';

/// 取一個「好讀」的刻度間距,讓 [maxValue] 最多分成 [ticks] 格。
double niceInterval(double maxValue, {int ticks = 5}) {
  if (maxValue <= 0) return 100;
  final raw = maxValue / ticks;
  const steps = [25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000];
  for (final s in steps) {
    if (raw <= s) return s.toDouble();
  }
  return 10000;
}

/// Y 軸上限:不小於 [maxValue] 的最小刻度倍數。
double niceMax(double maxValue, {int ticks = 5}) {
  final i = niceInterval(maxValue, ticks: ticks);
  final m = (maxValue / i).ceil() * i;
  return m <= 0 ? i : m;
}

/// Y 軸刻度文字:1,000 以下照寫,以上寫成「1.5k」以免擠壓。
String axisMl(double v) {
  if (v >= 1000) {
    final k = v / 1000;
    return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}k';
  }
  return v.toStringAsFixed(0);
}

/// 圖例中的一個項目:短線段 + 文字(文字用一般字色,不用資料色)。
class LegendKey extends StatelessWidget {
  const LegendKey({
    super.key,
    required this.label,
    required this.color,
    this.dashed = false,
  });

  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 10,
          child: CustomPaint(painter: _KeyPainter(color, dashed)),
        ),
        const SizedBox(width: 4),
        Text(label, style: mutedSmall),
      ],
    );
  }
}

class _KeyPainter extends CustomPainter {
  _KeyPainter(this.color, this.dashed);

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), p);
      return;
    }
    for (var x = 1.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, y), Offset((x + 4).clamp(0, size.width - 1), y), p);
    }
  }

  @override
  bool shouldRepaint(_KeyPainter old) => old.color != color || old.dashed != dashed;
}
