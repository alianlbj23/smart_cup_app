import 'package:flutter/material.dart';

import '../services/care_api.dart';
import '../state/care_link_manager.dart';
import '../state/care_sync.dart';
import 'care_link_page.dart';
import 'stats/chart_style.dart' show fmtMl;
import 'theme.dart';

/// 每日目標的顯示文字;null(照護系統還沒設定)時不顯示任何數字。
String describeCareGoal(int? goalMl) =>
    goalMl == null ? '照護系統尚未設定目標' : '${fmtMl(goalMl)} mL';

/// 「設定」頁的「照護系統」區塊。
///
/// - 尚未連結:伺服器位址(可改,會驗證)、「測試連線」、「連結照護系統」。
/// - 已連結:顯示「已連結:101-1 王○明」、每日目標(Server 為準)、同步狀態,
///   可以「立即同步」與「解除連結」。
/// - 連結失效(401)時顯示原因,直到使用者按「知道了」或重新連結。
class CareLinkPanel extends StatefulWidget {
  const CareLinkPanel({super.key, required this.care, this.sync});

  final CareLinkManager care;

  /// 背景同步;有傳入才顯示待上傳筆數、錯誤與「立即同步」。
  final CareSync? sync;

  @override
  State<CareLinkPanel> createState() => _CareLinkPanelState();
}

class _CareLinkPanelState extends State<CareLinkPanel> {
  late final _urlController = TextEditingController(text: _care.serverUrl);
  String? _urlError;

  /// 「測試連線」的結果;[_testOk] 為 null 表示還沒測。
  bool? _testOk;
  String? _testMessage;
  bool _testing = false;
  bool _syncing = false;

  /// 上一次從 [CareLinkManager] 看到的位址,用來在它(載入後)改變時更新輸入框。
  late String _knownServerUrl = _care.serverUrl;

  CareLinkManager get _care => widget.care;

  @override
  void initState() {
    super.initState();
    _care.addListener(_onChanged);
    widget.sync?.addListener(_onChanged);
  }

  @override
  void dispose() {
    _care.removeListener(_onChanged);
    widget.sync?.removeListener(_onChanged);
    _urlController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    if (_care.serverUrl != _knownServerUrl) {
      _knownServerUrl = _care.serverUrl;
      _urlController.text = _care.serverUrl;
    }
    setState(() {});
  }

