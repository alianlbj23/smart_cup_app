import 'dart:async';

import 'package:flutter/material.dart';

import '../data/intake_repository.dart';
import '../services/update_service.dart';
import '../state/care_link_manager.dart';
import '../state/care_sync.dart';
import '../state/cup_connection_manager.dart';
import '../state/disconnect_log.dart';
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
    this.disconnectLog,
    this.updates,
  });

  final CupConnectionManager manager;

  /// 水杯的斷線紀錄(設定頁「連線紀錄」)。
  final DisconnectLog? disconnectLog;
  final IntakeRepository repo;

  /// 照護系統的連結與背景同步;有傳入時「設定」頁才有「照護系統」區塊。
  final CareLinkManager? care;
  final CareSync? careSync;

  /// App 自動更新;有傳入時查到新版會跳出視窗詢問要不要更新(同一版只問一次),
  /// 之後在上方留提示列;「設定」頁有「軟體更新」區塊。
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

  /// 已經跳出視窗問過的版本:同一版只主動問一次,之後只留上方的提示列。
  String? _promptedVersion;

  @override
  void initState() {
    super.initState();
    widget.updates?.addListener(_maybePromptUpdate);
    // App 啟動前就已經查到新版的情況。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptUpdate());
    // 水量/姿態是否過期隨時間變化,定期重算(姿態 2 秒即過期,故每秒一次)。
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    widget.updates?.removeListener(_maybePromptUpdate);
    _refreshTimer.cancel();
    super.dispose();
  }

  void _openSettings() => setState(() {
        _tab = _settingsTab;
        _visited.add(_settingsTab);
      });

  /// 查到還沒問過的新版時,跳出視窗讓使用者決定要不要更新。
  void _maybePromptUpdate() {
    final updates = widget.updates;
    final info = updates?.available;
    if (!mounted || updates == null || info == null) return;
    final version = info.version;
    if (_promptedVersion == version) return;
    // 已經在下載或安裝(使用者自己到設定頁按的)就不用再問。
    if (updates.phase == UpdatePhase.downloading ||
        updates.phase == UpdatePhase.installing) {
      return;
    }
    _promptedVersion = version;
    // 通知可能發生在畫面建構途中,等這一幀結束再開視窗。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showUpdateDialog(info));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showUpdateDialog(UpdateInfo info) async {
    final updates = widget.updates!;
    final canInstall = updates.canInstall;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('有新版本 ${info.version}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('目前版本 ${updates.currentVersion}', style: mutedSmall),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(info.notes, maxLines: 8, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 12),
              Text(
                canInstall
                    ? '要現在更新嗎?安裝新版不會刪除這台裝置上的紀錄。'
                    : '這台裝置無法由 App 自行安裝新版,可以到「設定」取得下載連結。',
                style: mutedSmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍後再說'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(canInstall ? '立即更新' : '前往設定'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    // 切到設定頁:下載進度與失敗原因都顯示在「軟體更新」。
    _openSettings();
    if (canInstall && !updates.busy) unawaited(updates.install());
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
            disconnectLog: widget.disconnectLog,
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
                    onView: _openSettings,
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

/// 查到新版時的提示列(使用者在詢問視窗選了「稍後再說」之後仍然留著);
/// 按「查看」切到設定頁的「軟體更新」。
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
