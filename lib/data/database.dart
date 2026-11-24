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

  /// 韌體偵測並補傳(第二階段)。
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

  /// 已刪除(軟刪除,保留紀錄方便日後同步);不計入。
  deleted,
}

/// 水杯。
@DataClassName('CupRow')
class Cups extends Table {
  /// BLE remoteId。
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// 滿杯容量(mL),水位比例 × 容量 = 水量。
  IntColumn get capacityMl => integer().withDefault(const Constant(350))();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 飲用者。單機版只有一位(預設建立),保留此表方便日後擴充多人。
@DataClassName('DrinkerRow')
class Drinkers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get dailyGoalMl => integer().withDefault(const Constant(1500))();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 每一次喝水/加水/倒掉。日、週、月累積都由此表即時計算,不另存統計表。
@DataClassName('IntakeEvent')
@TableIndex(name: 'idx_intake_day', columns: {#drinkerId, #localDay})
@TableIndex(name: 'idx_intake_time', columns: {#drinkerId, #startedAtMs})
class IntakeEvents extends Table {
  /// UUID v4,日後同步雲端不會撞號。
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

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        // 韌體補傳同一事件時去除重複。cupId 為 null(手動)時 SQLite 不視為重複。
        {cupId, startedAtMs},
      ];
}

@DriftDatabase(tables: [Cups, Drinkers, IntakeEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
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
