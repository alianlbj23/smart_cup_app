import 'package:flutter/material.dart';

import '../models/resident.dart';
import '../state/care_store.dart';
import '../state/cup_connection_manager.dart';
import 'cup_link.dart';
import 'intake_chart.dart';
import 'resident_detail.dart';
import 'resident_form.dart';
import 'theme.dart';

enum _Filter { all, behind, paired, unpaired }

/// 今日總覽:全區指標、住民飲水進度、選取住民的登錄與水杯配對。
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.manager,
    required this.store,
    required this.now,
  });

  final CupConnectionManager manager;
  final CareStore store;
  final DateTime now;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  _Filter _filter = _Filter.all;

  CupConnectionManager get manager => widget.manager;
  CareStore get store => widget.store;
  DateTime get now => widget.now;

  @override
  Widget build(BuildContext context) {
    final residents = store.residents;
    final selected = store.selected;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _header(context, residents.length),
            const SizedBox(height: 12),
            _KpiRow(manager: manager, residents: residents, now: now),
            const SizedBox(height: 12),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _gridPanel(context, residents, wide: true)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        if (selected != null) ...[
                          Panel(
                            child: ResidentDetail(
                              manager: manager,
                              store: store,
                              resident: selected,
                              now: now,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _RemindersPanel(store: store, now: now),
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              _gridPanel(context, residents, wide: false),
              const SizedBox(height: 12),
              _RemindersPanel(store: store, now: now),
            ],
            if (selected != null) ...[
              const SizedBox(height: 12),
              _chartPanel(selected),
            ],
            const SizedBox(height: 16),
            const Text(
              '衛教原則:一般參考量 25–30 mL × 體重(kg)/天;'
              '若醫師已開立每日液體上限,以醫囑為準。',
              textAlign: TextAlign.center,
              style: mutedSmall,
            ),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, int count) {
    final lastSync = manager.log.lastOrNull?.receivedAt;
    final sync = manager.state == CupConnectionState.ready
        ? (lastSync == null ? '水杯已連線' : '水杯最後同步 ${fmtTime(lastSync)}')
        : '水杯未連線';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('今日飲水照護',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text('全區 $count 位住民 · $sync', style: mutedSmall),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: () => showResidentForm(context, store),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新增住民'),
        ),
      ],
    );
  }

  Widget _gridPanel(
    BuildContext context,
    List<Resident> residents, {
    required bool wide,
  }) {
    final shown = residents.where((r) {
      return switch (_filter) {
        _Filter.all => true,
        _Filter.behind => HydrationSchedule.isBehind(r, now),
        _Filter.paired => r.hasCup,
        _Filter.unpaired => !r.hasCup,
      };
    }).toList();

    final grid = shown.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('沒有符合條件的住民', style: mutedSmall)),
          )
        : GridView.builder(
            // 寬版超過高度上限時在區塊內捲動;窄版隨整頁捲動。
            shrinkWrap: true,
            physics: wide ? null : const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              mainAxisExtent: 78,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final r = shown[i];
              return _ResidentCard(
                resident: r,
                now: now,
                link: cupLinkOf(manager, r),
                selected: wide && r.id == store.selected?.id,
                onTap: () {
                  store.select(r.id);
                  if (!wide) _showDetailSheet(context, r.id);
                },
              );
            },
          );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('住民飲水進度',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('點選住民即可快速登錄與配對水杯', style: mutedSmall),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<_Filter>(
                  value: _filter,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  style: const TextStyle(fontSize: 14, color: AppColors.ink),
                  onChanged: (f) => setState(() => _filter = f!),
                  items: [
                    DropdownMenuItem(
                      value: _Filter.all,
                      child: Text('全部 ${residents.length} 人'),
                    ),
                    const DropdownMenuItem(
                        value: _Filter.behind, child: Text('需要提醒')),
                    const DropdownMenuItem(
                        value: _Filter.paired, child: Text('已配對水杯')),
                    const DropdownMenuItem(
                        value: _Filter.unpaired, child: Text('未配對水杯')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (wide)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: grid,
            )
          else
            grid,
        ],
      ),
    );
  }

  Widget _chartPanel(Resident r) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${r.name} · 今日累積飲水曲線',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const Text('依登錄時間自動累加,虛線為個人目標進度', style: mutedSmall),
          const SizedBox(height: 12),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: IntakeChart(
                entries: r.entriesOn(now),
                goalMl: r.goalMl,
                now: now,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Row(
            children: [
              _Legend(color: AppColors.teal, label: '實際累積量'),
              SizedBox(width: 16),
              _Legend(color: AppColors.muted, label: '目標進度'),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetailSheet(BuildContext context, String residentId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([manager, store]),
        builder: (context, _) {
          final r = store.byId(residentId);
          if (r == null) return const SizedBox.shrink();
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: ResidentDetail(
                manager: manager,
                store: store,
                resident: r,
                now: DateTime.now(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label, style: mutedSmall),
      ],
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.manager,
    required this.residents,
    required this.now,
  });

  final CupConnectionManager manager;
  final List<Resident> residents;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final n = residents.length;
    final expected = HydrationSchedule.expectedFraction(now);
    final avg = n == 0
        ? 0.0
        : residents.fold<double>(
                0, (s, r) => s + r.progressOn(now).clamp(0.0, 1.0)) /
            n;
    final onTrack =
        residents.where((r) => HydrationSchedule.isOnTrack(r, now)).length;
    final done = residents.where((r) => r.progressOn(now) >= 1).length;
    final behind =
        residents.where((r) => HydrationSchedule.isBehind(r, now)).length;
    final paired = residents.where((r) => r.hasCup).length;
    final connected = residents
        .where((r) => cupLinkOf(manager, r) == CupLink.connected)
        .length;

    final cards = [
      _Kpi(
        label: '全區平均進度',
        value: '${(avg * 100).round()}%',
        note: '目標時程 ${(expected * 100).round()}%',
        color: AppColors.teal,
      ),
      _Kpi(
        label: '已達時程',
        value: '$onTrack人',
        note: '含 $done 人已完成',
        color: AppColors.ink,
      ),
      _Kpi(
        label: '需要提醒',
        value: '$behind人',
        note: '落後時程 15%以上',
        color: AppColors.orange,
      ),
      _Kpi(
        label: '水杯配對',
        value: '$paired/$n',
        note: connected > 0 ? '$connected 個水杯連線中' : '目前沒有水杯連線',
        color: AppColors.teal,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 720 ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in cards) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.note,
    required this.color,
  });

  final String label;
  final String value;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: mutedSmall),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          Text(note,
              style: mutedSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _ResidentCard extends StatelessWidget {
  const _ResidentCard({
    required this.resident,
    required this.now,
    required this.link,
    required this.selected,
    required this.onTap,
  });

  final Resident resident;
  final DateTime now;
  final CupLink link;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = resident;
    final progress = r.progressOn(now);
    final behind = HydrationSchedule.isBehind(r, now);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.teal : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      r.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (link != CupLink.none)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Tooltip(
                        message: link == CupLink.connected
                            ? '水杯已連線'
                            : '已配對水杯(未連線)',
                        child: Icon(
                          link == CupLink.connected
                              ? Icons.bluetooth_connected
                              : Icons.local_drink_outlined,
                          size: 15,
                          color: link == CupLink.connected
                              ? AppColors.teal
                              : AppColors.muted,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(r.room, style: mutedSmall.copyWith(fontSize: 11)),
                ],
              ),
              ProgressBar(
                value: progress,
                color: behind ? AppColors.orange : AppColors.teal,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text('${r.totalOn(now)} / ${r.goalMl}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mutedSmall.copyWith(fontSize: 11)),
                  ),
                  Text('${(progress * 100).round()}%',
                      style: mutedSmall.copyWith(fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 下一步提醒:落後最多的前幾位住民。
class _RemindersPanel extends StatelessWidget {
  const _RemindersPanel({required this.store, required this.now});

  final CareStore store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final behind = behindResidents(store.residents, now).take(3).toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('下一步提醒',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child:
                    Text('自動排序', style: mutedSmall.copyWith(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (behind.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('目前沒有需要提醒的住民', style: mutedSmall),
            ),
          for (final r in behind) ...[
            const Divider(),
            InkWell(
              onTap: () => store.select(r.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: ReminderLine(resident: r, now: now),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 落後時程的住民,落後最多者在前。
List<Resident> behindResidents(List<Resident> residents, DateTime now) =>
    residents.where((r) => HydrationSchedule.isBehind(r, now)).toList()
      ..sort((a, b) => HydrationSchedule.lagMl(b, now)
          .compareTo(HydrationSchedule.lagMl(a, now)));

class ReminderLine extends StatelessWidget {
  const ReminderLine({super.key, required this.resident, required this.now});

  final Resident resident;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final r = resident;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 8),
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                color: AppColors.orange, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.room.isEmpty ? r.name : '${r.name} · ${r.room}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '落後 ${HydrationSchedule.lagMl(r, now)} mL · '
                '建議現在補充 ${HydrationSchedule.suggestedMl(r, now)} mL',
                style: mutedSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
