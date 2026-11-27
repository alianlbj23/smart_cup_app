import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// 飲水事件種類。
enum IntakeKind {
  /// 喝水:計入飲水量。
  drink,

  /// 加水:水位上升,不計入飲水量。
  refill,

  /// 倒掉:水位下降但沒有喝的動作,不計入飲水量。
  discard,
}

/// 事件來源。
enum IntakeSource {
  /// App 連線時由水位與姿態自動偵測。
  appAuto,

  /// 韌體偵測並送來的事件(DRINK_EVENT 0x07,韌體 0.3.0 起;斷線時存 flash、連上補傳)。
  firmware,

  /// 使用者手動輸入。
  manual,
}

/// 事件狀態。
enum IntakeStatus {
  /// 正常,喝水事件會計入飲水量。
  ok,

  /// 自動判斷不確定(例如水位下降但沒偵測到喝的姿態),等使用者確認;不計入。
  uncertain,

  /// 已刪除(軟刪除,保留紀錄,刪除才能同步到照護系統);不計入。
  deleted,
}

/// 水杯。
@DataClassName('CupRow')
class Cups extends Table {
  /// BLE remoteId。
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// 滿杯容量(mL),水位比例 × 容量 = 水量。
  ///
  /// 這裡的 SQL 預設值(350)已經沒有在用:新水杯的容量由
  /// `IntakeRepository.ensureCup` 明確寫入 `IntakeRepository.defaultCupCapacityMl`。
  /// 保留原值是為了不改動已安裝裝置上的資料表定義。
  IntColumn get capacityMl => integer().withDefault(const Constant(350))();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  /// 水杯自己回報的 BLE 位址(Device Status,韌體 0.4.0 起),例如 `58:E6:C5:12:E0:CE`。
  /// 連結照護系統時當作 `cup_hardware_id`;舊韌體為 null,改用 [id]。
  TextColumn get bleAddress => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 飲用者。這台裝置只有一位(預設建立),保留此表方便日後擴充多人。
@DataClassName('DrinkerRow')
class Drinkers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// 每日目標(mL)。未連結照護系統時由使用者在「設定」修改;
  /// 已連結且照護系統有設定目標時,會被改成照護系統的值。
  IntColumn get dailyGoalMl => integer().withDefault(const Constant(1500))();
  IntColumn get updatedAtMs => integer()();

  /// 已連結照護系統:每日目標以 Server 為準([serverGoalMl]),不能在 App 修改。
  BoolColumn get goalFromServer =>
      boolean().withDefault(const Constant(false))();

