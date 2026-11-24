import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart'
    show ShareParams, ShareResultStatus, SharePlus;

import '../data/intake_repository.dart';

// 匯出/匯入:沒有伺服器,這是使用者換手機、誤刪 App 時唯一的備份方式。
//
// 核心(JSON/CSV 的產生與解析、合併匯入)是純函式,方便單元測試;
// 平台相關的檔案存取放在 [BackupFileIO],UI 測試可以換成假的。

/// 備份檔格式識別字。
const backupFormatId = 'smart_cup_backup';

/// 目前的備份檔版本。日後格式改變時遞增,並在 [parseBackupJson] 處理舊版。
const backupFormatVersion = 1;

/// 解析後的備份檔內容。
class BackupData {
  const BackupData({
    required this.exportedAt,
    required this.dailyGoalMl,
    required this.cups,
    required this.events,
  });

  /// 匯出時間;舊檔或手動編輯過缺少時為 null。
  final DateTime? exportedAt;
  final int dailyGoalMl;
  final List<CupRow> cups;

  /// 含已刪除的事件,匯入時刪除狀態也會一併同步。
  final List<IntakeEvent> events;
}

/// [importBackup] 的結果。
class ImportResult {
  const ImportResult({
    required this.eventsInFile,
    required this.eventsChanged,
    required this.cupsChanged,
    required this.goalChanged,
    required this.dailyGoalMl,
  });

  /// 備份檔裡的事件總數(含已刪除)。
  final int eventsInFile;

  /// 實際新增或更新的事件數。
  final int eventsChanged;

  /// 實際新增或更新的水杯數。
  final int cupsChanged;

  /// 每日目標是否因匯入而改變。
  final bool goalChanged;

  /// 匯入後的每日目標(mL)。
  final int dailyGoalMl;

  /// 是否完全沒有變更(例如同一個檔案匯入第二次)。
  bool get nothingChanged =>
      eventsChanged == 0 && cupsChanged == 0 && !goalChanged;
}

/// 產生備份檔 JSON。[events] 應包含已刪除的事件,刪除才會同步到另一台裝置。
String buildBackupJson({
  required int dailyGoalMl,
  required List<CupRow> cups,
  required List<IntakeEvent> events,
  required DateTime exportedAt,
}) {
  return jsonEncode({
    'format': backupFormatId,
    'version': backupFormatVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'dailyGoalMl': dailyGoalMl,
    'cups': [for (final c in cups) c.toJson()],
    'events': [for (final e in events) e.toJson()],
  });
}

/// 解析備份檔。格式不符時丟出 [FormatException],訊息可直接顯示給使用者。
BackupData parseBackupJson(String json) {
  // 有些編輯器存檔會加上 BOM,先去掉。
  final text = json.startsWith('﻿') ? json.substring(1) : json;
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const FormatException('這不是有效的備份檔(檔案內容無法解讀)');
  }
  if (root is! Map<String, dynamic> || root['format'] != backupFormatId) {
    throw const FormatException('這不是智慧水杯的備份檔');
  }
  final version = root['version'];
  if (version is! int) {
    throw const FormatException('備份檔缺少版本資訊,無法匯入');
  }
  if (version > backupFormatVersion) {
    throw const FormatException('這個備份檔來自較新版本的 App,請先更新 App 再匯入');
  }
  if (version < 1) {
    throw const FormatException('不支援的備份檔版本');
  }
  final goal = root['dailyGoalMl'];
  if (goal is! int || goal <= 0) {
    throw const FormatException('備份檔的每日目標有誤');
  }
  final cupsJson = root['cups'];
  final eventsJson = root['events'];
  if (cupsJson is! List || eventsJson is! List) {
    throw const FormatException('備份檔缺少水杯或紀錄資料');
  }
  try {
    return BackupData(
      exportedAt: switch (root['exportedAt']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
      dailyGoalMl: goal,
      cups: [
        for (final c in cupsJson) CupRow.fromJson(c as Map<String, dynamic>),
      ],
      events: [
        for (final e in eventsJson)
          IntakeEvent.fromJson(e as Map<String, dynamic>),
      ],
    );
  } on Object {
    // 欄位缺漏、型別不對、未知的種類/狀態等。
    throw const FormatException('備份檔內容有誤,可能已損壞或被修改過');
  }
}