  /// 驗證並儲存輸入的伺服器位址;不合法時顯示錯誤並回傳 false。
  Future<bool> _applyUrl() async {
    try {
      await _care.setServerUrl(_urlController.text);
      _knownServerUrl = _care.serverUrl;
      if (mounted) setState(() => _urlError = null);
      return true;
    } on FormatException catch (e) {
      if (mounted) setState(() => _urlError = e.message);
    } on CareLinkException catch (e) {
      if (mounted) setState(() => _urlError = e.message);
    }
    return false;
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testOk = null;
      _testMessage = null;
    });
    try {
      if (!await _applyUrl()) return;
      final health = await _care.testConnection(_care.serverUrl);
      final skew = health.serverTime?.difference(_care.now).abs();
      // 紀錄的時間是用手機的時鐘,差太多的話照護系統上的時間會不對。
      final clockNote = skew != null && skew > const Duration(minutes: 5)
          ? '。注意:這台裝置的時間和伺服器相差約 ${_fmtSkew(skew)},請檢查日期與時間設定'
          : '';
      if (mounted) {
        setState(() {
          _testOk = true;
          _testMessage = '連線成功$clockNote';
        });
      }
    } on CareApiException catch (e) {
      if (mounted) {
        setState(() {
          _testOk = false;
          _testMessage = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  static String _fmtSkew(Duration d) => d.inHours >= 48
      ? '${d.inDays} 天'
      : d.inMinutes >= 120
          ? '${d.inHours} 小時'
          : '${d.inMinutes} 分鐘';

  Future<void> _startLink() async {
    if (!await _applyUrl() || !mounted) return;
    setState(() {
      _testOk = null;
      _testMessage = null;
    });
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CareLinkPage(care: _care),
    ));
    // 不管怎麼離開那個畫面(取消、返回、完成),都停止輪詢。
    _care.cancelPairing();
  }

  Future<void> _unlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解除連結?'),
        content: const SingleChildScrollView(
          child: Text(
            '只會清除這台裝置上的連結資料。\n\n'
            '網頁端也要請照護人員解除綁定,否則網頁仍會顯示這位住民已綁定水杯。\n\n'
            '本機紀錄會保留;解除之後的新紀錄不會再上傳。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('解除連結'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _care.unlink();
  }

  Future<void> _syncNow() async {
    final sync = widget.sync;
    if (sync == null) return;
    setState(() => _syncing = true);
    try {
      await sync.syncNow();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = _care.notice;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('照護系統',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (notice != null) ...[
            const SizedBox(height: 8),
            _noticeBox(notice),
          ],
          const SizedBox(height: 8),
          ...(_care.isLinked ? _linked() : _unlinked()),
        ],
      ),
    );
  }

  Widget _noticeBox(String notice) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(notice),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _care.dismissNotice,
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 尚未連結

  List<Widget> _unlinked() {
    final hasCup = _care.pairedCup != null;
    final insecure = _urlController.text.trim().startsWith('http://');
    return [
      const Row(
        children: [
          Icon(Icons.link_off, size: 18, color: AppColors.muted),
          SizedBox(width: 6),
          Text('尚未連結'),
        ],
      ),
      const SizedBox(height: 4),
      const Text('連結後,飲水紀錄會自動傳給照護人員,每日目標改由照護系統設定。', style: mutedSmall),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('care-server-url'),
        controller: _urlController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: '伺服器位址',
          border: const OutlineInputBorder(),
          isDense: true,
          errorText: _urlError,
          errorMaxLines: 3,
        ),
        onChanged: (_) => setState(() {
          _urlError = null;
          _testOk = null;
          _testMessage = null;
        }),
      ),
      if (insecure) ...[
        const SizedBox(height: 6),
        const Text(
          'http 沒有加密,只適合在內部網路測試;Android 與 iOS 預設不允許 http 連線。',
          style: TextStyle(fontSize: 12, color: AppColors.orange),
        ),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _testing ? null : _testConnection,
        icon: _testing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.wifi_tethering),
        label: const Text('測試連線'),
      ),
      if (_testMessage != null) ...[
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _testOk == true ? Icons.check_circle : Icons.error_outline,
              size: 18,
              color: _testOk == true ? AppColors.teal : AppColors.red,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(_testMessage!)),
          ],
        ),
      ],
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: hasCup ? _startLink : null,
        icon: const Icon(Icons.link),
        label: const Text('連結照護系統'),
      ),
      if (!hasCup) ...[
        const SizedBox(height: 6),
        const Text('請先到「水杯」分頁配對水杯,再連結照護系統。', style: mutedSmall),
      ],
    ];
  }

  // ------------------------------------------------------------------ 已連結

  List<Widget> _linked() {
    final link = _care.link!;
    final sync = widget.sync;
    final from = link.goalEffectiveFrom;
    return [
      Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: AppColors.teal),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '已連結:${link.resident.display}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text('每日目標:${describeCareGoal(link.dailyGoalMl)}'
          '${link.dailyGoalMl != null && from != null ? '(自 $from 起)' : ''}'),
      const SizedBox(height: 4),
      Text('水杯:${link.cupName.isEmpty ? '未命名水杯' : link.cupName}',
          style: mutedSmall),
      Text('伺服器:${link.serverUrl}', style: mutedSmall),
      if (_care.otherCupConnected) ...[
        const SizedBox(height: 6),
        Text(
          '目前連線的不是已連結的水杯(${link.cupName}),它的紀錄不會上傳。'
          '要換水杯請先解除連結,再重新連結。',
          style: const TextStyle(fontSize: 12, color: AppColors.orange),
        ),
      ],
      if (sync != null) ...[
        const SizedBox(height: 8),
        Text(_syncSummary(sync)),
        if (sync.rejectedCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            '${sync.rejectedCount} 筆紀錄被照護系統拒收,沒有上傳'
            '(例如水量超出照護系統接受的範圍;修改那筆紀錄後會重新上傳)。',
            style: const TextStyle(fontSize: 12, color: AppColors.orange),
          ),
        ],
        if (sync.lastError != null) ...[
          const SizedBox(height: 4),
          Text(sync.lastError!,
              style: const TextStyle(fontSize: 12, color: AppColors.red)),
        ],
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (sync != null)
            OutlinedButton.icon(
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: const Text('立即同步'),
            ),
          OutlinedButton.icon(
            onPressed: _unlink,
            icon: const Icon(Icons.link_off),
            label: const Text('解除連結'),
          ),
        ],
      ),
    ];
  }

  static String _syncSummary(CareSync sync) {
    final at = sync.lastSyncedAt;
    final last = at == null ? '' : ' · 上次同步 ${fmtTime(at)}';
    if (sync.pendingCount > 0) return '待上傳 ${sync.pendingCount} 筆$last';
    return sync.rejectedCount > 0 ? '其餘紀錄已上傳$last' : '紀錄已全部上傳$last';
  }
}
