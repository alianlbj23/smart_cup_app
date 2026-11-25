import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/intake_repository.dart';
import '../theme.dart';

/// 事件對話框的結果。
sealed class IntakeEventDialogResult {
  const IntakeEventDialogResult();
}

/// 儲存(新增或修改)。
class IntakeEventSave extends IntakeEventDialogResult {
  const IntakeEventSave({required this.time, required this.ml, required this.kind});

  final DateTime time;
  final int ml;
  final IntakeKind kind;
}

/// 刪除既有事件。
class IntakeEventDelete extends IntakeEventDialogResult {
  const IntakeEventDelete();
}

/// 單次最多可輸入的毫升數。和照護系統 `cup/events/` 的上限一致(合約 §2.2:ml 0–2000),
/// 超過的紀錄會被伺服器拒收。
const maxEventMl = 2000;

String intakeKindLabel(IntakeKind k) => switch (k) {
      IntakeKind.drink => '喝水',
      IntakeKind.refill => '加水',
      IntakeKind.discard => '倒掉',
    };

/// 新增或修改一筆紀錄。[existing] 為 null 時是「手動新增」:
/// 預設時間為 [initialTime]、200 mL、喝水。日期固定為 [day],只能改時間。
/// 取消回傳 null。
Future<IntakeEventDialogResult?> showIntakeEventDialog(
  BuildContext context, {
  IntakeEvent? existing,
  required DateTime day,
  required DateTime initialTime,
  required DateTime now,
}) =>
    showDialog<IntakeEventDialogResult>(
      context: context,
      builder: (_) => IntakeEventDialog(
        existing: existing,
        day: day,
        initialTime: initialTime,
        now: now,
      ),
    );

class IntakeEventDialog extends StatefulWidget {
  const IntakeEventDialog({
    super.key,
    this.existing,
    required this.day,
    required this.initialTime,
    required this.now,
  });

  final IntakeEvent? existing;
  final DateTime day;
  final DateTime initialTime;
  final DateTime now;

  @override
  State<IntakeEventDialog> createState() => _IntakeEventDialogState();
}

class _IntakeEventDialogState extends State<IntakeEventDialog> {
  late final TextEditingController _ml;
  late TimeOfDay _time;
  late IntakeKind _kind;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final t = e?.startedAt ?? widget.initialTime;
    _time = TimeOfDay(hour: t.hour, minute: t.minute);
    _kind = e?.kind ?? IntakeKind.drink;
    _ml = TextEditingController(text: '${e?.ml ?? 200}');
  }

  @override
  void dispose() {
    _ml.dispose();
    super.dispose();
  }

  DateTime get _dateTime {
    final d = widget.day;
    // 保留原本的秒數,只改時、分時不會無端變動排序。
    final sec = widget.existing?.startedAt.second ?? 0;
    return DateTime(d.year, d.month, d.day, _time.hour, _time.minute, sec);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: '選擇時間',
      cancelText: '取消',
      confirmText: '確定',
    );
    if (t != null) setState(() => _time = t);
  }

  void _save() {
    final ml = int.tryParse(_ml.text.trim());
    if (ml == null || ml <= 0 || ml > maxEventMl) {
      setState(() => _error = '請輸入 1–$maxEventMl 之間的毫升數');
      return;
    }
    final time = _dateTime;
    if (time.isAfter(widget.now)) {
      setState(() => _error = '時間不能晚於現在');
      return;
    }
    Navigator.of(context).pop(IntakeEventSave(time: time, ml: ml, kind: _kind));
  }

  @override
  Widget build(BuildContext context) {
    final t = _dateTime;
    return AlertDialog(
      title: Text(_isNew ? '手動新增' : '修改紀錄'),
      scrollable: true,
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('時間', style: mutedSmall),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              key: const ValueKey('event-time'),
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule, size: 18),
              label: Text('${t.month}/${t.day} ${fmtTime(t)}'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('event-ml'),
              controller: _ml,
              autofocus: _isNew,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '水量',
                suffixText: 'mL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            const Text('種類', style: mutedSmall),
            const SizedBox(height: 4),
            SegmentedButton<IntakeKind>(
              showSelectedIcon: false,
              segments: [
                for (final k in IntakeKind.values)
                  ButtonSegment(value: k, label: Text(intakeKindLabel(k))),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            if (_kind != IntakeKind.drink)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('加水、倒掉不計入飲水量', style: mutedSmall),
              ),
            if (_error case final err?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(err,
                    style: const TextStyle(fontSize: 12, color: AppColors.red)),
              ),
          ],
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const IntakeEventDelete()),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('刪除'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('儲存')),
      ],
    );
  }
}
