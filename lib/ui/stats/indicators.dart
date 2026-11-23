import 'package:flutter/material.dart';

import '../../state/intake_stats.dart';
import '../theme.dart';
import 'chart_style.dart';

/// 最集中時段占比達到此值(且喝了 2 次以上)視為「集中」。
const concentratedShare = 0.7;

/// 最長未喝水間隔達到此長度視為「間隔太久」。
const longGap = Duration(hours: 4);

/// 時段覆蓋率達到此值視為「分布平均」。
const evenCoverage = 0.7;

/// 一句白話的分布結論,放在三個指標下方。
///
/// 判斷順序:沒喝水 → 集中 → 間隔太久 → 平均 → 其他。
String distributionVerdict(DayStats s) {
  if (s.drinks.isEmpty) {
    return s.isToday ? '今天還沒有喝水紀錄' : '這天沒有喝水紀錄';
  }
  final peak = s.peak!;
  if (s.drinks.length >= 2 && peak.share >= concentratedShare) {
    return '集中在 ${fmtTime(peak.start)}–${fmtTime(peak.end)},'
        '這段喝了 ${(peak.share * 100).round()}%';
  }
  final gap = s.longestGap;
  if (gap != null && gap.duration >= longGap) {
    return gap.ongoing
        ? '已經 ${fmtDuration(gap.duration)} 沒喝水了,記得補充'
        : '${fmtTime(gap.start)}–${fmtTime(gap.end)} 有 '
            '${fmtDuration(gap.duration)} 沒喝水';
  }
  if (s.drinks.length == 1) return '只喝了 1 次,可以分成少量多次';
  if (s.slotsEligible > 0 && s.slotsCovered / s.slotsEligible >= evenCoverage) {
    return '分布平均';
  }
  return '大致分散,可以再平均一點';
}

/// 三個「集中 vs 分散」指標與結論。
class DistributionIndicators extends StatelessWidget {
  const DistributionIndicators({super.key, required this.stats});

  final DayStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final partial = s.isToday && s.slotsEligible < wakingSlotCount;
    final peak = s.peak;
    final gap = s.longestGap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Tile(
                  label: '時段覆蓋',
                  value: partial
                      ? '${s.slotsCovered}/${s.slotsEligible}'
                      : '${s.slotsCovered}/$wakingSlotCount',
                  detail: partial ? '已過 ${s.slotsEligible} 段' : '06–20 每 2 小時',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Tile(
                  label: '最集中時段占比',
                  value: peak == null ? '—' : '${(peak.share * 100).round()}%',
                  detail: peak == null
                      ? '沒有喝水'
                      : '${fmtTime(peak.start)}–${fmtTime(peak.end)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Tile(
                  label: '最長未喝水間隔',
                  value: gap == null ? '—' : fmtDuration(gap.duration),
                  detail: gap == null
                      ? '06:00 後開始'
                      : '${fmtTime(gap.start)}–${gap.ongoing ? '現在' : fmtTime(gap.end)}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.insights, size: 16, color: AppColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                distributionVerdict(s),
                key: const ValueKey('distribution-verdict'),
                style: const TextStyle(fontSize: 13, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.detail});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: mutedSmall, maxLines: 2),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink),
            ),
          ),
          Text(detail,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
              maxLines: 2),
        ],
      ),
    );
  }
}
