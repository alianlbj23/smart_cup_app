import 'dart:async';

import 'package:flutter/material.dart';

import '../services/care_api.dart';
import '../state/care_link_manager.dart';
import 'care_link_panel.dart' show describeCareGoal;
import 'theme.dart';

/// 「連結照護系統」的流程畫面:
///
/// 1. 抓名單,選「我是誰」(只顯示房號-床號與遮蔽後的姓名)。
/// 2. 確認後送出綁定請求,顯示配對碼與倒數,等待照護人員在網頁按下確定。
/// 3. 核准 → 顯示已連結;被拒絕、過期 → 說明原因,可以重新選擇。
///
/// 離開這個畫面(取消、返回)就停止輪詢:開啟這個畫面的地方在 `Navigator.push`
/// 回來之後呼叫 [CareLinkManager.cancelPairing],這裡的 [State.dispose] 也會再保險一次。
class CareLinkPage extends StatefulWidget {
  const CareLinkPage({super.key, required this.care});

  final CareLinkManager care;

  @override
  State<CareLinkPage> createState() => _CareLinkPageState();
}

class _CareLinkPageState extends State<CareLinkPage> {
  List<CareResident>? _residents;
  String? _loadError;
  bool _loading = false;

  /// 送出綁定請求中(按下「送出」到伺服器回應之間)。
  bool _starting = false;
  String? _startError;

  /// 等待核准時每秒重畫一次倒數。
  Timer? _ticker;

  CareLinkManager get _care => widget.care;

  @override
  void initState() {
    super.initState();
    _care.addListener(_onCare);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_care.pairing?.status == CarePairingStatus.waiting) setState(() {});
    });
    _loadResidents();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _care.removeListener(_onCare);
    // 畫面不是被 pop 掉(例如整個 App 的畫面被拆掉)時也要停止輪詢。
    // 不能在 dispose 當下通知其他 widget 重畫,排到這一輪結束之後。
    final care = _care;
    scheduleMicrotask(care.cancelPairing);
    super.dispose();
  }

  void _onCare() {
    if (mounted) setState(() {});
  }

  Future<void> _loadResidents() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await _care.fetchResidents();
      if (!mounted) return;
      setState(() => _residents = list);
    } on CareApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose(CareResident resident) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('確定是「${resident.display}」嗎?'),
        content: const Text('送出後,請照護人員在網頁上按下「確定綁定」,這支手機的飲水紀錄就會記在這位住民名下。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('送出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      await _care.startPairing(resident);
    } on CareLinkException catch (e) {
      if (mounted) setState(() => _startError = e.message);
    } on CareApiException catch (e) {
      if (mounted) setState(() => _startError = e.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _care.pairing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('連結照護系統'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: switch (pairing?.status) {
          null => _chooser(),
          CarePairingStatus.waiting => _waiting(pairing!),
          CarePairingStatus.approved => _approved(),
          CarePairingStatus.denied ||
          CarePairingStatus.expired ||
          CarePairingStatus.failed =>
            _ended(pairing!),
        },
      ),
    );
  }

  // ------------------------------------------------------------ 選我是誰

  Widget _chooser() {
    final residents = _residents;
    if (_starting || (_loading && residents == null)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (residents == null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        color: AppColors.red,
        title: '抓不到住民名單',
        detail: _loadError ?? '',
        actions: [
          FilledButton(onPressed: _loadResidents, child: const Text('重試')),
        ],
      );
    }
    if (residents.isEmpty) {
      return _Message(
        icon: Icons.person_off_outlined,
        color: AppColors.muted,
        title: '照護系統目前沒有可以選擇的住民',
        detail: '請照護人員先在網頁上建立住民資料。',
        actions: [
          OutlinedButton(onPressed: _loadResidents, child: const Text('重新整理')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('請選擇您是哪一位',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('依房號、床號排列;姓名已遮蔽。', style: mutedSmall),
        ),
        if (_startError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(_startError!,
                style: const TextStyle(color: AppColors.red)),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: residents.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, i) {
              final r = residents[i];
              return ListTile(
                tileColor: Colors.white,
                leading:
                    const Icon(Icons.person_outline, color: AppColors.teal),
                title: Text(r.display, style: const TextStyle(fontSize: 17)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _choose(r),
              );
            },
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ 等待核准

  Widget _waiting(CarePairing pairing) {
    final left = pairing.remaining(_care.now);
    final mm = left.inMinutes;
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('我是:${pairing.resident.display}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 24),
        const Text('配對碼', textAlign: TextAlign.center, style: mutedSmall),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: SelectableText(
            pairing.pairingCode,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
              color: AppColors.teal,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '等待照護人員在網頁按下確定…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '請照護人員在網頁上這位住民的頁面核對配對碼,再按「確定綁定」。',
          textAlign: TextAlign.center,
          style: mutedSmall,
        ),
        const SizedBox(height: 16),
        Text('配對碼有效時間 $mm:$ss',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()])),
        if (pairing.warning != null) ...[
          const SizedBox(height: 12),
          Text(pairing.warning!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.orange)),
        ],
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 結果

  Widget _approved() {
    final link = _care.link;
    return _Message(
      icon: Icons.check_circle_outline,
      color: AppColors.teal,
      title: link == null ? '已連結' : '已連結:${link.resident.display}',
      detail: link == null
          ? ''
          : '每日目標:${describeCareGoal(link.dailyGoalMl)}\n'
              '之後的飲水紀錄會自動上傳到照護系統。',
      actions: [
        FilledButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _ended(CarePairing pairing) {
    return _Message(
      icon: pairing.status == CarePairingStatus.denied
          ? Icons.block
          : Icons.timer_off_outlined,
      color: AppColors.orange,
      title: switch (pairing.status) {
        CarePairingStatus.denied => '連結請求被拒絕',
        CarePairingStatus.expired => '配對碼已過期',
        _ => '無法完成連結',
      },
      detail: pairing.message ?? '',
      actions: [
        FilledButton(
          // 清掉這次的結果,回到名單。
          onPressed: _care.cancelPairing,
          child: const Text('重新選擇'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

/// 置中的圖示 + 標題 + 說明 + 按鈕。
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.actions,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
