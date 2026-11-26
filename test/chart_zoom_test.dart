import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/ui/stats/chart_zoom.dart';
import 'package:stut_food_intake_project/ui/theme.dart';

void main() {
  /// 最近一次 builder 收到的放大倍率。
  late double scale;

  Future<void> pumpChart(WidgetTester tester, {double width = 600}) async {
    scale = 1;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ChartZoom(
              maxScale: 24,
              builder: (context, config, s) {
                scale = s;
                return SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: 24,
                      minY: 0,
                      maxY: 100,
                      lineBarsData: [
                        LineChartBarData(
                            spots: const [FlSpot(0, 0), FlSpot(24, 100)]),
                      ],
                    ),
                    transformationConfig: config,
                    duration: Duration.zero,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    final center = tester.getCenter(find.byType(LineChart));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  Finder resetButton() => find.widgetWithText(TextButton, '還原');

  testWidgets('一開始沒有放大,不顯示「還原」', (tester) async {
    await pumpChart(tester);

    expect(scale, 1);
    expect(resetButton(), findsNothing);
    expect(find.text('雙指、滾輪或 + − 可以放大'), findsOneWidget);
  });

  group('「+」「−」按鈕', () {
    IconButton button(WidgetTester tester, String tooltip) =>
        tester.widget<IconButton>(find.widgetWithIcon(
            IconButton,
            tooltip == '放大'
                ? Icons.add_circle_outline
                : Icons.remove_circle_outline));

    testWidgets('按「+」放大一級,按「−」縮回來', (tester) async {
      await pumpChart(tester);
      expect(button(tester, '縮小').onPressed, isNull); // 還沒放大,不能再縮

      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      expect(scale, closeTo(ChartZoom.buttonStep, 0.001));
      expect(resetButton(), findsOneWidget);

      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      expect(scale,
          closeTo(ChartZoom.buttonStep * ChartZoom.buttonStep, 0.001));

      await tester.tap(find.byTooltip('縮小'));
      await tester.pump();
      await tester.tap(find.byTooltip('縮小'));
      await tester.pump();
      expect(scale, 1);
      expect(resetButton(), findsNothing);
    });

    testWidgets('放到最大後「+」不能再按', (tester) async {
      await pumpChart(tester);

      for (var i = 0; i < 12; i++) {
        if (button(tester, '放大').onPressed == null) break;
        await tester.tap(find.byTooltip('放大'));
        await tester.pump();
      }

      expect(scale, closeTo(24, 0.001));
      expect(button(tester, '放大').onPressed, isNull);
      expect(button(tester, '縮小').onPressed, isNotNull);
    });

    testWidgets('用按鈕放大後,滾輪還能接著縮放', (tester) async {
      await pumpChart(tester);
      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      final afterButton = scale;

      await wheel(tester, -200);

      expect(scale, greaterThan(afterButton));
    });
  });

  testWidgets('滑鼠滾輪往上 → 放大;往下 → 縮小,最小回到原本大小', (tester) async {
    await pumpChart(tester);

    await wheel(tester, -200);
    final zoomed = scale;
    expect(zoomed, greaterThan(1));
    expect(resetButton(), findsOneWidget);

    await wheel(tester, 100);
    expect(scale, lessThan(zoomed));

    await wheel(tester, 5000);
    expect(scale, closeTo(1, 0.001));
    expect(resetButton(), findsNothing);
  });

  testWidgets('放大有上限', (tester) async {
    await pumpChart(tester);

    for (var i = 0; i < 30; i++) {
      await wheel(tester, -400);
    }

    expect(scale, closeTo(24, 0.001));
  });

  testWidgets('雙指張開 → 放大', (tester) async {
    await pumpChart(tester);
    final center = tester.getCenter(find.byType(LineChart));

    final a = await tester.startGesture(center - const Offset(20, 0), pointer: 1);
    final b = await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(-20, 0));
      await b.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    expect(scale, greaterThan(1.5));
    expect(resetButton(), findsOneWidget);
  });

  testWidgets('按「還原」→ 回到原本大小', (tester) async {
    await pumpChart(tester);
    await wheel(tester, -300);
    expect(scale, greaterThan(1));

    await tester.tap(resetButton());
    await tester.pumpAndSettle();

    expect(scale, 1);
    expect(resetButton(), findsNothing);
  });

  testWidgets('手機寬度不會溢位', (tester) async {
    await pumpChart(tester, width: 300);
    await wheel(tester, -300);

    expect(resetButton(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('時間軸的刻度隨放大倍率變細', () {
    expect(hourIntervalForScale(1), 6);
    expect(hourIntervalForScale(2), 3);
    expect(hourIntervalForScale(4), 2);
    expect(hourIntervalForScale(8), 1);
    expect(hourIntervalForScale(16), 0.5);
    expect(hourIntervalForScale(24), 0.5);
  });

  test('時間軸的文字:整點只寫小時,半點寫時分', () {
    expect(hourAxisLabel(0), '00');
    expect(hourAxisLabel(6), '06');
    expect(hourAxisLabel(14.5), '14:30');
    expect(hourAxisLabel(24), '24');
  });
}
