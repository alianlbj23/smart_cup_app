import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/intake_repository.dart';
import '../services/care_api.dart';
import '../services/care_link_store.dart';
import 'care_link_manager.dart';
import 'cup_connection_manager.dart';

/// 已連結照護系統時,在背景把資料送給 Server(介面合約 §2.2):
///
/// **上傳紀錄**(`cup/events/`):新增、修改、刪除(軟刪除)的事件,以
/// `client_event_id = intake_events.id`、`updated_at = updatedAtMs` 上傳,一批最多
/// 200 筆;Server 回成功才標成已同步。什麼時候試:App 啟動、連結成功、每次有新事件
/// (等 [debounce] 把連續的變更併成一次)、每 [interval](5 分鐘)。
/// - 可重試的錯誤(網路、逾時、5xx、429):紀錄留在佇列,退避後重試([retryDelay])。
/// - 某一筆紀錄的問題(`INVALID_EVENT`、`CLIENT_EVENT_ID_TAKEN`):伺服器只說整批失敗,
///   所以把這一批對半拆開再送,找出修不了的那一筆,記下原因並移出佇列,不卡住其他紀錄。
/// - 其他不可重試的錯誤:這一輪放棄並記 log,紀錄留著,下一次觸發再試。
/// - 401 `TOKEN_EXPIRED`:交給 [CareLinkManager.handleTokenExpired] 清掉 token。
///
/// **狀態回報**(`cup/status/`):App 啟動、連結成功、每 [interval]、以及已連結的水杯
/// 連上/斷線時。回應裡的每日目標會套用到本機(Server 為準,null 就是沒有目標)。
///
/// 尚未連結時完全不連網。
class CareSync extends ChangeNotifier {
  CareSync({
    required this._api,
    required this._link,
    required this._repo,
    required this._cups,
    required this._store,
    DateTime Function()? clock,
    this.interval = const Duration(minutes: 5),
    this.debounce = defaultDebounce,
    this.batchSize = CareApi.maxEventsPerRequest,
  }) : _clock = clock ?? DateTime.now;

  /// 有新事件後等多久才上傳(連續的變更併成一次)。
  static const defaultDebounce = Duration(seconds: 2);

  /// 第一次重試前等多久,之後每次加倍。
  static const retryBase = Duration(seconds: 30);

  /// 重試間隔的上限。
  static const retryMax = Duration(minutes: 5);

  /// 「是某一筆紀錄有問題」的錯誤碼:把這一批拆小找出是哪一筆。
  static const _eventErrorCodes = {'INVALID_EVENT', 'CLIENT_EVENT_ID_TAKEN'};

  /// 這一批太大:拆小再送,不是紀錄本身的問題。
  static const _tooManyEvents = 'TOO_MANY_EVENTS';

  /// 第 [attempt] 次(從 1 起算)連續失敗後要等多久:30、60、120、240 秒,最多 5 分鐘。
  static Duration retryDelay(int attempt) {
    if (attempt >= 5) return retryMax;
    final delay = retryBase * (1 << (attempt - 1));
    return delay > retryMax ? retryMax : delay;
  }

  final CareApi _api;
  final CareLinkManager _link;
  final IntakeRepository _repo;
  final CupConnectionManager _cups;
  final CareLinkStore _store;
  final DateTime Function() _clock;

  /// 定期上傳與回報的間隔。
  final Duration interval;
  final Duration debounce;
  final int batchSize;

  bool _started = false;
  bool _disposed = false;
  Timer? _periodic;
  Timer? _retryTimer;
  Timer? _debounceTimer;

  /// 目前連結的 token(只用來判斷連結有沒有換)。
  String? _linkToken;

  /// 上一次看到「已連結的水杯是否連線中」,變了就回報狀態。
  bool _cupConnected = false;

  int? _cupLastSeenAtMs;
  String? _cupFirmware;

  bool _uploading = false;
  bool _uploadAgain = false;
  bool _reporting = false;
  bool _reportAgain = false;
  int _retryAttempt = 0;

  int _pendingCount = 0;
  int _rejectedCount = 0;
  DateTime? _lastSyncedAt;
  String? _lastError;

  /// 進行中的工作,測試可等待。
  final Set<Future<void>> _inFlight = {};

  /// 還沒上傳的紀錄筆數(尚未連結時為 0)。
  int get pendingCount => _pendingCount;

  /// 被照護系統拒收、沒有上傳的紀錄筆數(畫面要讓使用者知道,不能只顯示「已全部上傳」)。
  int get rejectedCount => _rejectedCount;

  /// 最近一次上傳全部成功的時間。
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// 最近一次上傳或回報失敗的原因;成功後清掉。
  String? get lastError => _lastError;

  bool get uploading => _uploading;