  /// 照護系統設定的每日目標(mL);[goalFromServer] 為 true 而此欄為 null
  /// 代表「照護系統尚未設定目標」,不可以套用任何預設值。
  IntColumn get serverGoalMl => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 每一次喝水/加水/倒掉。日、週、月累積都由此表即時計算,不另存統計表。
@DataClassName('IntakeEvent')
@TableIndex(name: 'idx_intake_day', columns: {#drinkerId, #localDay})
@TableIndex(name: 'idx_intake_time', columns: {#drinkerId, #startedAtMs})
// 韌體事件去重:同一個水杯、同一個去重鍵只能有一筆。fwKey 為 null(非韌體事件)時
// SQLite 不視為重複。
@TableIndex(name: 'idx_intake_fw', columns: {#cupId, #fwKey}, unique: true)
class IntakeEvents extends Table {
  /// UUID v4;上傳照護系統時就是 `client_event_id`。
  TextColumn get id => text()();
  TextColumn get drinkerId => text().references(Drinkers, #id)();

  /// 手動輸入可為 null。
  TextColumn get cupId => text().nullable()();
  TextColumn get kind => textEnum<IntakeKind>()();
  IntColumn get ml => integer()();

  /// UTC 毫秒。
  IntColumn get startedAtMs => integer()();
  IntColumn get endedAtMs => integer().nullable()();

  /// 事件發生當下的時區偏移(分鐘),換時區後「哪一天」不會跑掉。
  IntColumn get tzOffsetMin => integer()();

  /// 事件發生當地的日期 yyyy-MM-dd(由 startedAtMs + tzOffsetMin 算出),
  /// 日/週/月統計直接以此分組。
  TextColumn get localDay => text()();

  /// 拿起前、放下後的水量(mL),除錯與日後重算用。
  IntColumn get beforeMl => integer().nullable()();
  IntColumn get afterMl => integer().nullable()();
  TextColumn get source => textEnum<IntakeSource>()();
  TextColumn get status =>
      textEnum<IntakeStatus>().withDefault(Constant(IntakeStatus.ok.name))();
  IntColumn get updatedAtMs => integer()();

  // ---- schema 2 新增(都可為 null,舊的備份檔沒有這些欄位也能匯入)----

  /// 事件當下的水杯容量(mL),換算 mL 用的那個值。
  IntColumn get capacityMl => integer().nullable()();

  /// 事件前/後的水位(%,0–100)。韌體事件是韌體送來的 A/B。
  RealColumn get levelBeforePct => real().nullable()();
  RealColumn get levelAfterPct => real().nullable()();

  /// 時間為估計:韌體送來的事件沒有可信的時間(`time_unknown`),
  /// [startedAtMs] 是 App 收到的時間。null 視為 false。
  BoolColumn get timeEstimated => boolean().nullable()();

  /// 韌體旗標:過程中出現過「飲用中」姿態、過程超過 10 分鐘。非韌體事件為 null。
  BoolColumn get sawDrinking => boolean().nullable()();
  BoolColumn get tooLong => boolean().nullable()();

  /// 韌體事件的 seq(0..2047)。
  IntColumn get fwSeq => integer().nullable()();

  /// 韌體事件的去重鍵(seq + 時間戳 + A/B),同一筆重送時相同。
  TextColumn get fwKey => text().nullable()();

  /// 上傳照護系統成功的時間(UTC 毫秒);null = 還沒同步(新增或修改過)。
  IntColumn get syncedAtMs => integer().nullable()();

  /// 照護系統拒收這一版紀錄的原因(例如 INVALID_EVENT);有值 = 不再重送,
  /// 直到紀錄再被修改。
  TextColumn get syncError => text().nullable()();

  /// true = 這筆紀錄不上傳照護系統,之後再修改也一樣。連結到新的住民時,本機原有的
  /// 紀錄都會標上(Server 會把收到的事件算在 token 所屬的住民身上,連結之前的紀錄
  /// 不能算到他頭上);從備份檔匯入的紀錄也是。
  BoolColumn get syncExcluded => boolean().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        // 同一個水杯同一時間只有一筆(匯入備份時去重)。cupId 為 null(手動)時
        // SQLite 不視為重複。韌體事件的去重另外用 idx_intake_fw。
        {cupId, startedAtMs},
      ];
}

@DriftDatabase(tables: [Cups, Drinkers, IntakeEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  /// 1:單機版。
  /// 2:韌體事件(去重鍵、旗標、水位、容量)、照護系統同步狀態、Server 的每日目標、
  ///    水杯的 BLE 位址。
  /// 3:只改資料、不改資料表。容量還是舊預設值 350 mL 的水杯改成 276 mL
  ///    (目前使用的水杯:直徑 80 mm、高 55 mm)。過去的紀錄不重算。
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(cups, cups.bleAddress);
            await m.addColumn(drinkers, drinkers.goalFromServer);
            await m.addColumn(drinkers, drinkers.serverGoalMl);
            await m.addColumn(intakeEvents, intakeEvents.capacityMl);
            await m.addColumn(intakeEvents, intakeEvents.levelBeforePct);
            await m.addColumn(intakeEvents, intakeEvents.levelAfterPct);
            await m.addColumn(intakeEvents, intakeEvents.timeEstimated);
            await m.addColumn(intakeEvents, intakeEvents.sawDrinking);
            await m.addColumn(intakeEvents, intakeEvents.tooLong);
            await m.addColumn(intakeEvents, intakeEvents.fwSeq);
            await m.addColumn(intakeEvents, intakeEvents.fwKey);
            await m.addColumn(intakeEvents, intakeEvents.syncedAtMs);
            await m.addColumn(intakeEvents, intakeEvents.syncError);
            await m.addColumn(intakeEvents, intakeEvents.syncExcluded);
            await m.createIndex(idxIntakeFw);
          }
          if (from < 3) {
            // 數字寫死:這一步是當時的決定,不跟著之後的預設值變動。分不出「沒改過」
            // 和「刻意填 350」,一律改掉;修改時間一併更新,匯入舊備份檔才不會又改回 350。
            await customStatement(
              'UPDATE cups SET capacity_ml = 276, updated_at_ms = ? '
              'WHERE capacity_ml = 350',
              [DateTime.now().millisecondsSinceEpoch],
            );
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// 各平台的預設資料庫:手機/桌面為 App 資料夾內的 smart_cup.sqlite,
  /// Web 存在瀏覽器(OPFS/IndexedDB),需要 web/sqlite3.wasm 與 web/drift_worker.js。
  static QueryExecutor _openDefault() => driftDatabase(
        name: 'smart_cup',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );
}
