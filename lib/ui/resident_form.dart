import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/resident.dart';
import '../state/care_store.dart';
import 'theme.dart';

/// 新增([resident] 為 null)或編輯住民。
Future<void> showResidentForm(
  BuildContext context,
  CareStore store, {
  Resident? resident,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ResidentForm(store: store, resident: resident),
  );
}

class _ResidentForm extends StatefulWidget {
  const _ResidentForm({required this.store, this.resident});

  final CareStore store;
  final Resident? resident;

  @override
  State<_ResidentForm> createState() => _ResidentFormState();
}

class _ResidentFormState extends State<_ResidentForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.resident?.name);
  late final _room = TextEditingController(text: widget.resident?.room);
  late final _age =
      TextEditingController(text: widget.resident?.age.toString());
  late final _goal = TextEditingController(
      text: (widget.resident?.goalMl ?? 1500).toString());
  late final _tags =
      TextEditingController(text: widget.resident?.tags.join('、'));

  @override
  void dispose() {
    for (final c in [_name, _room, _age, _goal, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final room = _room.text.trim();
    final age = int.tryParse(_age.text) ?? 0;
    final goal = int.parse(_goal.text);
    final tags = _tags.text
        .split(RegExp(r'[、,,\s]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final existing = widget.resident;
    if (existing == null) {
      await widget.store.addResident(
          name: name, room: room, age: age, goalMl: goal, tags: tags);
    } else {
      await widget.store.updateResident(existing.id,
          name: name, room: room, age: age, goalMl: goal, tags: tags);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text(widget.resident == null ? '新增住民' : '編輯住民'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: widget.resident == null,
                  decoration: const InputDecoration(labelText: '姓名'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '請輸入姓名' : null,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _room,
                        decoration:
                            const InputDecoration(labelText: '房號/床號'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _age,
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        decoration: const InputDecoration(labelText: '年齡'),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _goal,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: const InputDecoration(
                    labelText: '每日飲水目標',
                    suffixText: 'mL',
                    helperText: '一般參考 25–30 mL × 體重(kg);有醫囑以醫囑為準',
                    helperMaxLines: 2,
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return (n == null || n <= 0) ? '請輸入大於 0 的毫升數' : null;
                  },
                ),
                TextFormField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: '照護註記',
                    hintText: '例如:高血壓、吞嚥照護',
                    hintStyle: TextStyle(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('儲存')),
      ],
    );
  }
}
