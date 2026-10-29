import 'dart:async';

import 'package:flutter/material.dart';

import '../state/care_store.dart';
import '../state/cup_connection_manager.dart';
import 'cup_link.dart';
import 'dashboard_page.dart';
import 'pages.dart';
import 'theme.dart';

const _navItems = [
  (Icons.grid_view_rounded, '今日總覽', '總覽'),
  (Icons.person_outline, '住民資料', '住民'),
  (Icons.notifications_none, '提醒中心', '提醒'),
  (Icons.show_chart, '統計分析', '統計'),
  (Icons.local_drink_outlined, '水杯裝置', '水杯'),
];
const _cupsIndex = 4;

/// App 外框:頂列、導覽(寬版側欄/窄版底部)與各分頁。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.manager, required this.store});

  final CupConnectionManager manager;
  final CareStore store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    // 時程進度隨時間變化,每分鐘重算一次。
    _clock = Timer.periodic(
        const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    final store = widget.store;
    return ListenableBuilder(
      listenable: Listenable.merge([manager, store]),
      builder: (context, _) {
        final now = DateTime.now();
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final page = !store.loaded
            ? const Center(child: CircularProgressIndicator())
            : switch (_index) {
                0 => DashboardPage(manager: manager, store: store, now: now),
                1 => ResidentsPage(manager: manager, store: store),
                2 => RemindersPage(store: store, now: now),
                3 => StatsPage(store: store, now: now),
                _ => CupsPage(manager: manager, store: store),
              };
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  manager: manager,
                  store: store,
                  now: now,
                  showDate: wide,
                  onCupTap: () => setState(() => _index = _cupsIndex),
                ),
                const Divider(),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Sidebar(
                              index: _index,
                              onSelect: (i) => setState(() => _index = i),
                            ),
                            Expanded(child: page),
                          ],
                        )
                      : page,
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  backgroundColor: Colors.white,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: [
                    for (final (icon, _, short) in _navItems)
                      NavigationDestination(icon: Icon(icon), label: short),
                  ],
                ),
        );
      },
    );
  }
}

String _shift(DateTime now) => switch (now.hour) {
      >= 7 && < 15 => '早班',
      >= 15 && < 23 => '小夜班',
      _ => '大夜班',
    };

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.manager,
    required this.store,
    required this.now,
    required this.showDate,
    required this.onCupTap,
  });

  final CupConnectionManager manager;
  final CareStore store;
  final DateTime now;
  final bool showDate;
  final VoidCallback onCupTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.teal,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.water_drop, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('潤心照護',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (showDate) ...[
            Text('${now.year}年${now.month}月${now.day}日 · ${_shift(now)}',
                style: mutedSmall),
            const SizedBox(width: 12),
          ],
          _cupChip(),
        ],
      ),
    );
  }

  /// 目前水杯連線狀態,點選前往「水杯裝置」。
  Widget _cupChip() {
    final m = manager;
    final owner = store.ownerOfCup(
        m.activeDeviceId ?? m.rememberedDevice?.id);
    final who = owner?.name ?? cupDisplayName(m.connectingName);
    final (label, color, icon) = switch (m.state) {
      CupConnectionState.ready => (
          '水杯已連線 · $who',
          AppColors.teal,
          Icons.bluetooth_connected
        ),
      CupConnectionState.notFound => (
          '找不到水杯',
          AppColors.red,
          Icons.bluetooth_disabled
        ),
      CupConnectionState.idle => ('水杯未連線', AppColors.muted, Icons.bluetooth),
      _ => ('水杯連線中…', AppColors.orange, Icons.bluetooth_searching),
    };
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onCupTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      color: AppColors.sidebar,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          for (final (i, (icon, label, _)) in _navItems.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: i == index ? AppColors.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        Icon(icon,
                            size: 18,
                            color: i == index ? Colors.white : AppColors.ink),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: i == index ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('飲水照護原則',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text(
                  '少量多次、白天平均喝;心衰竭、腎病與吞嚥困難者依個別醫囑。',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.muted, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
