import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../state/intake_stats.dart';
import '../theme.dart';
import 'chart_style.dart';

/// 週/月的每日長條圖,附每日目標參考線(灰色虛線)。
///
/// 單一數列,所有長條同色;是否達標由參考線判讀,不另外換色。
/// 未來的日子不畫長條。週顯示星期,月每 5 天標一次日期。
class PeriodBarChart extends StatelessWidget {
  const PeriodBarChart({super.key, required this.stats, required this.isMonth});

  final PeriodStats stats;
  final bool isMonth;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final maxY = niceMax(math.max(s.goalMl ?? 0, s.maxMl).toDouble() * 1.05);
    final interval = niceInterval(maxY);
    return LayoutBuilder(builder: (context, c) {
      final plotWidth = math.max(0.0, c.maxWidth - ChartStyle.leftReserved);
      final slot = plotWidth / s.dayCount;
      // 長條最寬 24,其餘留白;月檢視在手機上約 5–6 px。
      final barWidth = math.min(24.0, math.max(2.0, slot * 0.6));
      final radius = Radius.circular(math.min(4.0, barWidth / 2));
      return SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(
              show: true,
              border:
                  const Border(bottom: BorderSide(color: ChartStyle.grid, width: 1)),
            ),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: ChartStyle.grid, strokeWidth: 1),
            ),
            extraLinesData: ExtraLinesData(horizontalLines: [
              // 沒有目標(照護系統尚未設定)就不畫目標線。
              if (s.hasGoal)
                HorizontalLine(
                  y: s.goalMl!.toDouble(),
                  color: ChartStyle.reference,
                  strokeWidth: 1.5,
                  dashArray: const [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(right: 2, bottom: 2),
                    style: ChartStyle.axisText,
                    labelResolver: (_) => '目標 ${fmtMl(s.goalMl!)}',
                  ),
                ),
            ]),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: ChartStyle.leftReserved,
                  interval: interval,
                  getTitlesWidget: (v, meta) => v % interval != 0
                      ? const SizedBox.shrink()
                      : SideTitleWidget(
                          meta: meta,
                          child: Text(axisMl(v), style: ChartStyle.axisText),
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= s.days.length) return const SizedBox.shrink();
                    final d = s.days[i].day;
                    final String label;
                    if (isMonth) {
                      if (d.day != 1 && d.day % 5 != 0) {
                        return const SizedBox.shrink();
                      }
                      label = '${d.day}';
                    } else {
                      label = weekdayNames[d.weekday - 1];
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(label, style: ChartStyle.axisText),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < s.days.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: s.days[i].isFuture ? 0 : s.days[i].ml.toDouble(),
                      width: barWidth,
                      color: ChartStyle.data,
                      borderRadius: BorderRadius.vertical(top: radius),
                    ),
                  ],
                ),
            ],
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.ink,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                tooltipBorderRadius: BorderRadius.circular(6),
                getTooltipItem: (group, _, _, _) {
                  final d = s.days[group.x];
                  if (d.isFuture) return null;
                  return BarTooltipItem(
                    '${fmtMonthDay(d.day)}\n${fmtMl(d.ml)} mL',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  );
                },
              ),
            ),
          ),
          duration: Duration.zero,
        ),
      );
    });
  }
}
