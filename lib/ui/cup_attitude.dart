import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/ble_service.dart';
import '../state/cup_connection_manager.dart';
import 'theme.dart';

/// 姿態動畫時間:ATTITUDE 約每 200 ms 一筆,動畫略長一點讓畫面連續。
const _attitudeAnimation = Duration(milliseconds: 250);

/// roll 絕對值小於此角度(度)時,側視圖改用 pitch 的正負號決定旋轉方向。
const _rollSignThreshold = 1.0;

/// 「水杯姿態」面板內容:杯子側視圖、水平儀(俯視)、傾斜角數值與姿態標籤。
///
/// 姿態角來自 ATTITUDE(0x05),姿態分類與移動旗標來自 POSE(0x04),
/// 杯內水量取最新 WATER(0x02)。未連線或資料過期時以灰色呈現。
class CupAttitude extends StatelessWidget {
  const CupAttitude({super.key, required this.manager, required this.now});

  final CupConnectionManager manager;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final connected = manager.state == CupConnectionState.ready;
    final attitude = manager.latestAttitude;
    final attitudeStale = !connected || manager.isAttitudeStale(now);
    final color = attitude == null || attitudeStale
        ? AppColors.muted
        : AppColors.teal;

    final water = manager.latestWater;
    final waterStale = !connected || manager.isWaterStale(now);
    final waterColor = water == null || waterStale
        ? AppColors.muted
        : AppColors.teal;

    final pose = manager.latestPose;
    final poseStale = !connected || manager.isPoseStale(now);

    final updatedAt = manager.latestAttitudeAt;
    final status = !connected
        ? '水杯未連線'
        : attitude == null
        ? '已連線,等待姿態資料…'
        : attitudeStale
        ? '姿態資料過期 · 更新於 ${fmtTime(updatedAt!)}'
        : '即時姿態 · 更新於 ${fmtTime(updatedAt!)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '水杯姿態',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        Text(
          status,
          style: mutedSmall.copyWith(
            color: connected && attitudeStale && attitude != null
                ? AppColors.orange
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _captioned(
              '側視',
              CupTiltView(
                angleDegrees: attitude == null ? 0 : cupSideAngle(attitude),
                fillFraction: water?.fillFraction ?? 0,
                outlineColor: color == AppColors.muted
                    ? AppColors.muted
                    : AppColors.ink,
                waterColor: waterColor,
              ),
            ),
            _captioned(
              '水平儀(俯視)',
              BubbleLevel(
                rollDegrees: attitude?.rollDegrees,
                pitchDegrees: attitude?.pitchDegrees,
                color: color,
              ),
            ),
            _readout(attitude, color, pose, poseStale),
          ],
        ),
      ],
    );
  }

  static Widget _captioned(String caption, Widget child) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      const SizedBox(height: 4),
      Text(caption, style: mutedSmall),
    ],
  );

  Widget _readout(
    AttitudePacket? attitude,
    Color color,
    PosePacket? pose,
    bool poseStale,
  ) {
    const figures = [FontFeature.tabularFigures()];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          attitude == null
              ? '傾斜 --'
              : '傾斜 ${attitude.tiltDegrees.toStringAsFixed(1)}°',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: figures,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          attitude == null
              ? 'pitch -- · roll --'
              : 'pitch ${_signed(attitude.pitchDegrees)} · '
                    'roll ${_signed(attitude.rollDegrees)}',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.muted,
            fontFeatures: figures,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              icon: Icons.local_drink_outlined,
              label: pose == null ? '姿態 --' : pose.pose.label,
              color: pose == null || poseStale
                  ? AppColors.muted
                  : _poseColor(pose.pose),
            ),
            _chip(
              icon: pose?.moving ?? false
                  ? Icons.vibration
                  : Icons.pause_circle_outline,
              label: pose == null ? '移動 --' : (pose.moving ? '移動中' : '靜止'),
              color: pose == null || poseStale
                  ? AppColors.muted
                  : pose.moving
                  ? AppColors.orange
                  : AppColors.teal,
            ),
          ],
        ),
      ],
    );
  }

  static String _signed(double deg) =>
      '${deg > 0 ? '+' : ''}${deg.toStringAsFixed(1)}°';

  static Color _poseColor(CupPose pose) => switch (pose) {
    CupPose.upright || CupPose.drinking => AppColors.teal,
    CupPose.tilted => AppColors.orange,
    CupPose.lying => AppColors.red,
    CupPose.unknown => AppColors.muted,
  };

  static Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) => Chip(
    avatar: Icon(icon, size: 18, color: color),
    label: Text(label),
    labelStyle: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: color,
    ),
    backgroundColor: color.withValues(alpha: 0.12),
    side: BorderSide(color: color.withValues(alpha: 0.5)),
    shape: const StadiumBorder(),
    visualDensity: VisualDensity.compact,
  );
}

