import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

export 'database.dart'
    show
        AppDatabase,
        CupRow,
        DrinkerRow,
        IntakeEvent,
        IntakeKind,
        IntakeSource,
        IntakeStatus;

/// 當地日期 key:yyyy-MM-dd(依 [t] 自己的時區)。
String dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// [dayKey] 的反向:回傳當地時間該日 00:00。
DateTime parseDayKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// 當地時間 [t] 那天的 00:00。
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

extension IntakeEventX on IntakeEvent {
  /// 事件開始時間(本機時區)。
  DateTime get startedAt => DateTime.fromMillisecondsSinceEpoch(startedAtMs);
  DateTime? get endedAt => endedAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(endedAtMs!);

  /// 是否計入飲水量:喝水且狀態正常。
  bool get countsAsIntake =>
      kind == IntakeKind.drink && status == IntakeStatus.ok;
}

/// 飲水紀錄、水杯與飲用者設定的存取層(SQLite / drift)。
///
/// 寫入後會 [notifyListeners],UI 收到通知再重新查詢即可。
class IntakeRepository extends ChangeNotifier {
  IntakeRepository(this._db, {DateTime Function()? clock, Uuid? uuid})
      : _clock = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  /// 單機版唯一的飲用者 id。
  static const defaultDrinkerId = 'me';
  static const defaultCupCapacityMl = 350;
  static const defaultDailyGoalMl = 1500;

  final AppDatabase _db;
  final DateTime Function() _clock;
  final Uuid _uuid;

  DrinkerRow? _drinker;

  AppDatabase get db => _db;

  /// 目前的飲用者;[init] 之前為 null。
  DrinkerRow? get drinker => _drinker;
  int get dailyGoalMl => _drinker?.dailyGoalMl ?? defaultDailyGoalMl;

  int get _nowMs => _clock().millisecondsSinceEpoch;

