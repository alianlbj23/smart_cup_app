import 'dart:async';

import 'package:flutter/material.dart';

import '../data/intake_repository.dart';
import '../state/care_link_manager.dart';
import '../state/care_sync.dart';
import '../state/cup_connection_manager.dart';
import '../state/update_manager.dart';
import 'cup_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.manager,
    required this.repo,
    this.care,
    this.careSync,
    this.updates,
  });

  final CupConnectionManager manager;
  final IntakeRepository repo;

  /// 照護系統的連結與背景同步;有傳入時「設定」頁才有「照護系統」區塊。
  final CareLinkManager? care;
  final CareSync? careSync;

  /// App 自動更新;有傳入時查到新版會在上方提示,「設定」頁有「軟體更新」區塊。
  final UpdateManager? updates;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _settingsTab = 2;

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
      () => SettingsPage(
            repo: widget.repo,
            care: widget.care,
            careSync: widget.careSync,
            updates: widget.updates,
          ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            const Divider(),
            if (widget.updates != null)
              ListenableBuilder(
                listenable: widget.updates!,
                builder: (context, _) {
                  final info = widget.updates!.available;
                  // 已經在設定頁就不用再提示。
                  if (info == null || _tab == _settingsTab) {
                    return const SizedBox.shrink();
                  }
                  return _UpdateBanner(
                    version: info.version,
                    onView: () => setState(() {
                      _tab = _settingsTab;
                      _visited.add(_settingsTab);
                    }),
                  );
                },
              ),
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

/// 查到新版時的提示列;按「查看」切到設定頁的「軟體更新」。
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.version, required this.onView});

  final String version;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(
          children: [
            const Icon(Icons.system_update_alt,
                color: AppColors.teal, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '有新版本 $version',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: onView, child: const Text('查看')),
          ],
        ),
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
