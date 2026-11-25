import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/intake_repository.dart';
import '../services/backup_service.dart';
import '../state/care_link_manager.dart';
import '../state/care_sync.dart';
import 'care_link_panel.dart';
import 'theme.dart';

/// 設定:每日目標、水杯容量、照護系統(連結/解除)、資料備份(匯出/匯入)。
///
/// 和其他分頁一樣只是內容(ListView),需要放在有 [Scaffold] 的畫面裡才能顯示 SnackBar。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repo,
    this.fileIO = const PlatformBackupFileIO(),
    this.clock,
    this.care,
    this.careSync,
  });

  final IntakeRepository repo;

  /// 照護系統的連結狀態;有傳入才顯示「照護系統」區塊。
  final CareLinkManager? care;

  /// 照護系統的背景同步(顯示待上傳筆數、「立即同步」)。
  final CareSync? careSync;

  /// 檔案存取;測試時換成假的。
  final BackupFileIO fileIO;

  /// 目前時間(匯出檔名、匯出時間用);預設 [DateTime.now]。
  final DateTime Function()? clock;

  static const minGoalMl = 500;
  static const maxGoalMl = 5000;
  static const minCapacityMl = 50;
  static const maxCapacityMl = 2000;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// 正在進行的備份動作,用來顯示轉圈並避免重複按。
enum _BackupTask { csv, backup, import }

class _SettingsPageState extends State<SettingsPage> {
  List<CupRow>? _cups;
  _BackupTask? _busy;