  /// 確保預設飲用者存在。App 啟動時呼叫一次。
  Future<void> init() async {
    await _db.into(_db.drinkers).insert(
          DrinkersCompanion.insert(
            id: defaultDrinkerId,
            name: '我',
            updatedAtMs: _nowMs,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    _drinker = await (_db.select(_db.drinkers)
          ..where((d) => d.id.equals(defaultDrinkerId)))
        .getSingle();
    notifyListeners();
  }

  Future<void> setDailyGoal(int ml) async {
    await (_db.update(_db.drinkers)
          ..where((d) => d.id.equals(defaultDrinkerId)))
        .write(DrinkersCompanion(
      dailyGoalMl: Value(ml),
      updatedAtMs: Value(_nowMs),
    ));
    _drinker = _drinker?.copyWith(dailyGoalMl: ml, updatedAtMs: _nowMs);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 水杯

  Future<CupRow?> cup(String id) =>
      (_db.select(_db.cups)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<CupRow>> cups() => _db.select(_db.cups).get();

  /// 連上水杯時呼叫:第一次看到就建立(預設容量),之後只更新名稱。
  Future<CupRow> ensureCup(String id, String name) async {
    final existing = await cup(id);
    if (existing == null) {
      final now = _nowMs;
      await _db.into(_db.cups).insert(CupsCompanion.insert(
            id: id,
            name: name,
            createdAtMs: now,
            updatedAtMs: now,
          ));
      notifyListeners();
      return (await cup(id))!;
    }
    if (name.isNotEmpty && existing.name != name) {
      await (_db.update(_db.cups)..where((c) => c.id.equals(id))).write(
          CupsCompanion(name: Value(name), updatedAtMs: Value(_nowMs)));
      notifyListeners();
      return (await cup(id))!;
    }
    return existing;
  }

  Future<void> setCupCapacity(String id, int capacityMl) async {
    await (_db.update(_db.cups)..where((c) => c.id.equals(id))).write(
        CupsCompanion(
            capacityMl: Value(capacityMl), updatedAtMs: Value(_nowMs)));
    notifyListeners();
  }

  // ---------------------------------------------------------------- 事件

  Future<IntakeEvent> addEvent({
    required IntakeKind kind,
    required int ml,
    required DateTime startedAt,
    DateTime? endedAt,
    String? cupId,
    int? beforeMl,
    int? afterMl,
    IntakeSource source = IntakeSource.manual,
    IntakeStatus status = IntakeStatus.ok,
  }) async {
    final local = startedAt.toLocal();
    final id = _uuid.v4();
    await _db.into(_db.intakeEvents).insert(IntakeEventsCompanion.insert(
          id: id,
          drinkerId: defaultDrinkerId,
          cupId: Value(cupId),
          kind: kind,
          ml: ml,
          startedAtMs: local.millisecondsSinceEpoch,
          endedAtMs: Value(endedAt?.millisecondsSinceEpoch),
          tzOffsetMin: local.timeZoneOffset.inMinutes,
          localDay: dayKey(local),
          beforeMl: Value(beforeMl),
          afterMl: Value(afterMl),
          source: source,
          status: Value(status),
          updatedAtMs: _nowMs,
        ));
    notifyListeners();
    return (await event(id))!;
  }

  Future<IntakeEvent?> event(String id) =>
      (_db.select(_db.intakeEvents)..where((e) => e.id.equals(id)))
          .getSingleOrNull();

  /// 修改事件。改時間會一併更新 localDay / tzOffsetMin。
  Future<void> updateEvent(
    String id, {
    int? ml,
    DateTime? startedAt,
    IntakeKind? kind,
    IntakeStatus? status,
  }) async {
    final local = startedAt?.toLocal();
    await (_db.update(_db.intakeEvents)..where((e) => e.id.equals(id)))
        .write(IntakeEventsCompanion(
      ml: ml == null ? const Value.absent() : Value(ml),
      kind: kind == null ? const Value.absent() : Value(kind),
      status: status == null ? const Value.absent() : Value(status),
      startedAtMs: local == null
          ? const Value.absent()
          : Value(local.millisecondsSinceEpoch),
      tzOffsetMin: local == null
          ? const Value.absent()
          : Value(local.timeZoneOffset.inMinutes),
      localDay: local == null ? const Value.absent() : Value(dayKey(local)),
      updatedAtMs: Value(_nowMs),
    ));
    notifyListeners();
  }

  /// 軟刪除:狀態改為 deleted,不再顯示也不計入。
  Future<void> deleteEvent(String id) =>
      updateEvent(id, status: IntakeStatus.deleted);

  /// [fromDay] 到 [toDay](皆含,當地日期)之間的事件,依時間排序。
  /// 預設不含已刪除。
  Future<List<IntakeEvent>> eventsInDays(
    DateTime fromDay,
    DateTime toDay, {
    bool includeDeleted = false,
  }) {
    final q = _db.select(_db.intakeEvents)
      ..where((e) =>
          e.drinkerId.equals(defaultDrinkerId) &
          e.localDay.isBetweenValues(dayKey(fromDay), dayKey(toDay)))
      ..orderBy([(e) => OrderingTerm.asc(e.startedAtMs)]);
    if (!includeDeleted) {
      q.where((e) => e.status.equalsValue(IntakeStatus.deleted).not());
    }
    return q.get();
  }

  Future<List<IntakeEvent>> eventsOnDay(DateTime day) =>
      eventsInDays(day, day);

  /// 每日飲水量(只算 [IntakeEventX.countsAsIntake]),key 為當地日期 00:00。
  /// 區間內沒有喝水的日子也會出現,值為 0。
  Future<Map<DateTime, int>> dailyTotals(DateTime fromDay, DateTime toDay) async {
    final total = _db.intakeEvents.ml.sum();
    final rows = await (_db.selectOnly(_db.intakeEvents)
          ..addColumns([_db.intakeEvents.localDay, total])
          ..where(_db.intakeEvents.drinkerId.equals(defaultDrinkerId) &
              _db.intakeEvents.kind.equalsValue(IntakeKind.drink) &
              _db.intakeEvents.status.equalsValue(IntakeStatus.ok) &
              _db.intakeEvents.localDay
                  .isBetweenValues(dayKey(fromDay), dayKey(toDay)))
          ..groupBy([_db.intakeEvents.localDay]))
        .get();
    final byKey = {
      for (final r in rows)
        r.read(_db.intakeEvents.localDay)!: r.read(total) ?? 0,
    };
    final result = <DateTime, int>{};
    for (var d = startOfDay(fromDay);
        !d.isAfter(startOfDay(toDay));
        d = DateTime(d.year, d.month, d.day + 1)) {
      result[d] = byKey[dayKey(d)] ?? 0;
    }
    return result;
  }

  // ---------------------------------------------------------------- 備份

  /// 所有事件(含已刪除),依時間排序,匯出用。
  Future<List<IntakeEvent>> allEvents() => (_db.select(_db.intakeEvents)
        ..orderBy([(e) => OrderingTerm.asc(e.startedAtMs)]))
      .get();

  /// 匯入事件:依 id 合併,同 id 以 updatedAtMs 較新者為準。
  /// 回傳實際新增或更新的筆數。
  Future<int> importEvents(Iterable<IntakeEvent> events) async {
    var changed = 0;
    await _db.transaction(() async {
      for (final e in events) {
        final existing = await event(e.id);
        if (existing != null && existing.updatedAtMs >= e.updatedAtMs) {
          continue;
        }
        // 匯入的資料一律歸到本機的飲用者。
        final row = e.copyWith(drinkerId: defaultDrinkerId);
        if (existing == null) {
          // 同一水杯同一時間已有事件(例如韌體補傳過)就略過。
          if (row.cupId != null &&
              await (_db.select(_db.intakeEvents)
                        ..where((x) =>
                            x.cupId.equals(row.cupId!) &
                            x.startedAtMs.equals(row.startedAtMs)))
                      .getSingleOrNull() !=
                  null) {
            continue;
          }
          await _db.into(_db.intakeEvents).insert(row);
          changed++;
        } else {
          await _db.update(_db.intakeEvents).replace(row);
          changed++;
        }
      }
    });
    if (changed > 0) notifyListeners();
    return changed;
  }

  /// 匯入水杯設定:依 id 合併,同 id 以 updatedAtMs 較新者為準。
  Future<void> importCups(Iterable<CupRow> cups) async {
    await _db.transaction(() async {
      for (final c in cups) {
        final existing = await cup(c.id);
        if (existing != null && existing.updatedAtMs >= c.updatedAtMs) {
          continue;
        }
        await _db.into(_db.cups).insertOnConflictUpdate(c);
      }
    });
    notifyListeners();
  }
}
