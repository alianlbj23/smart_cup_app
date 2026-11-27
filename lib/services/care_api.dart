/// 照護系統(Server)的網路層:App ↔ Server 的 HTTPS / JSON(介面合約 §2)。
///
/// 全專案只有這個檔案 import `package:http`。規則:
/// - 所有請求都有 timeout:連線 [CareApi.connectTimeout](10 秒)、整體
///   [CareApi.totalTimeout](20 秒)。
/// - 回應一律是 envelope:`{"success": true, "data": {...}}` 或
///   `{"success": false, "error": {"code", "message", "retryable"}}`。
/// - 任何失敗都丟出 [CareApiException](不吞例外)並記 log;log 只有方法、路徑、
///   錯誤碼,**不印 token、device_code 或回應內容**。
/// - 伺服器回傳的每個欄位都先驗證型別與範圍,不合就當成 `BAD_RESPONSE`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../data/database.dart'
    show IntakeEvent, IntakeKind, IntakeSource, IntakeStatus;

/// 預設的照護系統位址(可在「設定 → 照護系統」修改)。
const defaultCareServerUrl = 'https://foodintakesystem.com';

/// 驗證並整理使用者輸入的伺服器位址:必須是 http / https、有主機名稱,
/// 不能帶帳號密碼、查詢字串或 `#`;結尾的斜線會去掉。
///
/// 不合法時丟出 [FormatException],訊息可以直接顯示給使用者。
Uri parseCareServerUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) throw const FormatException('請輸入伺服器位址');
  if (text.contains(RegExp(r'\s'))) {
    throw const FormatException('伺服器位址不能有空白');
  }
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) {
    throw const FormatException('伺服器位址要以 https:// 或 http:// 開頭');
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw const FormatException('伺服器位址要以 https:// 或 http:// 開頭');
  }
  if (uri.host.isEmpty) throw const FormatException('伺服器位址缺少主機名稱');
  if (uri.userInfo.isNotEmpty) {
    throw const FormatException('伺服器位址不能包含帳號密碼');
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw const FormatException('伺服器位址不能包含 ? 或 #');
  }
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path.isEmpty ? null : path,
  );
}

/// 網路層的所有失敗。
class CareApiException implements Exception {
  const CareApiException({
    required this.code,
    required this.message,
    required this.retryable,
    this.statusCode,
  });

  /// 伺服器的錯誤碼(`TOKEN_EXPIRED`、`DENIED`、`INVALID_EVENT`…),或 App 自己的:
  /// [network](連不上)、[timeout](逾時)、[badResponse](回應不是合約的格式)。
  final String code;

  /// 中文訊息,可以直接顯示。
  final String message;

  /// 之後重送有沒有機會成功(伺服器給的;App 自己的錯誤依狀況決定)。
  final bool retryable;

  /// HTTP 狀態碼;沒有收到回應時為 null。
  final int? statusCode;

  static const network = 'NETWORK';
  static const timeout = 'TIMEOUT';
  static const badResponse = 'BAD_RESPONSE';
  static const tokenExpired = 'TOKEN_EXPIRED';

  /// token 無效或綁定已在網頁端解除:App 要清掉 token,回到「尚未連結」。
  bool get isTokenExpired => code == tokenExpired;

  @override
  String toString() =>
      'CareApiException($code${statusCode == null ? '' : ', HTTP $statusCode'}): $message';
}

/// 住民(只有房號-床號與遮蔽後的姓名)。
class CareResident {
  const CareResident({
    required this.id,
    required this.label,
    required this.nameMasked,
  });

  final int id;

  /// 房號-床號,例如 `101-1`。
  final String label;

  /// 遮蔽後的姓名,例如 `王○明`;沒有姓名時為空字串。
  final String nameMasked;

  /// 畫面上顯示的文字:`101-1 王○明`。
  String get display => nameMasked.isEmpty ? label : '$label $nameMasked';

  Map<String, Object?> toJson() =>
      {'id': id, 'label': label, 'name_masked': nameMasked};

  /// 解析伺服器或本機儲存的 JSON;格式不符時丟出 [FormatException]。
  factory CareResident.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('resident 不是物件');
    final id = json['id'], label = json['label'], name = json['name_masked'];
    if (id is! int || label is! String || name is! String) {
      throw const FormatException('resident 欄位型別不符');
    }
    return CareResident(id: id, label: label, nameMasked: name);
  }
}

