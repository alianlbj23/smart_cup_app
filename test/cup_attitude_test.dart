import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/ui/cup_attitude.dart';

void main() {
  final cup = cupInteriorPolygon(
    width: 72,
    height: 120,
    topRadius: 6,
    bottomRadius: 18,
  );
  final cupArea = polygonArea(cup);

  group('cupWaterPolygon', () {
    test('直立:水面水平且面積 = fraction × 杯內面積,水在杯底', () {
      final water = cupWaterPolygon(cup, 0.5, 0);
      expect(polygonArea(water), closeTo(cupArea * 0.5, cupArea * 1e-4));
      // 水在杯底(y 向下為正),最高點不會高過杯身中線太多。
      expect(water.map((p) => p.dy).reduce(math.max), closeTo(60, 1e-6));
    });

    test('各種傾斜角(含超過 90° 與倒立)面積都正確、不崩潰', () {
      for (final deg in [
        -180,
        -135,
        -90,
        -45,
        -10,
        0,
        30,
        89,
        90,
        91,
        150,
        180,
      ]) {
        for (final f in [0.05, 0.3, 0.75, 0.99]) {
          final angle = deg * math.pi / 180;
          final water = cupWaterPolygon(cup, f, angle);
          expect(
            polygonArea(water),
            closeTo(cupArea * f, cupArea * 1e-3),
            reason: '$deg° fill $f',
          );
          // 水面在世界座標水平:水的點投影到「世界下方」都 ≥ 水面高度。
          final down = Offset(math.sin(angle), math.cos(angle));
          final proj = water.map((p) => p.dx * down.dx + p.dy * down.dy);
          final level = proj.reduce(math.min);
          final onSurface = proj.where((v) => (v - level).abs() < 1e-6);
          expect(
            onSurface.length,
            greaterThanOrEqualTo(2),
            reason: '水面是一條水平線段($deg°)',
          );
        }
      }
    });

    test('空杯、滿杯與異常值', () {
      expect(cupWaterPolygon(cup, 0, 0.3), isEmpty);
      expect(cupWaterPolygon(cup, -1, 0.3), isEmpty);
      expect(cupWaterPolygon(cup, double.nan, 0.3), isEmpty);
      expect(polygonArea(cupWaterPolygon(cup, 1, 0.3)), closeTo(cupArea, 1e-9));
      expect(polygonArea(cupWaterPolygon(cup, 2, 0.3)), closeTo(cupArea, 1e-9));
    });
  });

  group('cupSideAngle', () {
    AttitudePacket a(int pitch, int roll) => AttitudePacket(
      pitchDeciDegrees: pitch,
      rollDeciDegrees: roll,
      timestamp: 0,
    );

    test('方向取 roll 的正負號', () {
      expect(cupSideAngle(a(0, 300)), closeTo(30, 1e-9));
      expect(cupSideAngle(a(0, -300)), closeTo(-30, 1e-9));
      expect(cupSideAngle(a(-400, 300)), greaterThan(30));
    });

    test('roll ≈ 0 時改用 pitch 的正負號', () {
      expect(cupSideAngle(a(450, 0)), closeTo(45, 1e-9));
      expect(cupSideAngle(a(-450, 5)), closeTo(-45, 0.1));
      expect(cupSideAngle(a(0, 0)), 0);
    });
  });

  group('BubbleLevel.dotPosition', () {
    test('90° 對應圓周,pitch 正往上,超出貼在圓周', () {
      expect(BubbleLevel.dotPosition(null, 0), isNull);
      expect(BubbleLevel.dotPosition(0, 0), Offset.zero);
      expect(BubbleLevel.dotPosition(45, 0), const Offset(0.5, 0));
      expect(BubbleLevel.dotPosition(0, 90), const Offset(0, -1));
      final clamped = BubbleLevel.dotPosition(-180, 0)!;
      expect(clamped.dx, closeTo(-1, 1e-9));
      final diag = BubbleLevel.dotPosition(90, -90)!;
      expect(diag.distance, closeTo(1, 1e-9));
      expect(diag.dx, greaterThan(0));
      expect(diag.dy, greaterThan(0));
    });
  });
}