/// 側視圖的杯子旋轉角(度,順時針為正):大小為總傾斜角,
/// 方向取 roll 的正負號(正 = 杯口往右);roll ≈ 0 時改用 pitch 的正負號。
double cupSideAngle(AttitudePacket a) {
  final sign = a.rollDegrees.abs() >= _rollSignThreshold
      ? a.rollDegrees.sign
      : (a.pitchDegrees == 0 ? 1.0 : a.pitchDegrees.sign);
  return sign * a.tiltDegrees;
}

/// 杯子側視圖:杯身依 [angleDegrees] 旋轉(有平滑動畫),杯內水面保持水平。
class CupTiltView extends StatelessWidget {
  const CupTiltView({
    super.key,
    required this.angleDegrees,
    required this.fillFraction,
    required this.outlineColor,
    required this.waterColor,
    this.size = 140,
  });

  /// 順時針為正,-180..180。
  final double angleDegrees;
  final double fillFraction;
  final Color outlineColor;
  final Color waterColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: fillFraction.clamp(0.0, 1.0)),
      duration: _attitudeAnimation,
      curve: Curves.easeOut,
      builder: (context, fill, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: angleDegrees),
        duration: _attitudeAnimation,
        curve: Curves.easeOut,
        builder: (context, angle, _) => CustomPaint(
          size: Size.square(size),
          painter: _CupTiltPainter(
            angleRadians: angle * math.pi / 180,
            fill: fill,
            outlineColor: outlineColor,
            waterColor: waterColor,
          ),
        ),
      ),
    );
  }
}

class _CupTiltPainter extends CustomPainter {
  _CupTiltPainter({
    required this.angleRadians,
    required this.fill,
    required this.outlineColor,
    required this.waterColor,
  });

  final double angleRadians;
  final double fill;
  final Color outlineColor;
  final Color waterColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    // 鉛垂參考線(世界座標)。
    final guide = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      guide,
    );

    // 杯形比例同 CupGauge(72 × 120,杯底圓角較大);任何角度都要放得進方框。
    const cupW = 72.0, cupH = 120.0;
    final scale =
        size.shortestSide * 0.92 / math.sqrt(cupW * cupW + cupH * cupH);
    final interior = cupInteriorPolygon(
      width: cupW * scale,
      height: cupH * scale,
      topRadius: 6 * scale,
      bottomRadius: 18 * scale,
    );
    final water = cupWaterPolygon(interior, fill, angleRadians);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angleRadians);

    canvas.drawPath(_path(interior), Paint()..color = AppColors.bg);
    if (water.length >= 3) {
      canvas.drawPath(
        _path(water),
        Paint()..color = waterColor.withValues(alpha: 0.85),
      );
    }
    // 杯身外框;杯口(上緣)畫粗線以分辨上下。
    canvas.drawPath(
      _path(interior),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = outlineColor.withValues(alpha: 0.6),
    );
    final rimY = -cupH * scale / 2;
    canvas.drawLine(
      Offset(-cupW * scale / 2 - 3, rimY),
      Offset(cupW * scale / 2 + 3, rimY),
      Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = outlineColor,
    );
    canvas.restore();
  }

  static Path _path(List<Offset> pts) => Path()..addPolygon(pts, true);

  @override
  bool shouldRepaint(_CupTiltPainter old) =>
      old.angleRadians != angleRadians ||
      old.fill != fill ||
      old.outlineColor != outlineColor ||
      old.waterColor != waterColor;
}

/// 杯子內部輪廓(杯子局部座標,原點在杯身中心,y 向下,杯口在上),
/// 上方兩角為小圓角、杯底兩角為大圓角,以多邊形近似。
List<Offset> cupInteriorPolygon({
  required double width,
  required double height,
  required double topRadius,
  required double bottomRadius,
  int arcSegments = 8,
}) {
  final hw = width / 2, hh = height / 2;
  final pts = <Offset>[];
  void arc(Offset c, double r, double from) {
    for (var i = 0; i <= arcSegments; i++) {
      final a = from + (math.pi / 2) * i / arcSegments;
      pts.add(c + Offset(math.cos(a), math.sin(a)) * r);
    }
  }

  // 順時針(螢幕座標):左上 → 右上 → 右下 → 左下。
  arc(Offset(-hw + topRadius, -hh + topRadius), topRadius, math.pi);
  arc(Offset(hw - topRadius, -hh + topRadius), topRadius, -math.pi / 2);
  arc(Offset(hw - bottomRadius, hh - bottomRadius), bottomRadius, 0);
  arc(Offset(-hw + bottomRadius, hh - bottomRadius), bottomRadius, math.pi / 2);
  return pts;
}