/// 每日目標。[dailyGoalMl] 為 null = 照護系統尚未設定目標(不可套用預設值)。
class CareGoal {
  const CareGoal({required this.dailyGoalMl, required this.effectiveFrom});

  final int? dailyGoalMl;

  /// 生效日期 `yyyy-MM-dd`。
  final String? effectiveFrom;

  factory CareGoal._fromData(Map<String, dynamic> data) {
    final goal = data['daily_goal_ml'], from = data['goal_effective_from'];
    if (goal != null && (goal is! int || goal <= 0)) {
      throw const FormatException('daily_goal_ml 必須是正整數或 null');
    }
    if (from != null && from is! String) {
      throw const FormatException('goal_effective_from 必須是字串或 null');
    }
    return CareGoal(dailyGoalMl: goal as int?, effectiveFrom: from as String?);
  }
}

/// `GET /api/machine/health/` 的結果。
class CareHealth {
  const CareHealth({required this.serverTime});

  /// 伺服器時間;沒有回傳時為 null。
  final DateTime? serverTime;
}

/// `POST cup/link/start/` 的結果。
class CareLinkStart {
  const CareLinkStart({
    required this.deviceCode,
    required this.pairingCode,
    required this.expiresIn,
    required this.interval,
  });

  /// 輪詢用的密碼,只留在記憶體,不顯示、不記 log。
  final String deviceCode;

  /// 顯示給使用者、讓照護人員在網頁核對的配對碼。
  final String pairingCode;
  final Duration expiresIn;

  /// 輪詢間隔。
  final Duration interval;
}

/// `POST cup/link/poll/` 的結果。
sealed class CareLinkPoll {
  const CareLinkPoll();
}

/// 還在等照護人員核准。
class CareLinkPending extends CareLinkPoll {
  const CareLinkPending();
}

/// 已核准。伺服器只回這一次,token 要馬上存起來。
class CareLinkApproved extends CareLinkPoll {
  const CareLinkApproved({
    required this.token,
    required this.linkId,
    required this.resident,
    required this.goal,
  });

  final String token;
  final int linkId;
  final CareResident resident;
  final CareGoal goal;
}

/// `GET cup/me/` 的結果。
class CareMe {
  const CareMe({
    required this.linkId,
    required this.resident,
    required this.goal,
    required this.serverTime,
  });

  final int linkId;
  final CareResident resident;
  final CareGoal goal;
  final DateTime? serverTime;
}

/// App 統計頁上某一天的喝水量(`day_totals` 的一筆)。照護系統的網站直接顯示這個數字,
/// 所以 App 和網站不會對不上;逐筆紀錄照常上傳,當明細用。
class CareDayTotal {
  CareDayTotal({
    required this.day,
    required this.totalMl,
    required this.drinkCount,
  }) {
    if (totalMl < 0) {
      throw ArgumentError.value(totalMl, 'totalMl', '不可以是負數');
    }
    if (drinkCount < 0) {
      throw ArgumentError.value(drinkCount, 'drinkCount', '不可以是負數');
    }
  }

  /// 當地日期(只用年月日)。
  final DateTime day;

  /// 那一天的喝水量(mL)。
  final int totalMl;

  /// 計入的喝水筆數。
  final int drinkCount;

  Map<String, Object?> toJson() => {
        'date': '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
        'total_ml': totalMl,
        'drink_count': drinkCount,
      };
}

/// `POST cup/status/` 的內容。
class CareStatusReport {
  const CareStatusReport({
    required this.cupConnected,
    required this.cupLastSeenAt,
    required this.batteryPct,
    required this.firmware,
    required this.pendingEvents,
    required this.levelPct,
    this.dayTotals,
  });

  final bool cupConnected;

  /// App 最後一次看到水杯的時間;不知道時為 null。
  final DateTime? cupLastSeenAt;
  final int? batteryPct;

  /// 韌體版本,例如 `0.4.0`;不知道時為 null。
  final String? firmware;

  /// 還沒上傳的紀錄筆數。
  final int pendingEvents;

  /// 目前水位 %(0–100)。
  final double? levelPct;

  /// App 統計頁上最近幾天的喝水量;null 時不送這個欄位。
  final List<CareDayTotal>? dayTotals;

