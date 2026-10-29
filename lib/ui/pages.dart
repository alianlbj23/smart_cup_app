import 'package:flutter/material.dart';

import '../models/resident.dart';
import '../state/care_store.dart';
import '../state/cup_connection_manager.dart';
import 'cup_link.dart';
import 'cup_reading.dart';
import 'dashboard_page.dart' show ReminderLine, behindResidents;
import 'resident_detail.dart';
import 'resident_form.dart';
import 'theme.dart';

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle, this.action});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle, style: mutedSmall),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

const _emptyPadding = EdgeInsets.symmetric(vertical: 32);

// ------------------------------------------------------------------ 住民資料

enum _ResidentAction { edit, pair, unpair, delete }

/// 住民資料:基本資料、飲水目標與配對水杯的管理。
class ResidentsPage extends StatelessWidget {
  const ResidentsPage({super.key, required this.manager, required this.store});

  final CupConnectionManager manager;
  final CareStore store;

  @override
  Widget build(BuildContext context) {
    final residents = store.residents;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PageHeader(
          title: '住民資料',
          subtitle: '共 ${residents.length} 位住民,'
              '${residents.where((r) => r.hasCup).length} 位已配對水杯',
          action: FilledButton.icon(
            onPressed: () => showResidentForm(context, store),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增住民'),
          ),
        ),
        Panel(
          padding: EdgeInsets.zero,
          child: residents.isEmpty
              ? const Padding(
                  padding: _emptyPadding,
                  child: Center(
                      child: Text('尚無住民,請先新增住民', style: mutedSmall)),
                )
              : Column(
                  children: [
                    for (final (i, r) in residents.indexed) ...[
                      if (i > 0) const Divider(),
                      _tile(context, r),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, Resident r) {
    final details = [
      residentSubtitle(r),
      '目標 ${fmtMl(r.goalMl)} mL',
      ...r.tags,
    ].where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      leading: ResidentAvatar(resident: r, radius: 18),
      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        r.hasCup ? '$details\n水杯:${cupDisplayName(r.cupName)}' : details,
        style: mutedSmall,
      ),
      isThreeLine: r.hasCup,
      onTap: () => showResidentForm(context, store, resident: r),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupStatusPill(link: cupLinkOf(manager, r)),
          PopupMenuButton<_ResidentAction>(
            onSelected: (a) => _onAction(context, r, a),
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: _ResidentAction.edit, child: Text('編輯')),
              if (r.hasCup)
                const PopupMenuItem(
                    value: _ResidentAction.unpair, child: Text('解除水杯配對'))
              else
                const PopupMenuItem(
                    value: _ResidentAction.pair, child: Text('配對水杯')),
              const PopupMenuItem(
                  value: _ResidentAction.delete, child: Text('刪除住民')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onAction(
      BuildContext context, Resident r, _ResidentAction action) async {
    switch (action) {
      case _ResidentAction.edit:
        await showResidentForm(context, store, resident: r);
      case _ResidentAction.pair:
        await showCupPairingDialog(context, manager, store, r);
      case _ResidentAction.unpair:
        await unpairCup(context, manager, store, r);
      case _ResidentAction.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('刪除住民?'),
            content: Text('將刪除「${r.name}」的資料、飲水紀錄與水杯配對,無法復原。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('刪除'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await releaseCup(manager, store, r);
        await store.removeResident(r.id);
    }
  }
}

// ------------------------------------------------------------------ 提醒中心

/// 提醒中心:落後時程的住民,可直接登錄建議補充量。
class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key, required this.store, required this.now});

  final CareStore store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final behind = behindResidents(store.residents, now);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PageHeader(
          title: '提醒中心',
          subtitle: '落後時程 15% 以上的住民共 ${behind.length} 位,依落後量排序',
        ),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: behind.isEmpty
              ? const Padding(
                  padding: _emptyPadding,
                  child: Center(
                      child: Text('目前沒有需要提醒的住民', style: mutedSmall)),
                )
              : Column(
                  children: [
                    for (final (i, r) in behind.indexed) ...[
                      if (i > 0) const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                                child: ReminderLine(resident: r, now: now)),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () => store.addIntake(r.id,
                                  HydrationSchedule.suggestedMl(r, now)),
                              child: Text(
                                  '+${HydrationSchedule.suggestedMl(r, now)} mL'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ 統計分析

/// 統計分析:近 7 日全區平均達成率與今日個人排行。
class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.store, required this.now});

  final CareStore store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final residents = store.residents;
    final days = [
      for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i),
    ];
    double average(DateTime day) => residents.isEmpty
        ? 0
        : residents.fold<double>(
                0, (s, r) => s + r.progressOn(day).clamp(0.0, 1.0)) /
            residents.length;
    final ranking = [...residents]
      ..sort((a, b) => b.progressOn(now).compareTo(a.progressOn(now)));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _PageHeader(title: '統計分析', subtitle: '依登錄的飲水紀錄計算'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('近 7 日全區平均達成率',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final day in days)
                      Expanded(child: _DayBar(day: day, value: average(day))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('今日達成率排行',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (ranking.isEmpty)
                const Padding(
                  padding: _emptyPadding,
                  child: Center(child: Text('尚無住民', style: mutedSmall)),
                ),
              for (final r in ranking)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(r.name,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: ProgressBar(
                          value: r.progressOn(now),
                          height: 8,
                          color: HydrationSchedule.isBehind(r, now)
                              ? AppColors.orange
                              : AppColors.teal,
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          '${r.totalOn(now)} / ${r.goalMl} mL',
                          textAlign: TextAlign.right,
                          style: mutedSmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day, required this.value});

  final DateTime day;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${(value * 100).round()}%', style: mutedSmall),
        const SizedBox(height: 4),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: value.clamp(0.01, 1.0).toDouble(),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 36),
                decoration: BoxDecoration(
                  color: AppColors.teal,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('${day.month}/${day.day}', style: mutedSmall),
      ],
    );
  }
}

// ------------------------------------------------------------------ 水杯裝置

String _stateLabel(CupConnectionState s) => switch (s) {
      CupConnectionState.idle => '未連線',
      CupConnectionState.scanning => '搜尋中',
      CupConnectionState.connecting => '連線中',
      CupConnectionState.connected => '已連線,初始化中',
      CupConnectionState.serviceDiscovered => '初始化中',
      CupConnectionState.ready => '已連線',
      CupConnectionState.notFound => '找不到水杯',
    };

/// 水杯裝置:目前連線、所有住民的水杯配對與接收紀錄。
class CupsPage extends StatelessWidget {
  const CupsPage({super.key, required this.manager, required this.store});

  final CupConnectionManager manager;
  final CareStore store;

  @override
  Widget build(BuildContext context) {
    final residents = store.residents;
    final paired = residents.where((r) => r.hasCup).toList();
    final unpaired = residents.where((r) => !r.hasCup).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PageHeader(
          title: '水杯裝置',
          subtitle: '${paired.length} 位住民已配對水杯;App 一次連線一個水杯',
        ),
        _connectionPanel(),
        const SizedBox(height: 12),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('住民與水杯配對',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (residents.isEmpty)
                const Padding(
                  padding: _emptyPadding,
                  child: Center(
                      child: Text('尚無住民,請先新增住民', style: mutedSmall)),
                ),
              for (final r in [...paired, ...unpaired]) ...[
                const Divider(),
                _pairingTile(context, r),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _logPanel(),
      ],
    );
  }

  Widget _connectionPanel() {
    final m = manager;
    final ready = m.state == CupConnectionState.ready;
    final busy = m.state == CupConnectionState.scanning ||
        m.state == CupConnectionState.connecting ||
        m.state == CupConnectionState.connected ||
        m.state == CupConnectionState.serviceDiscovered;
    final cupId = m.activeDeviceId ??
        (m.flow == CupFlow.reconnect ? m.rememberedDevice?.id : null);
    final owner = store.ownerOfCup(cupId);
    final cupName = m.connectingName ?? m.rememberedDevice?.name;
    final battery = m.deviceStatus?.batteryPercent;
    return Panel(
      child: Row(
        children: [
          Icon(
            ready ? Icons.bluetooth_connected : Icons.bluetooth,
            color: ready ? AppColors.teal : AppColors.muted,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('目前連線:${_stateLabel(m.state)}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                if (cupId != null)
                  Text(
                    [
                      cupDisplayName(cupName),
                      if (owner != null) '住民 ${owner.name}',
                      if (ready && battery != null) '電量 $battery%',
                    ].join(' · '),
                    style: mutedSmall,
                  )
                else
                  const Text('在下方為住民配對或連線水杯', style: mutedSmall),
                if (m.message case final msg?)
                  Text(msg,
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.red)),
              ],
            ),
          ),
          if (ready || busy)
            OutlinedButton(
              onPressed: m.disconnect,
              child: Text(ready ? '中斷連線' : '取消'),
            )
          else if (m.state == CupConnectionState.notFound)
            FilledButton(
              onPressed: m.startAutoReconnect,
              child: const Text('重試'),
            ),
        ],
      ),
    );
  }

  Widget _pairingTile(BuildContext context, Resident r) {
    final link = cupLinkOf(manager, r);
    return ListTile(
      leading: ResidentAvatar(resident: r, radius: 18),
      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        r.hasCup ? '${cupDisplayName(r.cupName)} · ${r.cupId}' : '尚未配對水杯',
        style: mutedSmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupStatusPill(link: link),
          const SizedBox(width: 8),
          switch (link) {
            CupLink.none => FilledButton.tonal(
                onPressed: () =>
                    showCupPairingDialog(context, manager, store, r),
                child: const Text('配對'),
              ),
            CupLink.offline || CupLink.notFound => FilledButton.tonal(
                onPressed: () => connectCup(manager, r),
                child: const Text('連線'),
              ),
            CupLink.linking || CupLink.connected => OutlinedButton(
                onPressed: manager.disconnect,
                child: Text(link == CupLink.connected ? '中斷' : '取消'),
              ),
          },
          if (r.hasCup)
            IconButton(
              tooltip: '解除配對',
              icon: const Icon(Icons.link_off, size: 20),
              onPressed: () => unpairCup(context, manager, store, r),
            ),
        ],
      ),
    );
  }

  Widget _logPanel() {
    final log = manager.log.reversed.toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('水杯資料接收紀錄',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Text(
            '水量與姿態來自韌體;原始值僅供除錯 · '
            '已接收 ${manager.receivedCount} 筆',
            style: mutedSmall,
          ),
          const SizedBox(height: 8),
          if (log.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('尚未收到資料', style: mutedSmall),
            ),
          for (final e in log)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(e.acked ? Icons.done_all : Icons.schedule,
                      size: 16, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(describePacket(e.packet))),
                  Text('${fmtTime(e.receivedAt)} 收到', style: mutedSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
