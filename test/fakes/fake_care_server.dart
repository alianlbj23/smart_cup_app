import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 測試用的假照護系統:照介面合約 §2 回應,並記下收到的請求。
///
/// 每個端點都有預設行為,測試可以用對應的 `on…` 換掉,或把 [down] 設成 true
/// 模擬連不上。
class FakeCareServer {
  static const base = 'https://care.test';
  static const token = 'cup_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  static const deviceCode =
      'dc00000000000000000000000000000000000000000000000000000000000000';

  final List<http.Request> requests = [];

  /// true 時所有請求都以 ClientException 失敗(沒有網路)。
  bool down = false;

  /// `cup/residents/` 回傳的名單。
  List<Map<String, Object?>> residents = [
    {'id': 12, 'label': '101-1', 'name_masked': '王○明'},
    {'id': 13, 'label': '101-2', 'name_masked': '李○'},
  ];

  /// `cup/link/start/` 回傳的 `expires_in`、`interval`(秒)。
  int expiresIn = 600;
  int interval = 5;

  /// `cup/link/poll/` 依序回應;用完之後一律回 pending。
  final List<FutureOr<http.Response> Function()> pollScript = [];

  /// Server 目前的每日目標(`cup/me/`、`cup/status/`、核准時回傳)。
  int? goalMl = 1500;
  String? goalFrom = '2026-11-25';

  /// 需要 token 的端點是否回 401 TOKEN_EXPIRED。
  bool tokenRevoked = false;

  FutureOr<http.Response> Function(http.Request r)? onHealth;
  FutureOr<http.Response> Function(http.Request r)? onResidents;
  FutureOr<http.Response> Function(http.Request r)? onStart;
  FutureOr<http.Response> Function(http.Request r)? onMe;
  FutureOr<http.Response> Function(http.Request r)? onStatus;

  /// `cup/events/` 的行為;參數是這一批的事件。預設全部回 created。
  FutureOr<http.Response> Function(List<Map<String, dynamic>> events)? onEvents;

  /// 成功收下的事件批次(每個請求一批)。
  final List<List<Map<String, dynamic>>> uploadedBatches = [];

  /// `cup/status/` 的回應要不要帶 `resident`(舊版 Server 不帶)。
  bool statusIncludesResident = true;

  /// 收到的 `cup/status/` 內容。
  final List<Map<String, dynamic>> statuses = [];

  http.Client get client => MockClient(_handle);

  /// 路徑結尾是 [suffix] 的請求。
  List<http.Request> requestsTo(String suffix) =>
      [for (final r in requests) if (r.url.path.endsWith(suffix)) r];

  /// 所有成功上傳的事件(依上傳順序)。
  List<Map<String, dynamic>> get uploaded =>
      [for (final b in uploadedBatches) ...b];

  static http.Response ok(Object data) => _json({'success': true, 'data': data});

  static http.Response fail(int status, String code,
          {String message = '測試錯誤', bool? retryable}) =>
      _json({
        'success': false,
        'error': {
          'code': code,
          'message': message,
          'retryable': retryable ??
              (status >= 500 || const [401, 408, 429].contains(status)),
        },
      }, status);

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status,
          headers: {'content-type': 'application/json'});

  Map<String, Object?> get _resident => residents.first;

  /// 核准的回應。
  http.Response approved({Map<String, Object?>? resident}) => ok({
        'status': 'approved',
        'token': token,
        'link_id': 7,
        'resident': resident ?? _resident,
        'daily_goal_ml': goalMl,
        'goal_effective_from': goalMl == null ? null : goalFrom,
      });

  Future<http.Response> _handle(http.Request r) async {
    requests.add(r);
    if (down) throw http.ClientException('Connection refused', r.url);
    final path = r.url.path;
    if (path.endsWith('/api/machine/health/')) {
      return await (onHealth?.call(r) ??
          ok({'status': 'ok', 'server_time': 1795600000, 'api_version': 1}));
    }
    if (path.endsWith('/cup/residents/')) {
      return await (onResidents?.call(r) ?? ok({'residents': residents}));
    }
    if (path.endsWith('/cup/link/start/')) {
      return await (onStart?.call(r) ??
          ok({
            'device_code': deviceCode,
            'pairing_code': 'K7QM42XP',
            'expires_in': expiresIn,
            'interval': interval,
          }));
    }
    if (path.endsWith('/cup/link/poll/')) {
      if (pollScript.isEmpty) return ok({'status': 'pending'});
      return await pollScript.removeAt(0)();
    }
    // ---- 以下需要 token ----
    if (tokenRevoked || r.headers['Authorization'] != 'Bearer $token') {
      return fail(401, 'TOKEN_EXPIRED', message: '綁定已解除,請重新連結');
    }
    if (path.endsWith('/cup/me/')) {
      return await (onMe?.call(r) ??
          ok({
            'link_id': 7,
            'resident': _resident,
            'daily_goal_ml': goalMl,
            'goal_effective_from': goalMl == null ? null : goalFrom,
            'server_time': 1795600000,
          }));
    }
    if (path.endsWith('/cup/events/')) {
      final events = [
        for (final e in (jsonDecode(r.body) as Map)['events'] as List)
          (e as Map).cast<String, dynamic>(),
      ];
      final custom = onEvents;
      if (custom != null) {
        final response = await custom(events);
        if (response.statusCode == 200) uploadedBatches.add(events);
        return response;
      }
      uploadedBatches.add(events);
      return ok(resultsFor(events));
    }
    if (path.endsWith('/cup/status/')) {
      statuses.add((jsonDecode(r.body) as Map).cast<String, dynamic>());
      return await (onStatus?.call(r) ??
          ok({
            'server_time': 1795600000,
            'daily_goal_ml': goalMl,
            'goal_effective_from': goalMl == null ? null : goalFrom,
            // 住民目前的資料(換床位後 App 靠這個跟上);舊版 Server 沒有這個欄位。
            if (statusIncludesResident) 'resident': _resident,
          }));
    }
    return http.Response('Not Found', 404);
  }

  /// `cup/events/` 成功時的 `data`。
  static Map<String, Object?> resultsFor(List<Map<String, dynamic>> events) => {
        'results': [
          for (var i = 0; i < events.length; i++)
            {
              'client_event_id': events[i]['client_event_id'],
              'record_id': 1000 + i,
              'result': 'created',
            },
        ],
      };
}
