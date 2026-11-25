import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'care_api.dart';

/// 已連結照護系統的資料(核准後存在本機)。
class CareLink {
  const CareLink({
    required this.token,
    required this.linkId,
    required this.resident,
    required this.dailyGoalMl,
    required this.goalEffectiveFrom,
    required this.linkedAtMs,
    required this.serverUrl,
    required this.cupLocalId,
    required this.cupHardwareId,
    required this.cupName,
  });

  /// `Authorization: Bearer` 用的 token。不可印到 log、不可顯示。
  final String token;
  final int linkId;
  final CareResident resident;

  /// Server 設定的每日目標;null = 照護系統尚未設定目標。
  final int? dailyGoalMl;
  final String? goalEffectiveFrom;

  /// 核准當下的手機時間(UTC 毫秒)。這之後新增或修改的紀錄才上傳。
  final int linkedAtMs;

  /// 連結時用的伺服器位址。
  final String serverUrl;

  /// 連結的水杯在本機的 id(`cups.id`,平台的 remoteId)。
  final String cupLocalId;

  /// 送給 Server 的 `cup_hardware_id`。
  final String cupHardwareId;
  final String cupName;

  CareGoal get goal =>
      CareGoal(dailyGoalMl: dailyGoalMl, effectiveFrom: goalEffectiveFrom);

  CareLink withGoal(CareGoal goal) => _copy(
      dailyGoalMl: goal.dailyGoalMl, goalEffectiveFrom: goal.effectiveFrom);

  CareLink withResident(CareResident resident) => _copy(
      resident: resident,
      dailyGoalMl: dailyGoalMl,
      goalEffectiveFrom: goalEffectiveFrom);

  CareLink _copy({
    CareResident? resident,
    required int? dailyGoalMl,
    required String? goalEffectiveFrom,
  }) =>
      CareLink(
        token: token,
        linkId: linkId,
        resident: resident ?? this.resident,
        dailyGoalMl: dailyGoalMl,
        goalEffectiveFrom: goalEffectiveFrom,
        linkedAtMs: linkedAtMs,
        serverUrl: serverUrl,
        cupLocalId: cupLocalId,
        cupHardwareId: cupHardwareId,
        cupName: cupName,
      );

  Map<String, Object?> toJson() => {
        'token': token,
        'linkId': linkId,
        'resident': resident.toJson(),
        'dailyGoalMl': dailyGoalMl,
        'goalEffectiveFrom': goalEffectiveFrom,
        'linkedAtMs': linkedAtMs,
        'serverUrl': serverUrl,
        'cupLocalId': cupLocalId,
        'cupHardwareId': cupHardwareId,
        'cupName': cupName,
      };

  /// 解析本機儲存的 JSON;欄位缺漏或型別不對時丟出 [FormatException]。
  factory CareLink.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('連結資料不是物件');
    final token = json['token'], linkId = json['linkId'];
    final goal = json['dailyGoalMl'], from = json['goalEffectiveFrom'];
    final linkedAt = json['linkedAtMs'], server = json['serverUrl'];
    final cupLocalId = json['cupLocalId'], cupHw = json['cupHardwareId'];
    final cupName = json['cupName'];
    if (token is! String ||
        token.isEmpty ||
        linkId is! int ||
        (goal != null && (goal is! int || goal <= 0)) ||
        (from != null && from is! String) ||
        linkedAt is! int ||
        server is! String ||
        cupLocalId is! String ||
        cupHw is! String ||
        cupName is! String) {
      throw const FormatException('連結資料的欄位不符');
    }
    return CareLink(
      token: token,
      linkId: linkId,
      resident: CareResident.fromJson(json['resident']),
      dailyGoalMl: goal as int?,
      goalEffectiveFrom: from as String?,
      linkedAtMs: linkedAt,
      serverUrl: server,
      cupLocalId: cupLocalId,
      cupHardwareId: cupHw,
      cupName: cupName,
    );
  }

  /// 不含 token。
  @override
  String toString() =>
      'CareLink(#$linkId ${resident.display}, 水杯 $cupName, $serverUrl)';
}

/// 水杯最後一次被 App 看到的時間與韌體版本(狀態回報用)。
typedef CupSeen = ({int? lastSeenAtMs, String? firmware});

/// 照護系統連結的本機儲存(shared_preferences)。
///
/// **限制**:這個 App 沒有安全儲存套件(Keychain / Keystore),token 只能存在
/// shared_preferences,沒有額外加密;手機被 root / 備份檔外流時可能被讀到。
/// token 只能用來上傳這位住民的飲水紀錄與讀取目標,照護人員可以在網頁端解除綁定讓它失效。
class CareLinkStore {
  CareLinkStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _keyServerUrl = 'care_server_url';
  static const _keyInstallId = 'care_install_id';
  static const _keyLink = 'care_link_v1';
  static const _keyNotice = 'care_notice';
  static const _keySeenAt = 'care_cup_last_seen_at_ms';
  static const _keyFirmware = 'care_cup_firmware';
  static const _keyLastResident = 'care_last_resident';

  final Uuid _uuid;

  /// 伺服器位址;沒設定過就是 [defaultCareServerUrl]。
  Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyServerUrl);
    return saved == null || saved.isEmpty ? defaultCareServerUrl : saved;
  }

  Future<void> saveServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, url);
  }

  /// 這個 App 安裝的識別碼:第一次呼叫時產生 UUID v4 並存起來,之後都回傳同一個。
  Future<String> installId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyInstallId);
    if (saved != null && saved.isNotEmpty) return saved;
    final id = _uuid.v4();
    await prefs.setString(_keyInstallId, id);
    return id;
  }

  /// 已儲存的連結;沒有、或資料損毀時為 null。
  Future<CareLink?> loadLink() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLink);
    if (raw == null) return null;
    try {
      return CareLink.fromJson(jsonDecode(raw));
    } on FormatException catch (e) {
      // 不印內容(裡面有 token)。
      debugPrint('[CareLinkStore] 儲存的連結資料無法讀取,當成尚未連結:${e.message}');
      return null;
    }
  }

  Future<void> saveLink(CareLink link) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLink, jsonEncode(link.toJson()));
  }

  /// 清掉 token 與連結資料(install_id、伺服器位址保留)。
  Future<void> clearLink() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLink);
    await prefs.remove(_keySeenAt);
    await prefs.remove(_keyFirmware);
  }

  /// 上一次連結的住民(`伺服器位址#住民 id`),解除連結後仍保留。用來判斷這次是不是
  /// 連結到同一位住民:不同的話,本機原有的紀錄不可以上傳。
  Future<String?> loadLastResident() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastResident);
  }

  Future<void> saveLastResident(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastResident, key);
  }

  /// 要顯示給使用者的提示(例如連結失效的原因),重開 App 後還在。
  Future<String?> loadNotice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNotice);
  }

  Future<void> saveNotice(String? notice) async {
    final prefs = await SharedPreferences.getInstance();
    if (notice == null) {
      await prefs.remove(_keyNotice);
    } else {
      await prefs.setString(_keyNotice, notice);
    }
  }

  Future<CupSeen> loadCupSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      lastSeenAtMs: prefs.getInt(_keySeenAt),
      firmware: prefs.getString(_keyFirmware),
    );
  }

  Future<void> saveCupSeen({int? lastSeenAtMs, String? firmware}) async {
    final prefs = await SharedPreferences.getInstance();
    if (lastSeenAtMs != null) await prefs.setInt(_keySeenAt, lastSeenAtMs);
    if (firmware != null) await prefs.setString(_keyFirmware, firmware);
  }
}