  /// 開始在背景同步。App 啟動時呼叫一次(要在 [CareLinkManager.load] 之後)。
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final seen = await _store.loadCupSeen();
    if (_disposed) return;
    _cupLastSeenAtMs = seen.lastSeenAtMs;
    _cupFirmware = seen.firmware;
    _linkToken = _link.link?.token;
    _cupConnected = _isCupConnected();
    _link.addListener(_onLinkChanged);
    _repo.addListener(_onRepoChanged);
    _cups.addListener(_onCupsChanged);
    _periodic = Timer.periodic(interval, (_) => _run(_tick()));
    if (_linkToken != null) _run(_tick(refreshMe: true));
  }

  /// 等目前進行中的工作做完。
  @visibleForTesting
  Future<void> settled() async {
    while (_inFlight.isNotEmpty) {
      await Future.wait([..._inFlight]);
    }
  }

  /// 取消「有新事件」排的那一次上傳(測試用)。
  @visibleForTesting
  void debugCancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// 立刻上傳並回報一次(「設定」頁的「立即同步」)。
  Future<void> syncNow() => _tick();

  // ---------------------------------------------------------------- 觸發

  void _onLinkChanged() {
    final token = _link.link?.token;
    if (token == _linkToken) return;
    _linkToken = token;
    _retryTimer?.cancel();
    _retryTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _retryAttempt = 0;
    _lastError = null;
    _lastSyncedAt = null;
    _pendingCount = 0;
    _rejectedCount = 0;
    // 換了連結:上一個連結記下的水杯狀態不沿用。
    _cupLastSeenAtMs = null;
    _cupFirmware = null;
    _cupConnected = _isCupConnected();
    notifyListeners();
    if (token != null) _run(_tick());
  }

  void _onRepoChanged() {
    if (_link.link == null) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      _run(upload());
    });
  }

  void _onCupsChanged() {
    // 每收到一筆封包都會通知,這裡只看「已連結的水杯連線狀態有沒有變」。
    if (_link.link == null) return;
    final connected = _isCupConnected();
    if (connected == _cupConnected) return;
    _cupConnected = connected;
    // 剛斷線:水杯最後出現的時間就是現在。
    if (!connected) _cupLastSeenAtMs = _clock().millisecondsSinceEpoch;
    _run(reportStatus());
  }

  bool _isCupConnected() {
    final link = _link.link;
    return link != null &&
        _cups.state == CupConnectionState.ready &&
        _cups.activeDeviceId == link.cupLocalId;
  }

  Future<void> _tick({bool refreshMe = false}) async {
    if (refreshMe) await _refreshMe();
    await reportStatus();
    await upload();
  }

  void _run(Future<void> work) {
    final guarded = work.catchError((Object e, StackTrace st) {
      // 不是 CareApiException 的意外錯誤(例如資料庫):記下來並顯示在設定頁。
      debugPrint('[CareSync] 同步時發生錯誤:$e\n$st');
      _lastError = '同步時發生錯誤:$e';
      notifyListeners();
    });
    _inFlight.add(guarded);
    guarded.whenComplete(() => _inFlight.remove(guarded));
  }

  // -------------------------------------------------------- 住民資訊與目標

  /// App 啟動時向 Server 確認連結還有效,並更新住民資訊(例如換床位)與目標。
  Future<void> _refreshMe() async {
    final link = _link.link;
    if (link == null) return;
    try {
      final me = await _api.me(Uri.parse(link.serverUrl), link.token);
      await _link.applyServerInfo(link.token,
          goal: me.goal, resident: me.resident);
    } on CareApiException catch (e) {
      await _onApiError(link, e, what: '讀取連結資訊');
    }
  }

  /// 401 → 清掉 token;其他錯誤記下來。回傳是不是 token 失效。
  Future<bool> _onApiError(
    CareLink link,
    CareApiException e, {
    required String what,
  }) async {
    if (e.isTokenExpired) {
      await _link.handleTokenExpired(e.message, token: link.token);
      return true;
    }
    debugPrint('[CareSync] $what失敗(${e.retryable ? '之後重試' : '不可重試'}):$e');
    _lastError = '$what失敗:${e.message}';
    notifyListeners();
    return false;
  }

  // ---------------------------------------------------------------- 狀態回報

  /// 回報 App 與水杯的狀態,並套用 Server 回傳的每日目標。
  Future<void> reportStatus() async {
    if (_reporting) {
      _reportAgain = true;
      return;
    }
    _reporting = true;
    try {
      do {
        _reportAgain = false;
        await _reportOnce();
      } while (_reportAgain && !_disposed);
    } finally {
      _reporting = false;
    }
  }

  Future<void> _reportOnce() async {
    final link = _link.link;
    if (link == null || _disposed) return;
    final connected = _isCupConnected();
    final status = connected ? _cups.deviceStatus : null;
    if (connected) {
      _cupLastSeenAtMs = _clock().millisecondsSinceEpoch;
      _cupFirmware = status?.firmwareVersion?.toString() ?? _cupFirmware;
    }
    if (_cupLastSeenAtMs != null || _cupFirmware != null) {
      await _store.saveCupSeen(
          lastSeenAtMs: _cupLastSeenAtMs, firmware: _cupFirmware);
    }
    final water = connected ? _cups.latestWater : null;
    final seenAt = _cupLastSeenAtMs;
    final report = CareStatusReport(
      cupConnected: connected,
      cupLastSeenAt:
          seenAt == null ? null : DateTime.fromMillisecondsSinceEpoch(seenAt),
      batteryPct: status?.batteryPercent,
      firmware: _cupFirmware,
      pendingEvents: await _repo.pendingSyncCount(cupId: link.cupLocalId),
      // 一位小數就夠(韌體的解析度是 0.5%)。
      levelPct: water == null ? null : (water.fillPercent * 10).round() / 10,
    );
    try {
      final reply =
          await _api.postStatus(Uri.parse(link.serverUrl), link.token, report);
      await _link.applyServerInfo(link.token, goal: reply.goal);
    } on CareApiException catch (e) {
      await _onApiError(link, e, what: '回報狀態');
    }
  }

  // -------------------------------------------------------------------- 上傳

  /// 把還沒同步的紀錄上傳。已經在上傳時,結束後會再跑一輪。
  Future<void> upload() async {
    if (_uploading) {
      _uploadAgain = true;
      return;
    }
    _uploading = true;
    try {
      do {
        _uploadAgain = false;
        await _uploadOnce();
      } while (_uploadAgain && !_disposed);
    } finally {
      _uploading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _uploadOnce() async {
    final link = _link.link;
    if (link == null || _disposed) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    try {
      while (_link.link?.token == link.token && !_disposed) {
        final batch = await _repo.pendingSyncEvents(
            cupId: link.cupLocalId, limit: batchSize);
        if (batch.isEmpty) {
          _retryAttempt = 0;
          _lastError = null;
          _lastSyncedAt = _clock();
          break;
        }
        if (await _uploadBatch(link, batch) == 0) {
          // 伺服器說成功卻沒有回報任何一筆:不再重送同一批,避免無窮迴圈。
          throw const CareApiException(
            code: CareApiException.badResponse,
            message: '伺服器沒有回報上傳結果',
            retryable: false,
          );
        }
      }
    } on CareApiException catch (e) {
      final expired = await _onApiError(link, e, what: '上傳紀錄');
      if (!expired && e.retryable) _scheduleRetry();
    } finally {
      await _refreshPending();
    }
  }

  /// 上傳一批,回傳「處理完」的筆數(已同步,或確定被拒收而移出佇列)。
  /// 整批失敗而且不是紀錄本身的問題時丟出 [CareApiException]。
  Future<int> _uploadBatch(CareLink link, List<IntakeEvent> batch) async {
    try {
      final results = await _api.uploadEvents(
        Uri.parse(link.serverUrl),
        link.token,
        [for (final e in batch) careEventPayload(e)],
      );
      final accepted = {for (final r in results) r.clientEventId};
      final versions = [
        for (final e in batch)
          if (accepted.contains(e.id)) (id: e.id, updatedAtMs: e.updatedAtMs),
      ];
      await _repo.markSynced(versions);
      return versions.length;
    } on CareApiException catch (e) {
      final eventProblem = _eventErrorCodes.contains(e.code);
      if (e.retryable || !(eventProblem || e.code == _tooManyEvents)) rethrow;
      if (batch.length == 1) {
        if (!eventProblem) rethrow;
        final event = batch.single;
        // App 修不了這一筆:記下原因、移出佇列(使用者之後修改這筆紀錄會再上傳)。
        debugPrint('[CareSync] 照護系統拒收紀錄 ${event.id}(${e.code}:${e.message}),'
            '不再重送');
        await _repo.markSyncRejected(
            event.id, event.updatedAtMs, '${e.code}:${e.message}');
        return 1;
      }
      // 伺服器只說整批失敗:對半拆開再送,好的那一半照常收下。
      final mid = batch.length ~/ 2;
      return await _uploadBatch(link, batch.sublist(0, mid)) +
          await _uploadBatch(link, batch.sublist(mid));
    }
  }

  void _scheduleRetry() {
    if (_disposed || _link.link == null) return;
    _retryAttempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay(_retryAttempt), () {
      _retryTimer = null;
      _run(upload());
    });
  }

  Future<void> _refreshPending() async {
    final link = _link.link;
    final count = link == null
        ? 0
        : await _repo.pendingSyncCount(cupId: link.cupLocalId);
    final rejected = link == null
        ? 0
        : await _repo.rejectedSyncCount(cupId: link.cupLocalId);
    if (_disposed) return;
    _pendingCount = count;
    _rejectedCount = rejected;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _periodic?.cancel();
    _retryTimer?.cancel();
    _debounceTimer?.cancel();
    if (_started) {
      _link.removeListener(_onLinkChanged);
      _repo.removeListener(_onRepoChanged);
      _cups.removeListener(_onCupsChanged);
    }
    super.dispose();
  }
}
