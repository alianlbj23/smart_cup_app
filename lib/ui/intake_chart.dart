import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/resident.dart';
import 'theme.dart';

/// 當日累積飲水曲線:實線為實際累積量,虛線為個人目標進度。
class IntakeChart extends StatelessWidget {
  const IntakeChart({
    super.key,
    required this.entries,
    required this.goalMl,
    required this.now,
  });

  /// 當日的飲水紀錄(依時間排序)。
  final List<IntakeEntry> entries;
  final int goalMl;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ChartPainter(entries, goalMl, now),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.entries, this.goalMl, this.now);

  final List<IntakeEntry> entries;
  final int goalMl;
  final DateTime now;

  static double _hours(DateTime t) => t.hour + t.minute / 60;

  @override
  void paint(Canvas canvas, Size size) {
    const scheduleStart = HydrationSchedule.startHour;
    const scheduleEnd = HydrationSchedule.endHour;

    // 時程外(清晨/夜間)有紀錄或現在已過時程時,延伸時間軸。
    final nowH = _hours(now);
    final startH = entries.any((e) => e.time.hour < scheduleStart)
        ? 0.0
        : scheduleStart.toDouble();
    final endH = (nowH > scheduleEnd ||
            entries.any((e) => _hours(e.time) > scheduleEnd))
        ? 24.0
        : scheduleEnd.toDouble();

    final total = entries.fold(0, (sum, e) => sum + e.ml);
    final yStep = math.max(goalMl, total) > 2000 ? 1000 : 500;
    final yMax =
        math.max(1, (math.max(goalMl, total) / yStep).ceil()) * yStep;

    final plot = Rect.fromLTRB(44, 18, size.width - 20, size.height - 26);
    double x(double h) =>
        plot.left + (h - startH) / (endH - startH) * plot.width;
    double y(num ml) => plot.bottom - ml / yMax * plot.height;

    final grid = Paint()
      ..color = AppColors.track
      ..strokeWidth = 1;
    for (var v = 0; v <= yMax; v += yStep) {
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      _text(canvas, '$v', Offset(plot.left - 8, y(v)), alignRight: true);
    }
    for (var h = startH.toInt(); h <= endH; h += endH - startH > 14 ? 4 : 2) {
      _text(
        canvas,
        '${h.toString().padLeft(2, '0')}:00',
        Offset(x(h.toDouble()), plot.bottom + 12),
        center: true,
      );
    }

    // 目標進度(虛線):時程內線性上升,之後持平。
    final target = Path()
      ..moveTo(x(startH), y(0))
      ..lineTo(x(scheduleStart.toDouble()), y(0))
      ..lineTo(x(scheduleEnd.toDouble()), y(goalMl))
      ..lineTo(x(endH), y(goalMl));
    _dashed(
      canvas,
      target,
      Paint()
        ..color = AppColors.muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 實際累積量。
    final points = <Offset>[Offset(x(startH), y(0))];
    var sum = 0;
    for (final e in entries) {
      sum += e.ml;
      points.add(
          Offset(x(_hours(e.time).clamp(startH, endH).toDouble()), y(sum)));
    }
    final lastX = x(nowH.clamp(startH, endH).toDouble());
    if (lastX > points.last.dx) points.add(Offset(lastX, y(sum)));

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(points.last.dx, plot.bottom)
      ..lineTo(points.first.dx, plot.bottom)
      ..close();
    canvas.drawPath(
        area, Paint()..color = AppColors.teal.withValues(alpha: 0.12));
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in points) {
      canvas.drawCircle(p, 3.5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 2.5, Paint()..color = AppColors.teal);
    }
    _text(
      canvas,
      '${fmtMl(total)} mL',
      Offset(points.last.dx, points.last.dy - 12),
      alignRight: true,
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink),
    );
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(
            metric.extractPath(d, math.min(d + dash, metric.length)), paint);
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool alignRight = false,
    bool center = false,
    TextStyle style = const TextStyle(fontSize: 11, color: AppColors.muted),
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center
        ? anchor.dx - tp.width / 2
        : alignRight
            ? anchor.dx - tp.width
            : anchor.dx;
    tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