  IntakeRepository get _repo => widget.repo;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepo);
    _loadCups();
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repo != widget.repo) {
      oldWidget.repo.removeListener(_onRepo);
      widget.repo.addListener(_onRepo);
      _loadCups();
    }
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepo);
    super.dispose();
  }

  void _onRepo() {
    // 目標存在 repo 裡,重建即可;水杯要重新查詢。
    setState(() {});
    _loadCups();
  }

  Future<void> _loadCups() async {
    final cups = await _repo.cups();
    cups.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    if (mounted) setState(() => _cups = cups);
  }

  void _snack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _goalPanel(),
        const SizedBox(height: 12),
        _cupsPanel(),
        const SizedBox(height: 12),
        if (widget.care != null) ...[
          CareLinkPanel(care: widget.care!, sync: widget.careSync),
          const SizedBox(height: 12),
        ],
        _backupPanel(),
      ],
    );
  }

  // ---------------------------------------------------------------- 每日目標

  Widget _goalPanel() {
    // 已連結照護系統:目標以 Server 為準,這裡只顯示、不能改。Server 還沒設定時
    // 顯示「照護系統尚未設定目標」,不套用任何預設值。
    final fromServer = _repo.goalFromServer;
    final goal = _repo.goalMl;
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('每日飲水目標'),
          ListTile(
            key: const ValueKey('goal-tile'),
            contentPadding: const EdgeInsets.only(right: 8),
            leading: const Icon(Icons.flag_outlined, color: AppColors.teal),
            title: Text(
              goal == null ? '照護系統尚未設定目標' : '$goal mL',
              style: TextStyle(
                fontSize: goal == null ? 16 : 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              fromServer ? '由照護系統設定,無法在這裡修改' : '一般成人建議每天 1500–2500 mL',
              style: mutedSmall,
            ),
            trailing: fromServer ? null : const Icon(Icons.edit_outlined, size: 20),
            onTap: fromServer ? null : _editGoal,
          ),
        ],
      ),
    );
  }

  Future<void> _editGoal() async {
    final ml = await showMlInputDialog(
      context,
      title: '每日飲水目標',
      initial: _repo.dailyGoalMl,
      min: SettingsPage.minGoalMl,
      max: SettingsPage.maxGoalMl,
    );
    if (ml == null || ml == _repo.dailyGoalMl) return;
    // 對話框開著的時候剛好連結成功 → 目標已經改由照護系統設定。
    if (_repo.goalFromServer) {
      _snack('已連結照護系統,每日目標由照護系統設定');
      return;
    }
    await _repo.setDailyGoal(ml);
    _snack('每日目標已改為 $ml mL');
  }

  // ---------------------------------------------------------------- 水杯容量

  Widget _cupsPanel() {
    final cups = _cups;
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('水杯容量'),
          const Padding(
            padding: EdgeInsets.only(right: 8, top: 2),
            child: Text('水量 = 水位比例 × 容量,請設成水杯裝滿時的毫升數。', style: mutedSmall),
          ),
          const SizedBox(height: 4),
          if (cups == null)
            const SizedBox(height: 48)
          else if (cups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('連上水杯後會出現在這裡', style: mutedSmall),
            )
          else
            for (final c in cups)
              ListTile(
                key: ValueKey('cup-${c.id}'),
                contentPadding: const EdgeInsets.only(right: 8),
                leading: const Icon(
                  Icons.local_drink_outlined,
                  color: AppColors.teal,
                ),
                title: Text(
                  c.name.isEmpty ? '未命名水杯' : c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${c.capacityMl} mL',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit_outlined, size: 20),
                  ],
                ),
                onTap: () => _editCapacity(c),
              ),
        ],
      ),
    );
  }

  Future<void> _editCapacity(CupRow cup) async {
    final name = cup.name.isEmpty ? '水杯' : cup.name;
    final ml = await showMlInputDialog(
      context,
      title: '$name 的容量',
      initial: cup.capacityMl,
      min: SettingsPage.minCapacityMl,
      max: SettingsPage.maxCapacityMl,
    );
    if (ml == null || ml == cup.capacityMl) return;
    await _repo.setCupCapacity(cup.id, ml);
    _snack('$name 的容量已改為 $ml mL');
  }

  // ---------------------------------------------------------------- 資料備份

  Widget _backupPanel() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('資料備份'),
          const SizedBox(height: 4),
          Text(
            widget.care?.isLinked ?? false
                ? '連結照護系統後,新的紀錄會另外上傳一份;這台裝置上的紀錄在解除安裝 App 時仍會一併刪除,請定期匯出備份檔。'
                : '紀錄只存在這台裝置上,解除安裝 App 會一併刪除,請定期匯出備份檔。',
            style: mutedSmall,
          ),
          const SizedBox(height: 12),
          _backupButton(
            task: _BackupTask.csv,
            icon: Icons.table_chart_outlined,
            label: '匯出紀錄(CSV)',
            onPressed: (c) => _run(_BackupTask.csv, () => _exportCsv(c)),
          ),
          const SizedBox(height: 8),
          _backupButton(
            task: _BackupTask.backup,
            icon: Icons.save_alt,
            label: '匯出備份檔',
            onPressed: (c) => _run(_BackupTask.backup, () => _exportBackup(c)),
          ),
          const SizedBox(height: 8),
          _backupButton(
            task: _BackupTask.import,
            icon: Icons.restore,
            label: '從備份檔匯入',
            onPressed: (_) => _confirmAndImport(),
          ),
          const SizedBox(height: 8),
          const Text(
            'CSV 可用 Excel 或 Google 試算表開啟;備份檔可在換手機或重新安裝後匯入還原。',
            style: mutedSmall,
          ),
        ],
      ),
    );
  }

  Widget _backupButton({
    required _BackupTask task,
    required IconData icon,
    required String label,
    required void Function(BuildContext buttonContext) onPressed,
  }) {
    return Builder(
      builder: (buttonContext) => OutlinedButton.icon(
        onPressed: _busy == null ? () => onPressed(buttonContext) : null,
        icon: _busy == task
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  /// 執行備份動作:期間顯示轉圈、停用按鈕,錯誤以 SnackBar 顯示。
  Future<void> _run(_BackupTask task, Future<void> Function() action) async {
    setState(() => _busy = task);
    try {
      await action();
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(switch (task) {
        _BackupTask.import => '匯入失敗:$e',
        _ => '匯出失敗:$e',
      });
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// 分享選單的錨點(iPad / macOS 需要)。
  Rect? _originOf(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _exportCsv(BuildContext buttonContext) async {
    final origin = _originOf(buttonContext);
    final csv = buildCsv(await _repo.allEvents());
    final where = await widget.fileIO.saveFile(
      fileName: csvFileName(_now()),
      bytes: Uint8List.fromList(utf8.encode(csv)),
      mimeType: 'text/csv',
      shareOrigin: origin,
    );
    if (where != null) _snack('已匯出紀錄:$where');
  }

  Future<void> _exportBackup(BuildContext buttonContext) async {
    final origin = _originOf(buttonContext);
    final now = _now();
    final json = await exportBackupJson(_repo, now: now);
    final where = await widget.fileIO.saveFile(
      fileName: backupFileName(now),
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
      shareOrigin: origin,
    );
    if (where != null) _snack('已匯出備份檔:$where');
  }

  /// 先確認(此時不顯示轉圈),再選檔並匯入。
  Future<void> _confirmAndImport() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('從備份檔匯入?'),
        content: const SingleChildScrollView(
          child: Text(
            '備份檔的紀錄會合併到這台裝置:\n'
            '・新的紀錄會加入,同一筆紀錄以較新的版本為準\n'
            '・這台裝置上現有的紀錄不會被刪除\n'
            '・每日目標會改成備份檔裡的設定(已連結照護系統時不會改)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('選擇檔案'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(_BackupTask.import, () async {
      final json = await widget.fileIO.pickBackupFile();
      if (json == null) return;
      final r = await importBackup(_repo, json);
      _snack(describeImportResult(r));
    });
  }
}

/// 匯入結果的提示文字。
String describeImportResult(ImportResult r) {
  if (r.nothingChanged) return '匯入完成:資料已是最新,沒有變更';
  final parts = [
    '${r.eventsChanged} 筆紀錄',
    if (r.cupsChanged > 0) '${r.cupsChanged} 個水杯',
  ];
  final goal = r.goalChanged ? ',每日目標改為 ${r.dailyGoalMl} mL' : '';
  return '匯入完成:新增或更新 ${parts.join('、')}$goal';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );
}

/// 輸入毫升數的對話框,限制在 [min]–[max];取消回傳 null。
Future<int?> showMlInputDialog(
  BuildContext context, {
  required String title,
  required int initial,
  required int min,
  required int max,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) =>
        _MlInputDialog(title: title, initial: initial, min: min, max: max),
  );
}

class _MlInputDialog extends StatefulWidget {
  const _MlInputDialog({
    required this.title,
    required this.initial,
    required this.min,
    required this.max,
  });

  final String title;
  final int initial;
  final int min;
  final int max;

  @override
  State<_MlInputDialog> createState() => _MlInputDialogState();
}

class _MlInputDialogState extends State<_MlInputDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == null || v < widget.min || v > widget.max) {
      setState(() => _error = '請輸入 ${widget.min}–${widget.max} 之間的數字');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('ml-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        decoration: InputDecoration(
          suffixText: 'mL',
          helperText: '範圍 ${widget.min}–${widget.max} mL',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('確定')),
      ],
    );
  }
}
