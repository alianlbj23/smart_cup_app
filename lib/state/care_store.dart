import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/resident.dart';

/// 住民、飲水紀錄與「住民 ↔ 水杯」配對的本機儲存。
class CareStore extends ChangeNotifier {
  static const _key = 'care_residents_v1';

  /// 超過此天數的飲水紀錄在載入時清除。
  static const _keepDays = 30;

  List<Resident> _residents = [];
  String? _selectedId;
  bool _loaded = false;
  int _idSeq = 0;

  bool get loaded => _loaded;
  List<Resident> get residents => List.unmodifiable(_residents);

  /// 目前選取的住民;未選取時為第一位。
  Resident? get selected =>
      byId(_selectedId) ?? (_residents.isEmpty ? null : _residents.first);

  Resident? byId(String? id) {
    if (id == null) return null;
    for (final r in _residents) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// 配對到 [cupId] 的住民。
  Resident? ownerOfCup(String? cupId) {
    if (cupId == null) return null;
    for (final r in _residents) {
      if (r.cupId == cupId) return r;
    }
    return null;
  }

  /// 首次啟動(尚無任何儲存資料)時載入示範住民。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      _residents = _demoResidents(DateTime.now());
      await _save();
    } else {
      final cutoff = DateTime.now().subtract(const Duration(days: _keepDays));
      _residents = [
        for (final e in jsonDecode(raw) as List)
          Resident.fromJson((e as Map).cast<String, dynamic>())
            ..intakes.removeWhere((i) => i.time.isBefore(cutoff)),
      ];
    }
    _loaded = true;
    notifyListeners();
  }

  void select(String id) {
    _selectedId = id;
    notifyListeners();
  }

  Future<Resident> addResident({
    required String name,
    required String room,
    required int age,
    required int goalMl,
    List<String> tags = const [],
  }) {
    final resident = Resident(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}',
      name: name,
      room: room,
      age: age,
      goalMl: goalMl,
      tags: [...tags],
    );
    _residents.add(resident);
    _selectedId = resident.id;
    return _commit().then((_) => resident);
  }

  Future<void> updateResident(
    String id, {
    required String name,
    required String room,
    required int age,
    required int goalMl,
    required List<String> tags,
  }) {
    final r = byId(id);
    if (r == null) return Future.value();
    r
      ..name = name
      ..room = room
      ..age = age
      ..goalMl = goalMl
      ..tags = [...tags];
    return _commit();
  }

  Future<void> removeResident(String id) {
    _residents.removeWhere((r) => r.id == id);
    if (_selectedId == id) _selectedId = null;
    return _commit();
  }

  Future<void> addIntake(String id, int ml, {DateTime? at}) {
    final r = byId(id);
    if (r == null) return Future.value();
    r.intakes.add(IntakeEntry(time: at ?? DateTime.now(), ml: ml));
    return _commit();
  }

  /// 復原 [id] 今日最後一筆飲水紀錄。
  Future<void> undoLastIntake(String id) {
    final r = byId(id);
    if (r == null || r.intakes.isEmpty) return Future.value();
    if (!isSameDay(r.intakes.last.time, DateTime.now())) return Future.value();
    r.intakes.removeLast();
    return _commit();
  }

  /// 將水杯配對給住民;一個水杯只屬於一位住民,原配對會被移除。
  Future<void> assignCup(String residentId, String cupId, String cupName) {
    final r = byId(residentId);
    if (r == null) return Future.value();
    for (final other in _residents) {
      if (other.cupId == cupId) {
        other
          ..cupId = null
          ..cupName = null;
      }
    }
    r
      ..cupId = cupId
      ..cupName = cupName;
    return _commit();
  }

  Future<void> unassignCup(String residentId) {
    final r = byId(residentId);
    if (r == null) return Future.value();
    r
      ..cupId = null
      ..cupName = null;
    return _commit();
  }

  Future<void> _commit() {
    notifyListeners();
    return _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final r in _residents) r.toJson()]),
    );
  }

  /// 示範資料:讓首次啟動即可看到完整畫面,可於「住民資料」刪除。
  static List<Resident> _demoResidents(DateTime now) {
    const seeds = [
      ('周德昌', 'A112', 81, 1500, 0.95, ['高血壓']),
      ('林陳和', 'C101', 82, 1500, 0.9, <String>[]),
      ('陳建和', 'C102', 79, 1600, 0.55, <String>[]),
      ('吳阿和', 'C103', 88, 1400, 0.75, ['吞嚥照護']),
      ('李添和', 'C104', 76, 1200, 1.0, <String>[]),
      ('王秀和', 'C105', 84, 1500, 1.05, <String>[]),
      ('張進和', 'C106', 73, 1800, 0.8, <String>[]),
      ('黃郭和', 'C107', 90, 1300, 0.6, ['心衰竭']),
      ('許文和', 'C108', 78, 1600, 1.05, <String>[]),
      ('蔡寶和', 'C109', 85, 1500, 0.65, <String>[]),
      ('鄭清和', 'C110', 80, 1700, 1.1, <String>[]),
      ('楊林和', 'C111', 87, 1400, 0.5, ['腎病']),
    ];
    const slotHours = [7, 9, 11, 13, 15, 17, 19];
    return [
      for (final (i, (name, room, age, goal, pace, tags)) in seeds.indexed)
        Resident(
          id: 'demo-$i',
          name: name,
          room: room,
          age: age,
          goalMl: goal,
          tags: [...tags],
          intakes: [
            for (final h in slotHours)
              if (DateTime(now.year, now.month, now.day, h, (i * 7) % 60)
                  case final t when !t.isAfter(now))
                IntakeEntry(
                  time: t,
                  ml: (goal / slotHours.length * pace / 10).round() * 10,
                ),
          ],
        ),
    ];
  }
}