/// 從 [repo] 匯出完整備份檔(含已刪除的事件)。
Future<String> exportBackupJson(IntakeRepository repo, {DateTime? now}) async {
  return buildBackupJson(
    dailyGoalMl: repo.dailyGoalMl,
    cups: await repo.cups(),
    events: await repo.allEvents(),
    exportedAt: now ?? DateTime.now(),
  );
}

/// 匯入備份檔並與本機資料合併:依 id 比對,同一筆以 updatedAtMs 較新者為準,
/// 不會刪除本機有、備份檔沒有的資料(備份檔裡標記為已刪除的事件則會同步為已刪除)。
///
/// 每日目標一律套用備份檔的設定:匯入是使用者明確的還原動作,而且新裝置的預設目標
/// 是安裝當下建立的,無法和備份檔比較新舊。
///
/// 先完整解析再寫入,格式有誤時丟出 [FormatException] 且不會改動任何資料。
Future<ImportResult> importBackup(IntakeRepository repo, String json) async {
  final data = parseBackupJson(json);

  var cupsChanged = 0;
  for (final c in data.cups) {
    final existing = await repo.cup(c.id);
    if (existing == null || existing.updatedAtMs < c.updatedAtMs) cupsChanged++;
  }
  if (cupsChanged > 0) await repo.importCups(data.cups);

  final eventsChanged = await repo.importEvents(data.events);

  final goalChanged = repo.dailyGoalMl != data.dailyGoalMl;
  if (goalChanged) await repo.setDailyGoal(data.dailyGoalMl);

  return ImportResult(
    eventsInFile: data.events.length,
    eventsChanged: eventsChanged,
    cupsChanged: cupsChanged,
    goalChanged: goalChanged,
    dailyGoalMl: data.dailyGoalMl,
  );
}

// ------------------------------------------------------------------ CSV

const _csvHeader = ['日期', '時間', '種類', '水量(mL)', '來源', '狀態'];

String _kindLabel(IntakeKind k) => switch (k) {
  IntakeKind.drink => '喝水',
  IntakeKind.refill => '加水',
  IntakeKind.discard => '倒掉',
};

String _sourceLabel(IntakeSource s) => switch (s) {
  IntakeSource.appAuto => '自動偵測',
  IntakeSource.firmware => '水杯補傳',
  IntakeSource.manual => '手動輸入',
};

String _statusLabel(IntakeStatus s) => switch (s) {
  IntakeStatus.ok => '正常',
  IntakeStatus.uncertain => '待確認',
  IntakeStatus.deleted => '已刪除',
};

String _two(int n) => n.toString().padLeft(2, '0');

/// CSV 欄位跳脫(RFC 4180):含逗號、雙引號或換行時用雙引號包起來,內部雙引號重複一次。
String csvEscape(String field) {
  if (field.contains(RegExp(r'[",\r\n]'))) {
    return '"${field.replaceAll('"', '""')}"';
  }
  return field;
}

