import 'dart:async';

import 'package:flutter/material.dart';

import '../data/intake_repository.dart';
import '../state/cup_connection_manager.dart';
import 'cup_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.manager, required this.repo});

  final CupConnectionManager manager;
  final IntakeRepository repo;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final Timer _refreshTimer;
  int _tab = 0;

  /// 打開過的分頁才建立,之後保留狀態(統計頁選的日期、範圍切換分頁後不會重設)。
  final Set<int> _visited = {0};

  @override
  void initState() {
    super.initState();
    // 水量/姿態是否過期隨時間變化,定期重算(姿態 2 秒即過期,故每秒一次)。
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget Function()>[
      () => ListenableBuilder(
            listenable: widget.manager,
            builder: (context, _) =>
                CupPage(manager: widget.manager, now: DateTime.now()),
          ),
      () => StatsPage(repo: widget.repo),
      () => SettingsPage(repo: widget.repo),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            const Divider(),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    _visited.contains(i) ? pages[i]() : const SizedBox(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        backgroundColor: Colors.white,
        height: 64,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: '水杯',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '飲水統計',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

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
          const Text('智慧水杯',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