  Map<String, Object?> toJson() => {
        'cup_connected': cupConnected,
        'cup_last_seen_at': _unixSeconds(cupLastSeenAt),
        'battery_pct': batteryPct,
        'firmware': firmware,
        'pending_events': pendingEvents,
        'level_pct': levelPct,
        if (dayTotals != null)
          'day_totals': [for (final d in dayTotals!) d.toJson()],
      };
}

/// `POST cup/status/` 的結果。
class CareStatusReply {
  const CareStatusReply({
    required this.goal,
    required this.serverTime,
    this.resident,
  });

  final CareGoal goal;
  final DateTime? serverTime;

  /// Server 目前的住民資料(App 一直開著時靠它跟上換房、換床);舊版 Server
  /// 沒有這個欄位時為 null。
  final CareResident? resident;
}

/// `POST cup/events/` 每一筆的結果。
class CareEventResult {
  const CareEventResult({
    required this.clientEventId,
    required this.recordId,
    required this.result,
  });

  final String clientEventId;
  final int? recordId;

  /// `created`、`updated` 或 `unchanged`。
  final String result;
}

int? _unixSeconds(DateTime? t) =>
    t == null ? null : t.millisecondsSinceEpoch ~/ 1000;

/// 一筆 `intake_events` → `cup/events/` 的事件(合約 §2.2)。
/// 時間是 Unix 秒,`updated_at` 是 Unix 毫秒;`client_event_id` 就是事件的 id。
Map<String, Object?> careEventPayload(IntakeEvent e) => {
      'client_event_id': e.id,
      'kind': switch (e.kind) {
        IntakeKind.drink => 'drink',
        IntakeKind.refill => 'refill',
        IntakeKind.discard => 'discard',
      },
      'ml': e.ml,
      'capacity_ml': e.capacityMl,
      'level_before_pct': e.levelBeforePct,
      'level_after_pct': e.levelAfterPct,
      'started_at': e.startedAtMs ~/ 1000,
      'ended_at': e.endedAtMs == null ? null : e.endedAtMs! ~/ 1000,
      'tz_offset_min': e.tzOffsetMin,
      'source': switch (e.source) {
        IntakeSource.firmware => 'firmware',
        IntakeSource.appAuto => 'app_auto',
        IntakeSource.manual => 'manual',
      },
      'status': switch (e.status) {
        IntakeStatus.ok => 'ok',
        IntakeStatus.uncertain => 'uncertain',
        IntakeStatus.deleted => 'deleted',
      },
      'time_estimated': e.timeEstimated ?? false,
      'saw_drinking': e.sawDrinking,
      'too_long': e.tooLong,
      'seq': e.fwSeq,
      'updated_at': e.updatedAtMs,
    };

/// 照護系統 API。[http.Client] 可以注入(測試用 `MockClient`)。
class CareApi {
  CareApi({http.Client? client, this.totalTimeout = defaultTotalTimeout})
      : _client = client ?? _defaultClient();

  /// 建立連線的時間上限。
  static const connectTimeout = Duration(seconds: 10);

  /// 一個請求從送出到讀完回應的時間上限。
  static const defaultTotalTimeout = Duration(seconds: 20);

  /// `cup/events/` 一批最多幾筆。
  static const maxEventsPerRequest = 200;

  static const _health = '/api/machine/health/';
  static const _cup = '/api/machine/cup';

  final http.Client _client;
  final Duration totalTimeout;

  /// 手機/桌面用 dart:io 的 HttpClient,才能設定連線逾時;Web 交給瀏覽器
  /// (沒有連線逾時可設,仍受 [totalTimeout] 限制)。
  static http.Client _defaultClient() => kIsWeb
      ? http.Client()
      : IOClient(HttpClient()..connectionTimeout = connectTimeout);

  void close() => _client.close();

  // ------------------------------------------------------------ 不需要 token

  /// 測試連線。
  Future<CareHealth> health(Uri base) async {
    final data = await _send('GET', base, _health);
    return _parse(
        _health, () => CareHealth(serverTime: _serverTime(data['server_time'])));
  }

