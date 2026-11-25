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

/// [IntakeRepository.addFirmwareEvent] 的結果:[created] 為 false 代表這筆事件
/// 之前就收過(韌體重送),[event] 是已經存在的那一筆。
typedef FirmwareEventResult = ({IntakeEvent event, bool created});

/// 一筆紀錄的版本:id + 上傳當下的 updatedAtMs。
typedef SyncedVersion = ({String id, int updatedAtMs});

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

  /// 存在本機的每日目標(`drinkers.daily_goal_ml`)。畫面要顯示的目標請用 [goalMl]。
  int get dailyGoalMl => _drinker?.dailyGoalMl ?? defaultDailyGoalMl;

  /// 已連結照護系統:每日目標以 Server 為準,不能在 App 修改。
  bool get goalFromServer => _drinker?.goalFromServer ?? false;

  /// 目前有效的每日目標(mL)。已連結照護系統而照護系統還沒設定目標時為 null:
  /// 畫面要顯示「照護系統尚未設定目標」,不可以套用任何預設值。
  int? get goalMl => goalFromServer ? _drinker?.serverGoalMl : dailyGoalMl;

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

  /// 修改本機的每日目標。已連結照護系統時目標以 Server 為準,會丟出 [StateError]。
  Future<void> setDailyGoal(int ml) async {
    if (goalFromServer) {
      throw StateError('已連結照護系統,每日目標由照護系統設定');
    }
    await (_db.update(_db.drinkers)
          ..where((d) => d.id.equals(defaultDrinkerId)))
        .write(DrinkersCompanion(
      dailyGoalMl: Value(ml),
      updatedAtMs: Value(_nowMs),
    ));
    _drinker = _drinker?.copyWith(dailyGoalMl: ml, updatedAtMs: _nowMs);
    notifyListeners();
  }

  /// 已連結照護系統:套用 Server 回傳的每日目標。[ml] 為 null 代表照護系統還沒設定,
  /// 之後 [goalMl] 為 null;有值時一併更新 `drinkers.daily_goal_ml`。
  Future<void> applyServerGoal(int? ml) async {
    if (ml != null && ml <= 0) {
      throw ArgumentError.value(ml, 'ml', '每日目標必須是正整數');
    }
    final d = _drinker;
    if (d != null && d.goalFromServer && d.serverGoalMl == ml) return;
    await (_db.update(_db.drinkers)
          ..where((d) => d.id.equals(defaultDrinkerId)))
        .write(DrinkersCompanion(
      goalFromServer: const Value(true),
      serverGoalMl: Value(ml),
      dailyGoalMl: ml == null ? const Value.absent() : Value(ml),
      updatedAtMs: Value(_nowMs),
    ));
    await _reloadDrinker();
    notifyListeners();
  }

  /// 解除連結(或連結失效):回到單機行為,目標是 `drinkers.daily_goal_ml`
  /// (照護系統設定過就是最後那個值),可以再由使用者修改。
  Future<void> clearServerGoal() async {
    if (!goalFromServer) return;
    await (_db.update(_db.drinkers)
          ..where((d) => d.id.equals(defaultDrinkerId)))
        .write(DrinkersCompanion(
      goalFromServer: const Value(false),
      serverGoalMl: const Value(null),
      updatedAtMs: Value(_nowMs),
    ));
    await _reloadDrinker();
    notifyListeners();
  }

  Future<void> _reloadDrinker() async {
    _drinker = await (_db.select(_db.drinkers)
          ..where((d) => d.id.equals(defaultDrinkerId)))
        .getSingle();
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

  /// 記下水杯自己回報的 BLE 位址(Device Status,韌體 0.4.0 起)。
  Future<void> setCupBleAddress(String id, String address) async {
    await (_db.update(_db.cups)..where((c) => c.id.equals(id))).write(
        CupsCompanion(bleAddress: Value(address), updatedAtMs: Value(_nowMs)));
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
    int? capacityMl,
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
          capacityMl: Value(capacityMl),
          source: source,
          status: Value(status),
          updatedAtMs: _nowMs,
        ));
    notifyListeners();
    return (await event(id))!;
  }

  /// 寫入一筆韌體送來的事件(DRINK_EVENT 0x07),來源為 [IntakeSource.firmware]、
  /// 狀態一律 ok。
  ///
  /// 以 `(cupId, dedupKey)` 去重:韌體沒收到 ACK 會重送同一筆,已經存在(包含
  /// 使用者之後刪除的)就不再新增,回傳 `created: false`。
  ///
  /// [startedAt]:韌體的時間戳;[timeEstimated] 為 true 時是 App 收到的時間。
  /// 同一個水杯剛好有另一筆事件在同一毫秒時往後挪 1 ms(既有的
  /// `(cupId, startedAtMs)` 唯一鍵),不同的事件不會因此被丟掉。
  Future<FirmwareEventResult> addFirmwareEvent({
    required String cupId,
    required String dedupKey,
    required IntakeKind kind,
    required int ml,
    required DateTime startedAt,
    required bool timeEstimated,
    required int capacityMl,
    required double levelBeforePct,
    required double levelAfterPct,
    required bool sawDrinking,
    required bool tooLong,
    required int seq,
  }) async {
    final local = startedAt.toLocal();
    final result = await _db.transaction<FirmwareEventResult>(() async {
      final existing = await (_db.select(_db.intakeEvents)
            ..where((e) => e.cupId.equals(cupId) & e.fwKey.equals(dedupKey)))
          .getSingleOrNull();
      if (existing != null) return (event: existing, created: false);

      var startedAtMs = local.millisecondsSinceEpoch;
      while (await (_db.select(_db.intakeEvents)
                ..where((e) =>
                    e.cupId.equals(cupId) & e.startedAtMs.equals(startedAtMs)))
              .getSingleOrNull() !=
          null) {
        startedAtMs++;
      }
      final id = _uuid.v4();
      await _db.into(_db.intakeEvents).insert(IntakeEventsCompanion.insert(
            id: id,
            drinkerId: defaultDrinkerId,
            cupId: Value(cupId),
            kind: kind,
            ml: ml,
            startedAtMs: startedAtMs,
            tzOffsetMin: local.timeZoneOffset.inMinutes,
            localDay: dayKey(local),
            beforeMl: Value((levelBeforePct / 100 * capacityMl).round()),
            afterMl: Value((levelAfterPct / 100 * capacityMl).round()),
            capacityMl: Value(capacityMl),
            levelBeforePct: Value(levelBeforePct),
            levelAfterPct: Value(levelAfterPct),
            timeEstimated: Value(timeEstimated),
            sawDrinking: Value(sawDrinking),
            tooLong: Value(tooLong),
            fwSeq: Value(seq),
            fwKey: Value(dedupKey),
            source: IntakeSource.firmware,
            status: const Value(IntakeStatus.ok),
            updatedAtMs: _nowMs,
          ));
      return (event: (await event(id))!, created: true);
    });
    if (result.created) notifyListeners();
    return result;
  }

  Future<IntakeEvent?> event(String id) =>
      (_db.select(_db.intakeEvents)..where((e) => e.id.equals(id)))
          .getSingleOrNull();

  /// 修改事件。改時間會一併更新 localDay / tzOffsetMin。
  ///
  /// 每次修改 updatedAtMs 一定比上一版大(同一毫秒內也是),並清掉同步狀態:
  /// 照護系統以 `updated_at` 較新的為準,這一版要重新上傳。
  Future<void> updateEvent(
    String id, {
    int? ml,
    DateTime? startedAt,
    IntakeKind? kind,
    IntakeStatus? status,
  }) async {
    final local = startedAt?.toLocal();
    await _db.transaction(() async {
      final existing = await event(id);
      if (existing == null) return;
      final now = _nowMs;
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
        updatedAtMs: Value(
            now > existing.updatedAtMs ? now : existing.updatedAtMs + 1),
        syncedAtMs: const Value(null),
        syncError: const Value(null),
      ));
    });
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

  // ---------------------------------------------------------------- 同步

  /// 還沒上傳照護系統的事件(含軟刪除),依 updatedAtMs 由舊到新,最多 [limit] 筆。
  ///
  /// - 只取已連結的水杯 [cupId] 的紀錄,以及手動輸入(沒有水杯)的紀錄。
  /// - 標成不需同步(`syncExcluded`,見 [excludeAllFromSync])的不上傳。
  /// - 被照護系統拒收(`syncError` 有值)的不再重送,直到紀錄再被修改。
  Future<List<IntakeEvent>> pendingSyncEvents({
    required String cupId,
    int limit = 200,
  }) =>
      (_db.select(_db.intakeEvents)
            ..where((e) => _pendingSync(e, cupId))
            ..orderBy([
              (e) => OrderingTerm.asc(e.updatedAtMs),
              (e) => OrderingTerm.asc(e.id),
            ])
            ..limit(limit))
          .get();

  /// [pendingSyncEvents] 的總筆數(不受 limit 限制)。
  Future<int> pendingSyncCount({required String cupId}) async {
    final count = _db.intakeEvents.id.count();
    final row = await (_db.selectOnly(_db.intakeEvents)
          ..addColumns([count])
          ..where(_pendingSync(_db.intakeEvents, cupId)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  /// 被照護系統拒收、目前沒有上傳的紀錄筆數(`syncError` 有值;修改後會重新排入)。
  Future<int> rejectedSyncCount({required String cupId}) async {
    final e = _db.intakeEvents;
    final count = e.id.count();
    final row = await (_db.selectOnly(e)
          ..addColumns([count])
          ..where(e.drinkerId.equals(defaultDrinkerId) &
              e.syncedAtMs.isNull() &
              e.syncError.isNotNull() &
              (e.syncExcluded.isNull() | e.syncExcluded.equals(false)) &
              (e.cupId.isNull() | e.cupId.equals(cupId))))
        .getSingle();
    return row.read(count) ?? 0;
  }

  Expression<bool> _pendingSync($IntakeEventsTable e, String cupId) =>
      e.drinkerId.equals(defaultDrinkerId) &
      e.syncedAtMs.isNull() &
      e.syncError.isNull() &
      (e.syncExcluded.isNull() | e.syncExcluded.equals(false)) &
      (e.cupId.isNull() | e.cupId.equals(cupId));

  /// 把本機現有的紀錄全部標成不需同步(已經上傳過的也算),之後再修改也不會上傳。
  /// 回傳這次標了幾筆。
  ///
  /// 連結到「和上次不同的住民」(或第一次連結)核准的當下呼叫:Server 會收下早於
  /// 綁定時間的事件並算在 token 所屬的住民身上,連結之前的紀錄不可以算到他頭上。
  /// 重新連結到同一位住民時不要呼叫,沒上傳的紀錄才會補傳。
  Future<int> excludeAllFromSync() =>
      (_db.update(_db.intakeEvents)
            ..where((e) =>
                e.syncExcluded.isNull() | e.syncExcluded.equals(false)))
          .write(const IntakeEventsCompanion(syncExcluded: Value(true)));

  /// 上傳成功:把這些版本標成已同步。上傳途中又被修改的紀錄(updatedAtMs 已經不同)
  /// 不會被標記,下一輪再上傳新的版本。回傳實際標記的筆數。
  ///
  /// 不會 [notifyListeners]:同步狀態不影響畫面上的紀錄,也避免「同步 → 通知 → 再同步」。
  Future<int> markSynced(Iterable<SyncedVersion> versions) async {
    final now = _nowMs;
    var marked = 0;
    await _db.transaction(() async {
      for (final v in versions) {
        marked += await (_db.update(_db.intakeEvents)
              ..where((e) =>
                  e.id.equals(v.id) & e.updatedAtMs.equals(v.updatedAtMs)))
            .write(IntakeEventsCompanion(
          syncedAtMs: Value(now),
          syncError: const Value(null),
        ));
      }
    });
    return marked;
  }

  /// 照護系統拒收這一版紀錄(例如 INVALID_EVENT):記下原因、移出上傳佇列,
  /// 不擋住後面的紀錄。紀錄之後再被修改會重新排入。
  Future<void> markSyncRejected(String id, int updatedAtMs, String error) async {
    await (_db.update(_db.intakeEvents)
          ..where((e) => e.id.equals(id) & e.updatedAtMs.equals(updatedAtMs)))
        .write(IntakeEventsCompanion(syncError: Value(error)));
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
        // 匯入的資料一律歸到本機的飲用者;別台裝置的同步狀態不沿用。
        // 新加入的紀錄不上傳照護系統(不知道是誰的,也可能早就由另一台裝置上傳過);
        // 本機已有的紀錄維持原本的設定。
        final row = e.copyWith(
          drinkerId: defaultDrinkerId,
          syncedAtMs: const Value(null),
          syncError: const Value(null),
          syncExcluded: Value(existing == null ? true : existing.syncExcluded),
        );
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
          // 同一筆韌體事件(同水杯、同去重鍵)已經在本機 → 略過。
          if (row.cupId != null &&
              row.fwKey != null &&
              await (_db.select(_db.intakeEvents)
                        ..where((x) =>
                            x.cupId.equals(row.cupId!) &
                            x.fwKey.equals(row.fwKey!)))
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