/// 產生飲水紀錄 CSV,可直接用 Excel / Google 試算表開啟。
///
/// - 開頭加 UTF-8 BOM,Excel 才不會把中文顯示成亂碼。
/// - 不含已刪除的事件。
/// - 日期與時間是事件發生當地的時間(依事件記錄的時區偏移),和 App 裡的「哪一天」一致。
/// - 依時間排序,換行使用 CRLF。
String buildCsv(List<IntakeEvent> events) {
  final rows = events.where((e) => e.status != IntakeStatus.deleted).toList()
    ..sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
  final b = StringBuffer('﻿')
    ..write(_csvHeader.map(csvEscape).join(','))
    ..write('\r\n');
  for (final e in rows) {
    final t = DateTime.fromMillisecondsSinceEpoch(
      e.startedAtMs,
      isUtc: true,
    ).add(Duration(minutes: e.tzOffsetMin));
    final fields = [
      '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}',
      '${_two(t.hour)}:${_two(t.minute)}',
      _kindLabel(e.kind),
      '${e.ml}',
      _sourceLabel(e.source),
      _statusLabel(e.status),
    ];
    b
      ..write(fields.map(csvEscape).join(','))
      ..write('\r\n');
  }
  return b.toString();
}

// ------------------------------------------------------------------ 檔名

String _dateStamp(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-${_two(now.month)}-${_two(now.day)}';

/// 備份檔預設檔名,例如 smart_cup_backup_2026-11-23.json。
String backupFileName(DateTime now) =>
    'smart_cup_backup_${_dateStamp(now)}.json';

/// CSV 預設檔名,例如 smart_cup_紀錄_2026-11-23.csv。
String csvFileName(DateTime now) => 'smart_cup_紀錄_${_dateStamp(now)}.csv';

// ------------------------------------------------------------------ 檔案存取

/// 平台檔案存取。UI 透過這個介面存取檔案,測試時可以換成假的實作。
abstract class BackupFileIO {
  /// 讓使用者把檔案存起來:桌面跳出「另存新檔」、手機開啟分享選單、Web 直接下載。
  ///
  /// 回傳可以顯示給使用者的位置(桌面為完整路徑,其他平台為檔名);
  /// 使用者取消時回傳 null。[shareOrigin] 是 iPad / macOS 分享選單的錨點位置。
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    Rect? shareOrigin,
  });

  /// 讓使用者選一個備份檔並讀出內容(UTF-8);使用者取消時回傳 null。
  Future<String?> pickBackupFile();
}

/// 各平台的實際檔案存取。不 import dart:io,Web 也能編譯。
class PlatformBackupFileIO implements BackupFileIO {
  const PlatformBackupFileIO();

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static XTypeGroup _typeGroupFor(String fileName, String mimeType) {
    final isCsv = fileName.endsWith('.csv');
    return XTypeGroup(
      label: isCsv ? 'CSV' : '備份檔',
      extensions: [isCsv ? 'csv' : 'json'],
      mimeTypes: [mimeType],
      uniformTypeIdentifiers: [
        isCsv ? 'public.comma-separated-values-text' : 'public.json',
      ],
    );
  }

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    Rect? shareOrigin,
  }) async {
    if (kIsWeb) {
      // Web:file_selector 的做法,建立 Blob 後觸發瀏覽器下載(路徑會被忽略)。
      await XFile.fromData(
        bytes,
        name: fileName,
        mimeType: mimeType,
      ).saveTo('');
      return fileName;
    }
    if (_isDesktop) {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [_typeGroupFor(fileName, mimeType)],
      );
      if (location == null) return null;
      await XFile.fromData(bytes, mimeType: mimeType).saveTo(location.path);
      return location.path;
    }
    // Android / iOS:先寫到暫存資料夾,再開分享選單讓使用者存到雲端硬碟、檔案 App 或傳給自己。
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    await XFile.fromData(bytes, mimeType: mimeType).saveTo(path);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType, name: fileName)],
        title: fileName,
        sharePositionOrigin: shareOrigin,
      ),
    );
    if (result.status == ShareResultStatus.dismissed) return null;
    return fileName;
  }

  @override
  Future<String?> pickBackupFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: '備份檔',
          extensions: const ['json'],
          // 從雲端硬碟下載的 JSON 在部分 Android 裝置會被標成 octet-stream,一併允許。
          mimeTypes: [
            'application/json',
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              'application/octet-stream',
          ],
          uniformTypeIdentifiers: const ['public.json'],
        ),
      ],
    );
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }
}