/// 杯子轉了 [angleRadians](螢幕上順時針為正)時,杯內的水所占的多邊形
/// (杯子局部座標)。水面在世界座標保持水平,面積 = [fraction] × 杯內面積。
///
/// 做法:世界的「下方」在杯子局部座標為 d = (sin θ, cos θ);水 = 杯內
/// 滿足 p·d ≥ h 的部分,以半平面裁切多邊形並二分搜尋 h 使面積符合。
/// 傾斜超過 90° 時視為杯口封閉(水量照感測值畫,堆在杯口那側),不會崩潰。
List<Offset> cupWaterPolygon(
  List<Offset> interior,
  double fraction,
  double angleRadians,
) {
  if (interior.length < 3 || !fraction.isFinite || fraction <= 0) {
    return const [];
  }
  if (fraction >= 1) return interior;

  final d = Offset(math.sin(angleRadians), math.cos(angleRadians));
  double proj(Offset p) => p.dx * d.dx + p.dy * d.dy;
  var lo = interior.map(proj).reduce(math.min);
  var hi = interior.map(proj).reduce(math.max);
  final target = fraction * polygonArea(interior);

  var best = const <Offset>[];
  for (var i = 0; i < 40; i++) {
    final h = (lo + hi) / 2;
    final clipped = _clipHalfPlane(interior, d, h);
    // h 越大,水越少。
    if (polygonArea(clipped) > target) {
      lo = h;
    } else {
      hi = h;
    }
    best = clipped;
  }
  return best;
}

/// 保留多邊形中 p·d ≥ h 的部分(Sutherland–Hodgman,單一半平面)。
List<Offset> _clipHalfPlane(List<Offset> poly, Offset d, double h) {
  double side(Offset p) => p.dx * d.dx + p.dy * d.dy - h;
  final out = <Offset>[];
  for (var i = 0; i < poly.length; i++) {
    final cur = poly[i];
    final prev = poly[(i + poly.length - 1) % poly.length];
    final sc = side(cur), sp = side(prev);
    if ((sc >= 0) != (sp >= 0)) {
      out.add(Offset.lerp(prev, cur, sp / (sp - sc))!);
    }
    if (sc >= 0) out.add(cur);
  }
  return out;
}

/// 多邊形面積(鞋帶公式,取絕對值)。
double polygonArea(List<Offset> poly) {
  if (poly.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

/// 水平儀(俯視):圓圈 + 十字線,點的位置 = (roll, pitch)。
///
/// |角度| 90° 對應到圓周,超出則貼在圓周上;pitch 正往畫面上方。
/// 沒有資料([rollDegrees] 或 [pitchDegrees] 為 null)時不畫點。
class BubbleLevel extends StatelessWidget {
  const BubbleLevel({
    super.key,
    required this.rollDegrees,
    required this.pitchDegrees,
    required this.color,
    this.size = 140,
  });

  final double? rollDegrees;
  final double? pitchDegrees;
  final Color color;
  final double size;

  /// 點的位置(單位圓內,x 向右、y 向下);沒資料時為 null。
  static Offset? dotPosition(double? roll, double? pitch) {
    if (roll == null || pitch == null) return null;
    var v = Offset(roll / 90, -pitch / 90);
    if (v.distance > 1) v = v / v.distance;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final dot = dotPosition(rollDegrees, pitchDegrees);
    return TweenAnimationBuilder<Offset>(
      tween: Tween(end: dot ?? Offset.zero),
      duration: _attitudeAnimation,
      curve: Curves.easeOut,
      builder: (context, pos, _) => CustomPaint(
        size: Size.square(size),
        painter: _BubbleLevelPainter(
          dot: dot == null ? null : pos,
          color: color,
        ),
      ),
    );
  }
}

class _BubbleLevelPainter extends CustomPainter {
  _BubbleLevelPainter({required this.dot, required this.color});

  final Offset? dot;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const dotRadius = 8.0;
    final r = size.shortestSide / 2 - dotRadius - 1;

    canvas.drawCircle(c, r, Paint()..color = AppColors.bg);
    final line = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // 45° 參考圈與十字線。
    canvas.drawCircle(c, r / 2, line);
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), line);
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), line);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    final d = dot;
    if (d == null) return;
    canvas.drawCircle(c + d * r, dotRadius, Paint()..color = color);
    canvas.drawCircle(
      c + d * r,
      dotRadius,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_BubbleLevelPainter old) =>
      old.dot != dot || old.color != color;
}