  /// 「選我是誰」的名單(依房號、床號排序,順序照伺服器給的)。
  Future<List<CareResident>> residents(Uri base) async {
    const path = '$_cup/residents/';
    final data = await _send('GET', base, path);
    return _parse(path, () {
      final list = data['residents'];
      if (list is! List) throw const FormatException('residents 不是陣列');
      return [for (final r in list) CareResident.fromJson(r)];
    });
  }

  /// 送出綁定請求。
  Future<CareLinkStart> startLink(
    Uri base, {
    required String installId,
    required int residentId,
    required String cupHardwareId,
    required String cupName,
    required String platform,
    required String appVersion,
  }) async {
    const path = '$_cup/link/start/';
    final data = await _send('POST', base, path, body: {
      'install_id': installId,
      'ltc_patient_id': residentId,
      'cup_hardware_id': cupHardwareId,
      'cup_name': cupName,
      'platform': platform,
      'app_version': appVersion,
    });
    return _parse(path, () {
      final deviceCode = data['device_code'], pairing = data['pairing_code'];
      final expires = data['expires_in'], interval = data['interval'];
      if (deviceCode is! String || deviceCode.isEmpty) {
        throw const FormatException('device_code 不是字串');
      }
      if (pairing is! String || pairing.isEmpty) {
        throw const FormatException('pairing_code 不是字串');
      }
      if (expires is! int || expires <= 0) {
        throw const FormatException('expires_in 必須是正整數');
      }
      if (interval is! int || interval <= 0) {
        throw const FormatException('interval 必須是正整數');
      }
      return CareLinkStart(
        deviceCode: deviceCode,
        pairingCode: pairing,
        expiresIn: Duration(seconds: expires),
        interval: Duration(seconds: interval),
      );
    });
  }

  /// 查詢綁定是否核准。被拒絕、過期、輪詢太快時丟出 [CareApiException]
  /// (`DENIED`、`EXPIRED`、`SLOW_DOWN`)。
  Future<CareLinkPoll> pollLink(Uri base, String deviceCode) async {
    const path = '$_cup/link/poll/';
    final data =
        await _send('POST', base, path, body: {'device_code': deviceCode});
    return _parse(path, () {
      switch (data['status']) {
        case 'pending':
          return const CareLinkPending();
        case 'approved':
          final token = data['token'], linkId = data['link_id'];
          // token 之後要放進 HTTP header:只接受可見的 ASCII 字元。
          if (token is! String || !RegExp(r'^[\x21-\x7E]+$').hasMatch(token)) {
            throw const FormatException('token 格式不符');
          }
          if (linkId is! int) throw const FormatException('link_id 不是整數');
          return CareLinkApproved(
            token: token,
            linkId: linkId,
            resident: CareResident.fromJson(data['resident']),
            goal: CareGoal._fromData(data),
          );
        default:
          throw const FormatException('未知的 status');
      }
    });
  }

  // -------------------------------------------------------------- 需要 token

  /// 目前的綁定、住民與每日目標。
  Future<CareMe> me(Uri base, String token) async {
    const path = '$_cup/me/';
    final data = await _send('GET', base, path, token: token);
    return _parse(path, () {
      final linkId = data['link_id'];
      if (linkId is! int) throw const FormatException('link_id 不是整數');
      return CareMe(
        linkId: linkId,
        resident: CareResident.fromJson(data['resident']),
        goal: CareGoal._fromData(data),
        serverTime: _serverTime(data['server_time']),
      );
    });
  }

  /// 上傳事件([careEventPayload] 的結果),一次最多 [maxEventsPerRequest] 筆。
  /// [dayTotals] 是 App 統計頁上最近幾天的喝水量,一起送出;null 時不送。
  Future<List<CareEventResult>> uploadEvents(
    Uri base,
    String token,
    List<Map<String, Object?>> events, {
    List<CareDayTotal>? dayTotals,
  }) async {
    if (events.length > maxEventsPerRequest) {
      throw ArgumentError.value(
          events.length, 'events', '一次最多 $maxEventsPerRequest 筆');
    }
    const path = '$_cup/events/';
    final data = await _send('POST', base, path, token: token, body: {
      'events': events,
      if (dayTotals != null)
        'day_totals': [for (final d in dayTotals) d.toJson()],
    });
    return _parse(path, () {
      final list = data['results'];
      if (list is! List) throw const FormatException('results 不是陣列');
      return [
        for (final r in list)
          if (r
              case {
                'client_event_id': final String id,
                'result': final String result,
              })
            CareEventResult(
              clientEventId: id,
              recordId: r['record_id'] is int ? r['record_id'] as int : null,
              result: result,
            )
          else
            throw const FormatException('results 的欄位型別不符'),
      ];
    });
  }

