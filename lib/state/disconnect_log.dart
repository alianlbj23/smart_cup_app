import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cup_connection_manager.dart';

/// 一筆意外斷線紀錄。
class DisconnectRecord {
  const DisconnectRecord({
    required this.at,
    required this.deviceName,
    required this.code,
    required this.description,
    required this.inBackground,
    required this.wasDozing,
  });

  final DateTime at;
  final String? deviceName;

  /// 平台斷線代碼(Android:8 逾時、19 水杯斷的、22 手機斷的);未知為 null。
  final int? code;
  final String? description;

  /// 斷線當下 App 是否在背景(螢幕關掉或切到別的 App)。
  final bool inBackground;

  /// 斷線當下水杯是否在休眠。
  final bool wasDozing;

  /// 給人看的原因(Android 常見代碼翻成中文)。
  String get reasonText {
    switch (code) {
      case null:
        return '原因不明';
      case 8:
        return '連線逾時:手機和水杯有一邊收不到對方(8)';
      case 19:
        return '水杯端斷線(19)';
      case 22:
        return '手機端斷線(22)';
      case 133:
        return 'Android 藍牙錯誤(133)';
      default:
        return '${description ?? '未知'}($code)';
    }
  }

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'device': deviceName,
    'code': code,
    'desc': description,
    'bg': inBackground,
    'doze': wasDozing,
  };

  /// 格式不對回傳 null(存在手機上的資料也要驗證)。
  static DisconnectRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'], device = json['device'], code = json['code'];
    final desc = json['desc'], bg = json['bg'], doze = json['doze'];
    if (at is! String || bg is! bool || doze is! bool) return null;
    if (device != null && device is! String) return null;
    if (code != null && code is! int) return null;
    if (desc != null && desc is! String) return null;
    final time = DateTime.tryParse(at);
    if (time == null) return null;
    return DisconnectRecord(
      at: time,
      deviceName: device as String?,
      code: code as int?,
      description: desc as String?,
      inBackground: bg,
      wasDozing: doze,
    );
  }
}

/// App 是否在背景(螢幕關掉、切到別的 App)。
///
/// 只有 paused、detached 才算:inactive 是下拉通知列或系統對話框蓋在上面,App 還在
/// 畫面上;null 是第一個 frame 之前還不知道,這時 App 剛被使用者打開。
bool isAppInBackground(AppLifecycleState? state) =>
    state == AppLifecycleState.paused || state == AppLifecycleState.detached;

/// 斷線紀錄存放的地方(一整段 JSON 文字)。
abstract interface class DisconnectLogStorage {
  /// 沒有存過回傳 null。
  Future<String?> read();
  Future<void> write(String data);
  Future<void> clear();
}

/// 存在 SharedPreferences;每個操作最多等 5 秒。
class PrefsDisconnectLogStorage implements DisconnectLogStorage {
  const PrefsDisconnectLogStorage();

  static const _timeout = Duration(seconds: 5);

  Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance().timeout(_timeout);

  @override
  Future<String?> read() async =>
      (await _prefs).getString(DisconnectLog.prefsKey);

  @override
  Future<void> write(String data) async {
    if (!await (await _prefs)
        .setString(DisconnectLog.prefsKey, data)
        .timeout(_timeout)) {
      throw StateError('SharedPreferences 沒有寫入成功');
    }
  }

  @override
  Future<void> clear() async {
    await (await _prefs).remove(DisconnectLog.prefsKey).timeout(_timeout);
  }
}

/// 記下每次意外斷線(原因、當時 App 在前景或背景、水杯是否休眠),
/// 存在手機上,設定頁可以看,用來判斷斷線是手機、App 還是水杯那邊造成的。
class DisconnectLog extends ChangeNotifier {
  DisconnectLog({
    required this.manager,
    required this.isInBackground,
    this.storage = const PrefsDisconnectLogStorage(),
  });

  final CupConnectionManager manager;

  /// 回傳 App 目前是否在背景。
  final bool Function() isInBackground;

  final DisconnectLogStorage storage;

  static const prefsKey = 'disconnect_log_v1';
  static const maxRecords = 30;

  final List<DisconnectRecord> _records = [];
  StreamSubscription<CupDisconnect>? _sub;

  /// 存的舊紀錄已經併進 [_records]。還沒併之前不能寫入,否則會蓋掉舊紀錄。
  bool _storedMerged = false;

  /// 讀取、寫入、清除依序執行。每一步都自己處理錯誤,這條鏈不會中斷。
  Future<void> _pending = Future.value();

  /// 最新的在前面。
  List<DisconnectRecord> get records => List.unmodifiable(_records);

  /// 讀出存在手機上的紀錄。讀取失敗時丟出例外(已經在記憶體裡的紀錄不受影響)。
  Future<void> load() {
    final done = _pending.then((_) => _mergeStored());
    _pending = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  /// 把存的舊紀錄接在這次執行新增的紀錄後面;只做一次。
  Future<void> _mergeStored() async {
    if (_storedMerged) return;
    final raw = await storage.read();
    final stored = <DisconnectRecord>[];
    if (raw != null) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final item in list) {
            final r = DisconnectRecord.fromJson(item);
            if (r == null) {
              debugPrint('[DisconnectLog] 略過格式不對的紀錄:$item');
            } else {
              stored.add(r);
            }
          }
        } else {
          debugPrint('[DisconnectLog] 紀錄格式不對,重新開始');
        }
      } on FormatException catch (e) {
        debugPrint('[DisconnectLog] 紀錄壞掉,重新開始:$e');
      }
    }
    _records.addAll(stored);
    _trim();
    _storedMerged = true;
    notifyListeners();
  }

  void _trim() {
    if (_records.length > maxRecords) {
      _records.removeRange(maxRecords, _records.length);
    }
  }

  void start() {
    _sub ??= manager.unexpectedDisconnects.listen(_onDisconnect);
  }

  void _onDisconnect(CupDisconnect d) {
    _records.insert(
      0,
      DisconnectRecord(
        at: d.at,
        deviceName: d.deviceName,
        code: d.reason?.code,
        description: d.reason?.description,
        inBackground: isInBackground(),
        wasDozing: d.wasDozing,
      ),
    );
    _trim();
    notifyListeners();
    _pending = _pending.then((_) => _save());
  }

  Future<void> _save() async {
    try {
      await _mergeStored();
      await storage.write(
        jsonEncode(_records.map((r) => r.toJson()).toList()),
      );
    } catch (e, st) {
      debugPrint('[DisconnectLog] 儲存失敗:$e\n$st');
    }
  }

  /// 清除全部紀錄。存檔清不掉時只記 log:畫面上已經清空,下次有新紀錄時會整份覆寫。
  Future<void> clear() {
    _records.clear();
    // 之後不用再併舊紀錄:使用者要的就是全部清掉
    _storedMerged = true;
    notifyListeners();
    return _pending = _pending.then((_) async {
      try {
        await storage.clear();
      } catch (e, st) {
        debugPrint('[DisconnectLog] 清除失敗:$e\n$st');
      }
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
