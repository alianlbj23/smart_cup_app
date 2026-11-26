import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/intake_repository.dart';
import '../state/intake_stats.dart';
import 'stats/chart_style.dart';
import 'stats/day_charts.dart';
import 'stats/event_dialog.dart';
import 'stats/indicators.dart';
import 'stats/period_chart.dart';
import 'theme.dart';

/// 統計檢視的範圍。
enum StatsRange { day, week, month }

/// 飲水統計:日 / 週 / 月。
///
/// 監聽 [repo],資料有變動就重新查詢。[clock] 決定「今天」與「現在」(測試用)。
/// 本身不含 Scaffold,放在 AppShell 的內容區即可;刪除後的「復原」提示
/// 需要上層有 ScaffoldMessenger(MaterialApp 預設就有)。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.repo, this.clock});

  final IntakeRepository repo;
  final DateTime Function()? clock;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

typedef _Period = ({DateTime from, DateTime to});

class _StatsPageState extends State<StatsPage> {
  StatsRange _range = StatsRange.day;
  late DateTime _anchor;

  /// 日檢視的事件(不含已刪除)。
  List<IntakeEvent>? _events;

  /// 週/月檢視的每日總量。
  Map<DateTime, int>? _totals;

  /// 目前範圍內,因為是連結照護系統之前的紀錄而沒有計入的筆數。
  int _hiddenBeforeLink = 0;

  /// 目前資料對應的範圍與起日;和畫面選擇不同時表示正在載入新資料,
  /// 先以半透明保留舊畫面,避免閃爍。
  (StatsRange, DateTime)? _loadedFor;
  int _generation = 0;

  DateTime get _now => (widget.clock ?? DateTime.now)();
  DateTime get _today => startOfDay(_now);