  /// 回報 App 與水杯的狀態;回傳 Server 目前的每日目標。
  Future<CareStatusReply> postStatus(
    Uri base,
    String token,
    CareStatusReport report,
  ) async {
    const path = '$_cup/status/';
    final data =
        await _send('POST', base, path, token: token, body: report.toJson());
    return _parse(
      path,
      () => CareStatusReply(
        goal: CareGoal._fromData(data),
        serverTime: _serverTime(data['server_time']),
        resident: data['resident'] == null
            ? null
            : CareResident.fromJson(data['resident']),
      ),
    );
  }

  // ------------------------------------------------------------------ 共用

  static DateTime? _serverTime(Object? seconds) => seconds is int && seconds > 0
      ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
      : null;

  /// 驗證並轉換 `data`;欄位不符合約時丟出 `BAD_RESPONSE`。
  T _parse<T>(String path, T Function() build) {
    try {
      return build();
    } on FormatException catch (e) {
      throw _log(
        path,
        CareApiException(
          code: CareApiException.badResponse,
          message: '伺服器回應的格式不符(${e.message})',
          retryable: false,
          statusCode: 200,
        ),
      );
    }
  }

  CareApiException _log(String path, CareApiException e) {
    debugPrint('[CareApi] $path 失敗:$e');
    return e;
  }

  /// 5xx、408、429 是暫時的;其他狀態碼重送也沒用(和伺服器的規則一致)。
  static bool _retryableStatus(int status) =>
      status >= 500 || status == 408 || status == 429;

  /// 送出請求並解開 envelope,回傳 `data`。
  Future<Map<String, dynamic>> _send(
    String method,
    Uri base,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) async {
    final url = base.replace(path: '${base.path}$path');
    // 逾時的時候用 abortTrigger 真的中止連線,不讓它在背景繼續跑。
    final abort = Completer<void>();
    final request = http.AbortableRequest(method, url,
        abortTrigger: abort.future)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }

    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(totalTimeout);
    } on TimeoutException {
      abort.complete();
      throw _log(
        path,
        CareApiException(
          code: CareApiException.timeout,
          message: '連線逾時(${totalTimeout.inSeconds} 秒內沒有回應)',
          retryable: true,
        ),
      );
    } catch (e) {
      // 連不上、DNS、TLS 等。只記錯誤的型別:例外訊息可能帶有網址以外的內容。
      throw _log(
        path,
        CareApiException(
          code: CareApiException.network,
          message: '無法連上伺服器(${e.runtimeType})',
          retryable: true,
        ),
      );
    }

    final status = response.statusCode;
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException {
      json = null;
    }
    if (json is! Map<String, dynamic> || json['success'] is! bool) {
      throw _log(
        path,
        CareApiException(
          code: CareApiException.badResponse,
          message: status >= 300 && status < 400
              ? '伺服器要求轉址(HTTP $status),請確認伺服器位址'
              : '伺服器回應不是預期的格式(HTTP $status)',
          retryable: _retryableStatus(status),
          statusCode: status,
        ),
      );
    }
    if (json['success'] == true) {
      final data = json['data'];
      if (status < 200 || status >= 300 || data is! Map<String, dynamic>) {
        throw _log(
          path,
          CareApiException(
            code: CareApiException.badResponse,
            message: '伺服器回應不是預期的格式(HTTP $status)',
            retryable: _retryableStatus(status),
            statusCode: status,
          ),
        );
      }
      return data;
    }
    final error = json['error'];
    final code = error is Map ? error['code'] : null;
    final message = error is Map ? error['message'] : null;
    final retryable = error is Map ? error['retryable'] : null;
    throw _log(
      path,
      CareApiException(
        code: code is String && code.isNotEmpty ? code : 'ERROR',
        message: message is String && message.isNotEmpty
            ? message
            : '請求失敗(HTTP $status)',
        retryable: retryable is bool ? retryable : _retryableStatus(status),
        statusCode: status,
      ),
    );
  }
}
