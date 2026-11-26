import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../state/intake_stats.dart';
import '../theme.dart';
import 'chart_style.dart';
import 'chart_zoom.dart';

/// 一天的時間分布圖:上下兩張共用同一條 0–24 時的 X 軸。
///
/// - 上:累積飲水(階梯線)與理想進度(虛線,06:00 由 0 直線到 20:00 的目標),
///   同一個 mL 刻度,一眼看出「目前超前或落後」。
/// - 下:每一次喝水的量(棒棒糖),看出是一口氣喝很多還是少量多次。
///
/// 兩者量級不同(累積到 1,500 vs 單次 200),不放在同一張圖、也不用雙 Y 軸,
/// 改成上下對齊的兩張小圖。06–20 的清醒時段以淡色底標出。
///
/// 兩張圖可以沿時間軸一起放大、移動(見 [ChartZoom]);換一天就還原。
class DayDistributionChart extends StatelessWidget {
  const DayDistributionChart({super.key, required this.stats});

  final DayStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            const LegendKey(label: '累積飲水', color: ChartStyle.data),
            // 沒有目標(照護系統尚未設定)就沒有理想進度可畫。
            if (stats.hasGoal)
              const LegendKey(
                  label: '理想進度', color: ChartStyle.reference, dashed: true),
          ],
        ),
        const SizedBox(height: 8),
        ChartZoom(
          key: ValueKey(stats.day),
          // 最多放大到畫面寬度約等於 1 小時
          maxScale: 24,
          builder: (context, zoom, scale) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 170,
                child:
                    _CumulativeChart(stats: stats, zoom: zoom, scale: scale),
              ),
              const SizedBox(height: 12),
              const Text('每次喝水量', style: mutedSmall),
              const SizedBox(height: 4),
              // 高度包含 X 軸文字,避免卡片出現內捲動。
              SizedBox(
                height: 110,
                child:
                    _DrinkStemsChart(stats: stats, zoom: zoom, scale: scale),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 時間 → 圖上 X(小時,0–24)。
double _hourX(DateTime day, DateTime t) {
  final x = t.difference(day).inSeconds / 3600;
  return x.clamp(0, 24).toDouble();
}

FlGridData _grid(double yInterval, double hourInterval) => FlGridData(
      drawVerticalLine: true,
      verticalInterval: hourInterval,
      horizontalInterval: yInterval,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: ChartStyle.grid, strokeWidth: 1),
      getDrawingVerticalLine: (_) =>
          const FlLine(color: ChartStyle.grid, strokeWidth: 1),
    );

AxisTitles _leftTitles(double interval, double maxY) => AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: ChartStyle.leftReserved,
        interval: interval,
        getTitlesWidget: (v, meta) {
          // 只顯示刻度倍數,避免 fl_chart 自動加上的非整數上限。
          if (v % interval != 0) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            child: Text(axisMl(v), style: ChartStyle.axisText),
          );
        },
      ),
    );

AxisTitles _hourTitles({required bool show, required double interval}) =>
    AxisTitles(
      sideTitles: SideTitles(
        showTitles: show,
        reservedSize: 22,
        interval: interval,
        getTitlesWidget: (v, meta) => SideTitleWidget(
          meta: meta,
          child: Text(hourAxisLabel(v), style: ChartStyle.axisText),
        ),
      ),
    );

const _noTitles = AxisTitles(sideTitles: SideTitles(showTitles: false));

RangeAnnotations _wakingBand() => RangeAnnotations(
      verticalRangeAnnotations: [
        VerticalRangeAnnotation(
          x1: wakingStartHour.toDouble(),
          x2: wakingEndHour.toDouble(),
          color: ChartStyle.wakingBand,
        ),
      ],
    );

ExtraLinesData _nowLine(DayStats s) => ExtraLinesData(
      verticalLines: [
        if (s.isToday)
          VerticalLine(
            x: _hourX(s.day, s.now),
            color: ChartStyle.reference,
            strokeWidth: 1,
            label: VerticalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              padding: const EdgeInsets.only(left: 4, top: 0),
              style: ChartStyle.axisText,
              labelResolver: (_) => '現在',
            ),
          ),
      ],
    );

LineTouchTooltipData _tooltip(GetLineTooltipItems items) => LineTouchTooltipData(
      getTooltipColor: (_) => AppColors.ink,
      fitInsideHorizontally: true,
      fitInsideVertically: true,
      maxContentWidth: 180,
      tooltipBorderRadius: BorderRadius.circular(6),
      getTooltipItems: items,
    );

class _CumulativeChart extends StatelessWidget {
  const _CumulativeChart({
    required this.stats,
    required this.zoom,
    required this.scale,
  });

  final DayStats stats;
  final FlTransformationConfig zoom;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final maxY = niceMax(
        [s.goalMl ?? 0, s.totalMl].reduce((a, b) => a > b ? a : b).toDouble() * 1.05);
    final interval = niceInterval(maxY);
    final drinkXs = {for (final d in s.drinks) _hourX(s.day, d.time)};