  @override
  void initState() {
    super.initState();
    _anchor = _today;
    widget.repo.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(StatsPage old) {
    super.didUpdateWidget(old);
    if (old.repo != widget.repo) {
      old.repo.removeListener(_load);
      widget.repo.addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    widget.repo.removeListener(_load);
    super.dispose();
  }

  _Period _periodOf(StatsRange r, DateTime anchor) => switch (r) {
        StatsRange.day => (from: anchor, to: anchor),
        StatsRange.week => PeriodStats.weekRange(anchor),
        StatsRange.month => PeriodStats.monthRange(anchor),
      };

  _Period get _period => _periodOf(_range, _anchor);

  Future<void> _load() async {
    final gen = ++_generation;
    final range = _range;
    final p = _period;
    final hidden = await widget.repo.hiddenBeforeLinkCount(p.from, p.to);
    if (range == StatsRange.day) {
      final events = await widget.repo.eventsOnDay(p.from);
      if (!mounted || gen != _generation) return;
      setState(() {
        _events = events;
        _hiddenBeforeLink = hidden;
        _loadedFor = (range, p.from);
      });
    } else {
      final totals = await widget.repo.dailyTotals(p.from, p.to);
      if (!mounted || gen != _generation) return;
      setState(() {
        _totals = totals;
        _hiddenBeforeLink = hidden;
        _loadedFor = (range, p.from);
      });
    }
  }

  void _select(StatsRange range, DateTime anchor) {
    setState(() {
      _range = range;
      _anchor = anchor;
    });
    _load();
  }

  DateTime _shifted(int dir) => switch (_range) {
        StatsRange.day =>
          DateTime(_anchor.year, _anchor.month, _anchor.day + dir),
        StatsRange.week =>
          DateTime(_anchor.year, _anchor.month, _anchor.day + 7 * dir),
        StatsRange.month => DateTime(_anchor.year, _anchor.month + dir, 1),
      };

  /// 下一段的起日不能在今天之後。
  bool get _canGoNext =>
      !_periodOf(_range, _shifted(1)).from.isAfter(_today);

  bool get _showsToday {
    final p = _period;
    return !_today.isBefore(p.from) && !_today.isAfter(p.to);
  }

  String get _periodLabel {
    final p = _period;
    return switch (_range) {
      StatsRange.day => fmtMonthDay(p.from),
      StatsRange.week =>
        '${p.from.month}/${p.from.day}–${p.to.month}/${p.to.day}',
      StatsRange.month => '${p.from.year} 年 ${p.from.month} 月',
    };
  }

  // ------------------------------------------------------------ 動作

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) _snack('儲存失敗:$e');
    }
  }

  Future<void> _addManual() async {
    final now = _now;
    final day = _anchor;
    final isToday = dayKey(day) == dayKey(now);
    final r = await showIntakeEventDialog(
      context,
      day: day,
      initialTime: isToday ? now : DateTime(day.year, day.month, day.day, 12),
      now: now,
    );
    if (r is IntakeEventSave) {
      await _guard(() => widget.repo.addEvent(
            kind: r.kind,
            ml: r.ml,
            startedAt: r.time,
            source: IntakeSource.manual,
          ));
    }
  }

  Future<void> _edit(IntakeEvent e) async {
    final r = await showIntakeEventDialog(
      context,
      existing: e,
      day: startOfDay(e.startedAt),
      initialTime: e.startedAt,
      now: _now,
    );
    switch (r) {
      case IntakeEventSave(:final time, :final ml, :final kind):
        await _guard(() => widget.repo.updateEvent(
              e.id,
              ml: ml,
              startedAt: time == e.startedAt ? null : time,
              kind: kind,
            ));
      case IntakeEventDelete():
        await _guard(() => widget.repo.deleteEvent(e.id));
        if (!mounted) return;
        final previous = e.status;
        _snack(
          '已刪除 ${fmtTime(e.startedAt)} ${fmtMl(e.ml)} mL',
          action: SnackBarAction(
            label: '復原',
            onPressed: () => widget.repo.updateEvent(e.id, status: previous),
          ),
        );
      case null:
        break;
    }
  }

  Future<void> _confirmDrink(IntakeEvent e) => _guard(() => widget.repo
      .updateEvent(e.id, kind: IntakeKind.drink, status: IntakeStatus.ok));

  Future<void> _rejectDrink(IntakeEvent e) => _guard(() => widget.repo
      .updateEvent(e.id, kind: IntakeKind.discard, status: IntakeStatus.ok));

  /// 待確認的加水:只是加水,沒有喝。
  Future<void> _confirmRefill(IntakeEvent e) => _guard(
      () => widget.repo.updateEvent(e.id, status: IntakeStatus.ok));

  /// 待確認的加水:有喝,補記一筆手動喝水(時間預設為那次拿起的時間),
  /// 加水本身確認為正常(仍不計入飲水量)。取消對話框則什麼都不改。
  Future<void> _addDrinkForRefill(IntakeEvent e) async {
    final r = await showIntakeEventDialog(
      context,
      day: startOfDay(e.startedAt),
      initialTime: e.startedAt,
      now: _now,
    );
    if (r is! IntakeEventSave) return;
    await _guard(() async {
      await widget.repo.addEvent(
        kind: r.kind,
        ml: r.ml,
        startedAt: r.time,
        source: IntakeSource.manual,
      );
      await widget.repo.updateEvent(e.id, status: IntakeStatus.ok);
    });
  }

  // ------------------------------------------------------------ 畫面

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final side = math.max(16.0, (c.maxWidth - 760) / 2);
      return ListView(
        padding: EdgeInsets.fromLTRB(side, 16, side, 24),
        children: [
          _controls(),
          // 已連結照護系統:數字要和照護系統一致,連結之前的紀錄不算。
          if (_hiddenBeforeLink > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text('連結照護系統之前的 $_hiddenBeforeLink 筆紀錄不計入',
                  style: mutedSmall),
            ),
          const SizedBox(height: 12),
          ..._content(),
        ],
      );
    });
  }

  Widget _controls() {
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<StatsRange>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: StatsRange.day, label: Text('日')),
              ButtonSegment(value: StatsRange.week, label: Text('週')),
              ButtonSegment(value: StatsRange.month, label: Text('月')),
            ],
            selected: {_range},
            onSelectionChanged: (s) => _select(s.first, _anchor),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                tooltip: '上一段',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _select(_range, _shifted(-1)),
              ),
              Expanded(
                child: Text(
                  _periodLabel,
                  key: const ValueKey('stats-period-label'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '下一段',
                icon: const Icon(Icons.chevron_right),
                onPressed: _canGoNext ? () => _select(_range, _shifted(1)) : null,
              ),
              TextButton(
                onPressed: _showsToday ? null : () => _select(_range, _today),
                child: const Text('今天'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _content() {
    final p = _period;
    final fresh = _loadedFor == (_range, p.from);
    final hasData = _range == StatsRange.day
        ? _events != null && _loadedFor?.$1 == StatsRange.day
        : _totals != null && _loadedFor?.$1 == _range;
    if (!hasData) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final children = _range == StatsRange.day ? _dayView() : _periodView();
    if (fresh) return children;
    // 換頁時先保留上一頁的畫面,資料到了再換掉。
    return [
      for (final w in children)
        Opacity(opacity: 0.5, child: IgnorePointer(child: w)),
    ];
  }

  // ------------------------------------------------------------ 日

  List<Widget> _dayView() {
    final events = _events!;
    final day = _loadedFor!.$2;
    final s = DayStats.fromEvents(events,
        day: day, goalMl: widget.repo.goalMl, now: _now);
    return [
      Panel(child: _dayTotal(s)),
      const SizedBox(height: 12),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('時間分布',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Text('06–20 時為清醒時段(淡色底)', style: mutedSmall),
            const SizedBox(height: 12),
            DayDistributionChart(stats: s),
            const SizedBox(height: 16),
            DistributionIndicators(stats: s),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Panel(child: _eventList(events, s)),
    ];
  }

  /// 已連結照護系統而照護系統還沒設定目標時顯示的文字(不套用任何預設值)。
  static const noGoalText = '照護系統尚未設定目標';

  Widget _dayTotal(DayStats s) {
    final goal = s.goalMl;
    final hasGoal = s.hasGoal && goal != null;
    final String detail;
    if (!hasGoal) {
      detail = '';
    } else if (s.isToday) {
      final ideal = s.idealAt(s.now).round();
      final diff = s.totalMl - ideal;
      detail = s.metGoal
          ? '已達標'
          : ideal <= 0
              ? '06:00 起開始累積理想進度'
              : '理想進度此時約 ${fmtMl(ideal)} mL,'
                  '${diff >= 0 ? '超前' : '落後'} ${fmtMl(diff.abs())} mL';
    } else {
      detail = s.metGoal ? '已達標' : '還差 ${fmtMl(goal - s.totalMl)} mL 達標';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          key: const ValueKey('day-total'),
          TextSpan(
            children: [
              TextSpan(
                text: s.isToday ? '今日 ' : '${fmtMonthDay(s.day)} ',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink),
              ),
              TextSpan(
                text: fmtMl(s.totalMl),
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink),
              ),
              TextSpan(
                text: hasGoal ? ' / ${fmtMl(goal)} mL' : ' mL',
                style: const TextStyle(fontSize: 16, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (hasGoal) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: s.progress.clamp(0.0, 1.0),
              minHeight: 8,
              color: AppColors.teal,
              backgroundColor: AppColors.teal.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 6),
          Text('達成 ${(s.progress * 100).round()}% · $detail',
              style: mutedSmall),
        ] else
          // 沒有目標:只顯示喝了多少,不算達成率、不畫進度條。
          const Text(noGoalText, style: mutedSmall),
      ],
    );
  }

  Widget _eventList(List<IntakeEvent> events, DayStats s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('紀錄',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            FilledButton.tonalIcon(
              onPressed: _addManual,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('手動新增'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              s.isToday
                  ? '今天還沒有紀錄。連上水杯會自動記錄,也可以按「手動新增」補記。'
                  : '這天沒有紀錄,可以按「手動新增」補記。',
              style: mutedSmall,
            ),
          ),
        for (final e in events.reversed) ...[
          const Divider(),
          _EventRow(
            event: e,
            onTap: () => _edit(e),
            onConfirm: () => e.kind == IntakeKind.refill
                ? _addDrinkForRefill(e)
                : _confirmDrink(e),
            onReject: () => e.kind == IntakeKind.refill
                ? _confirmRefill(e)
                : _rejectDrink(e),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ 週 / 月

  List<Widget> _periodView() {
    final isMonth = _range == StatsRange.month;
    final from = _loadedFor!.$2;
    final p = _periodOf(_range, from);
    final s = PeriodStats.fromTotals(_totals!,
        from: p.from, to: p.to, goalMl: widget.repo.goalMl, now: _now);
    final unit = isMonth ? '月' : '週';
    final partial = s.elapsedDays < s.dayCount;
    return [
      Panel(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SummaryTile(
                  key: const ValueKey('period-total'),
                  label: '$unit累積',
                  value: fmtMl(s.totalMl),
                  unit: 'mL',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryTile(
                  label: '日平均',
                  value: fmtMl(s.averageMl),
                  unit: 'mL',
                  detail: partial ? '算到今天 ${s.elapsedDays} 天' : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryTile(
                  key: const ValueKey('period-met'),
                  label: '達標天數',
                  value: s.hasGoal ? '${s.daysMetGoal}/${s.dayCount}' : '—',
                  detail: s.hasGoal ? '目標 ${fmtMl(s.goalMl!)} mL' : noGoalText,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('每日飲水量',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (s.hasGoal) const Text('虛線為每日目標', style: mutedSmall),
            const SizedBox(height: 12),
            if (s.totalMl == 0)
              SizedBox(
                height: 120,
                child: Center(
                  child: Text('這$unit沒有喝水紀錄', style: mutedSmall),
                ),
              )
            else
              PeriodBarChart(stats: s, isMonth: isMonth),
          ],
        ),
      ),
      const SizedBox(height: 12),
      // 表格版:每個數值都能直接讀到,不必靠觸控提示。
      Panel(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: const Text('每日明細',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              for (final d in s.days.reversed)
                if (!d.isFuture)
                  InkWell(
                    onTap: () => _select(StatsRange.day, d.day),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(fmtMonthDay(d.day))),
                          Text('${fmtMl(d.ml)} mL',
                              style: const TextStyle(
                                  fontFeatures: [FontFeature.tabularFigures()])),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 18,
                            child: s.hasGoal && d.ml >= s.goalMl!
                                ? const Icon(Icons.check_circle,
                                    size: 16, color: AppColors.teal,
                                    semanticLabel: '達標')
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.detail,
  });

  final String label;
  final String value;
  final String? unit;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: mutedSmall, maxLines: 1),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink),
            ),
            if (unit != null)
              TextSpan(
                text: ' $unit',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
          ])),
        ),
        if (detail != null)
          Text(detail!,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
              maxLines: 2),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.onTap,
    required this.onConfirm,
    required this.onReject,
  });

  final IntakeEvent event;
  final VoidCallback onTap;

  /// 待確認時的主要按鈕:喝水 →「確認是喝水」;加水 →「有喝,補記」。
  final VoidCallback onConfirm;

  /// 待確認時的次要按鈕:喝水 →「不是喝水」;加水 →「只是加水」。
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final uncertain = e.status == IntakeStatus.uncertain;
    final counts = e.countsAsIntake;
    final icon = switch (e.kind) {
      IntakeKind.drink => Icons.water_drop,
      IntakeKind.refill => Icons.add_circle_outline,
      IntakeKind.discard => Icons.remove_circle_outline,
    };
    final auto = e.source != IntakeSource.manual;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(fmtTime(e.startedAt),
                    style: const TextStyle(
                        fontSize: 14,
                        fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 12),
                Icon(icon,
                    size: 18, color: counts ? AppColors.teal : AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(intakeKindLabel(e.kind)),
                      _Badge(auto ? '自動' : '手動'),
                      if (uncertain) const _Badge('待確認', color: AppColors.orange),
                      // 韌體送來時沒有可信的時間(time_unknown):顯示的是 App 收到的時間。
                      if (e.timeEstimated ?? false) const _Badge('時間為估計'),
                    ],
                  ),
                ),
                Text(
                  '${fmtMl(e.ml)} mL',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: counts ? FontWeight.w600 : FontWeight.w400,
                    color: counts ? AppColors.ink : AppColors.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (uncertain) ...[
              if (e.kind == IntakeKind.refill)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text('這次拿起時有喝的動作,可能也喝了水',
                      textAlign: TextAlign.end, style: mutedSmall),
                ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: e.kind == IntakeKind.refill
                    ? [
                        TextButton(
                            onPressed: onReject, child: const Text('只是加水')),
                        FilledButton.tonal(
                            onPressed: onConfirm, child: const Text('有喝,補記')),
                      ]
                    : [
                        TextButton(
                            onPressed: onReject, child: const Text('不是喝水')),
                        FilledButton.tonal(
                            onPressed: onConfirm,
                            child: const Text('確認是喝水')),
                      ],
              ),
            ] else if (!counts)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('不計入飲水量',
                    textAlign: TextAlign.end, style: mutedSmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.color = AppColors.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      // 徽章文字用一般字色,邊框帶顏色區分。
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.ink)),
    );
  }
}