    final cumulative = LineChartBarData(
      spots: [
        for (final p in s.cumulative)
          FlSpot(_hourX(s.day, p.time), p.ml.toDouble()),
      ],
      isStepLineChart: true,
      // 維持前一點的量,到下一次喝水時才往上跳。
      lineChartStepData:
          const LineChartStepData(stepDirection: LineChartStepData.stepDirectionForward),
      color: ChartStyle.data,
      barWidth: ChartStyle.lineWidth,
      isCurved: false,
      belowBarData: BarAreaData(show: true, color: ChartStyle.dataWash),
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, _) => spot.y > 0 && drinkXs.contains(spot.x),
        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
          radius: ChartStyle.dotRadius,
          color: ChartStyle.data,
          strokeWidth: 2,
          strokeColor: Colors.white,
        ),
      ),
    );

    final g = (s.goalMl ?? 0).toDouble();
    final ideal = LineChartBarData(
      spots: [
        const FlSpot(0, 0),
        FlSpot(wakingStartHour.toDouble(), 0),
        FlSpot(wakingEndHour.toDouble(), g),
        FlSpot(24, g),
      ],
      color: ChartStyle.reference,
      barWidth: 1.5,
      dashArray: const [6, 4],
      dotData: const FlDotData(show: false),
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: _grid(interval, hourIntervalForScale(scale)),
        borderData: FlBorderData(show: false),
        rangeAnnotations: _wakingBand(),
        extraLinesData: _nowLine(s),
        titlesData: FlTitlesData(
          leftTitles: _leftTitles(interval, maxY),
          bottomTitles: _hourTitles(
              show: true, interval: hourIntervalForScale(scale)),
          topTitles: _noTitles,
          rightTitles: _noTitles,
        ),
        // 沒有目標時只畫累積線。
        lineBarsData: [if (s.hasGoal) ideal, cumulative],
        lineTouchData: LineTouchData(
          getTouchedSpotIndicator: (bar, idx) => [
            for (final _ in idx)
              bar == ideal
                  ? null
                  : const TouchedSpotIndicatorData(
                      FlLine(color: ChartStyle.reference, strokeWidth: 1),
                      FlDotData(show: false),
                    ),
          ],
          touchTooltipData: _tooltip((spots) => [
                for (final sp in spots)
                  sp.bar == ideal
                      ? null
                      : LineTooltipItem(
                          '${_fmtHour(sp.x)} 累積 ${fmtMl(sp.y)} mL',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        ),
              ]),
        ),
      ),
      transformationConfig: zoom,
      duration: Duration.zero,
    );
  }
}

class _DrinkStemsChart extends StatelessWidget {
  const _DrinkStemsChart({
    required this.stats,
    required this.zoom,
    required this.scale,
  });

  final DayStats stats;
  final FlTransformationConfig zoom;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final biggest = s.drinks.fold(0, (m, d) => d.ml > m ? d.ml : m);
    final maxY = niceMax(biggest <= 0 ? 300 : biggest.toDouble(), ticks: 2);
    final interval = niceInterval(maxY, ticks: 2);

    final stems = [
      for (final d in s.drinks)
        LineChartBarData(
          spots: [
            FlSpot(_hourX(s.day, d.time), 0),
            FlSpot(_hourX(s.day, d.time), d.ml.toDouble()),
          ],
          color: ChartStyle.data,
          barWidth: ChartStyle.lineWidth,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, _) => spot.y > 0,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: ChartStyle.dotRadius,
              color: ChartStyle.data,
              strokeWidth: 2,
              strokeColor: Colors.white,
            ),
          ),
        ),
    ];

    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
        minY: 0,
        maxY: maxY,
        // 左右要裁切:放大後畫面外的棒子不能蓋到座標軸。上方不裁,頂端的圓點才完整。
        clipData: const FlClipData(
            top: false, bottom: false, left: true, right: true),
        gridData: _grid(interval, hourIntervalForScale(scale)),
        borderData: FlBorderData(
          show: true,
          border: const Border(
              bottom: BorderSide(color: ChartStyle.grid, width: 1)),
        ),
        rangeAnnotations: _wakingBand(),
        titlesData: FlTitlesData(
          leftTitles: _leftTitles(interval, maxY),
          bottomTitles: _hourTitles(
              show: true, interval: hourIntervalForScale(scale)),
          topTitles: _noTitles,
          rightTitles: _noTitles,
        ),
        lineBarsData: stems,
        lineTouchData: LineTouchData(
          touchSpotThreshold: 14,
          getTouchedSpotIndicator: (bar, idx) => [
            for (final _ in idx)
              const TouchedSpotIndicatorData(
                FlLine(color: Colors.transparent, strokeWidth: 0),
                FlDotData(show: false),
              ),
          ],
          touchTooltipData: _tooltip((spots) {
            // 同一時間只顯示一次;值取棒子頂端。
            final seen = <int>{};
            return [
              for (final sp in spots)
                seen.add(sp.barIndex)
                    ? LineTooltipItem(
                        '${_fmtHour(sp.x)} · ${fmtMl(sp.bar.spots.last.y)} mL',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      )
                    : null,
            ];
          }),
        ),
      ),
      transformationConfig: zoom,
      duration: Duration.zero,
    );

    if (s.drinks.isNotEmpty) return chart;
    return Stack(
      children: [
        Positioned.fill(child: chart),
        const Positioned.fill(
          bottom: 22,
          left: ChartStyle.leftReserved,
          child: Center(child: Text('沒有喝水紀錄', style: mutedSmall)),
        ),
      ],
    );
  }
}

String _fmtHour(double x) {
  final m = (x * 60).round();
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}
