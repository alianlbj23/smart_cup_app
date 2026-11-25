import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_info.dart' as app_info;
import '../data/intake_repository.dart';
import '../services/care_api.dart';
import '../services/care_link_store.dart';
import '../services/device_store.dart' show RememberedDevice;
import 'cup_connection_manager.dart';

/// 連結流程在 App 這一端就能判斷的問題(還沒配對水杯、水杯識別碼不能用…)。
/// [message] 可以直接顯示。
class CareLinkException implements Exception {
  const CareLinkException(this.message);

  final String message;

  @override
  String toString() => 'CareLinkException: $message';
}

/// 送給照護系統的 `platform`:合約只接受 android / ios / linux / windows / macos / web。
String carePlatformName() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.linux => 'linux',
    TargetPlatform.windows => 'windows',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.fuchsia =>
      throw const CareLinkException('這個平台不支援連結照護系統'),
  };
}

/// 等待核准的狀態。
enum CarePairingStatus {
  /// 等待照護人員在網頁按下確定,輪詢中。
  waiting,

  /// 已核准,token 已存好。
  approved,

  /// 照護人員拒絕。
  denied,

  /// 配對碼過期(伺服器回 EXPIRED,或 App 自己數到時間)。
  expired,

  /// 其他無法繼續的錯誤。
  failed,
}

/// 一次綁定請求(畫面顯示用)。不可變,狀態改變時換一個新的。
class CarePairing {
  const CarePairing({
    required this.resident,
    required this.pairingCode,
    required this.expiresAt,
    required this.status,
    this.message,
    this.warning,
  });

  final CareResident resident;

  /// 顯示在畫面上、讓照護人員在網頁核對的配對碼。
  final String pairingCode;
  final DateTime expiresAt;
  final CarePairingStatus status;

  /// 結束的原因(被拒絕、過期、錯誤),[status] 不是 waiting / approved 時有值。
  final String? message;

  /// 等待中暫時的狀況(例如連不上伺服器,仍會繼續嘗試)。
  final String? warning;

  /// 距離過期還有多久(不會是負的)。
  Duration remaining(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  CarePairing _with({
    CarePairingStatus? status,
    String? message,
    String? warning,
  }) =>
      CarePairing(
        resident: resident,
        pairingCode: pairingCode,
        expiresAt: expiresAt,
        status: status ?? this.status,
        message: message,
        warning: warning,
      );
}

/// 「連結照護系統」的狀態與流程(介面合約 §2.1)。
///
/// 1. [fetchResidents] 抓名單 → 使用者選「我是誰」。
/// 2. [startPairing] 送出綁定請求,之後依伺服器給的 `interval` 輪詢,直到核准、
///    被拒絕、過期,或使用者 [cancelPairing] / 離開畫面。
/// 3. 核准後把 token、住民、目標存到 [CareLinkStore],每日目標改以 Server 為準。
///
/// token 只存在 [CareLinkStore] 與記憶體,不會出現在 log 或例外訊息。
class CareLinkManager extends ChangeNotifier {
  CareLinkManager({
    required this._api,
    required this._store,
    required this._repo,
    required this._cups,
    DateTime Function()? clock,
    String Function()? platform,
    this.appVersion = app_info.appVersion,
  })  : _clock = clock ?? DateTime.now,
        _platform = platform ?? carePlatformName {
    _cupsSignature = _currentCupsSignature();
    _cups.addListener(_onCupsChanged);
  }

  /// 伺服器回 SLOW_DOWN 時,輪詢間隔每次加這麼多。
  static const slowDownStep = Duration(seconds: 5);

  /// `cup_hardware_id` 的格式(合約 §2.1)。
  static final _hardwareIdPattern = RegExp(r'^[A-Za-z0-9:._-]{1,64}$');
  static const _maxCupNameLength = 64;

  final CareApi _api;
  final CareLinkStore _store;
  final IntakeRepository _repo;
  final CupConnectionManager _cups;
  final DateTime Function() _clock;
  final String Function() _platform;
  final String appVersion;

  bool _loaded = false;
  bool _disposed = false;
  String _serverUrl = defaultCareServerUrl;
  CareLink? _link;
  String? _notice;
  CarePairing? _pairing;

  /// 輪詢用的密碼與間隔;只在等待核准時有值。
  String? _deviceCode;
  Duration _pollInterval = Duration.zero;
  Timer? _pollTimer;

  /// 每次開始或取消綁定請求就加一,舊的輪詢看到不一樣就不再排下一次。
  int _session = 0;

  /// [load] 是否完成。
  bool get loaded => _loaded;

  /// 伺服器位址(已驗證)。
  String get serverUrl => _serverUrl;

  /// 已連結的資料;尚未連結時為 null。
  CareLink? get link => _link;
  bool get isLinked => _link != null;

  /// 要顯示給使用者的提示(例如連結失效的原因),按「知道了」或重新連結後消失。
  String? get notice => _notice;

  /// 進行中(或剛結束)的綁定請求。
  CarePairing? get pairing => _pairing;

  /// 配對過的水杯;沒有配對過就不能連結照護系統。
  RememberedDevice? get pairedCup => _cups.rememberedDevice;

  /// 目前時間(和輪詢、過期判斷用同一個時鐘;畫面的倒數用這個)。
  DateTime get now => _clock();

  /// 已連結,但目前連線中的是另一個水杯:它的紀錄不會上傳(連結綁的是
  /// [CareLink.cupLocalId] 那一個)。
  bool get otherCupConnected {
    final link = _link;
    final active = _activeCupId;
    return link != null && active != null && active != link.cupLocalId;
  }

  String? get _activeCupId =>
      _cups.state == CupConnectionState.ready ? _cups.activeDeviceId : null;

  /// 水杯那邊每收到一筆封包都會通知;這裡只在「配對的水杯」或「連線中的水杯」
  /// 換了的時候才通知畫面。
  (String?, String?) _cupsSignature = (null, null);

  (String?, String?) _currentCupsSignature() => (pairedCup?.id, _activeCupId);

  void _onCupsChanged() {
    final signature = _currentCupsSignature();
    if (signature == _cupsSignature) return;
    _cupsSignature = signature;
    notifyListeners();
  }

  /// App 啟動時呼叫:讀取儲存的伺服器位址、連結與提示。不會連網。
  Future<void> load() async {
    _serverUrl = await _store.loadServerUrl();
    _link = await _store.loadLink();
    _notice = await _store.loadNotice();
    final link = _link;
    if (link != null) {
      await _repo.applyServerGoal(link.dailyGoalMl);
    } else {
      // 沒有連結(例如儲存的資料被清掉)就不能再說目標是 Server 設定的。
      await _repo.clearServerGoal();
    }
    _loaded = true;
    notifyListeners();
  }

  // ------------------------------------------------------------ 伺服器位址

  /// 儲存伺服器位址。不合法時丟出 [FormatException];已連結或正在等待核准時不能改。
  Future<void> setServerUrl(String input) async {
    final url = parseCareServerUrl(input).toString();
    if (isLinked) {
      throw const CareLinkException('已連結照護系統,要換伺服器請先解除連結');
    }
    if (_pairing?.status == CarePairingStatus.waiting) {
      throw const CareLinkException('正在等待核准,請先取消');
    }
    await _store.saveServerUrl(url);
    _serverUrl = url;
    notifyListeners();
  }

  /// 測試連線(`GET /api/machine/health/`)。[input] 是畫面上輸入的位址,不會儲存。
  /// 位址不合法丟 [FormatException],連不上丟 [CareApiException]。
  Future<CareHealth> testConnection(String input) async =>
      _api.health(parseCareServerUrl(input));

  // -------------------------------------------------------------- 綁定流程

  /// 「選我是誰」的名單。
  Future<List<CareResident>> fetchResidents() =>
      _api.residents(Uri.parse(_serverUrl));

  /// 送出綁定請求並開始輪詢。
  ///
  /// 還沒配對水杯、水杯識別碼不合規定時丟 [CareLinkException];伺服器拒絕時丟
  /// [CareApiException]。兩種情況都不會進入等待。
  Future<void> startPairing(CareResident resident) async {
    if (isLinked) throw const CareLinkException('已經連結照護系統');
    final cup = pairedCup;
    if (cup == null) {
      throw const CareLinkException('請先到「水杯」分頁配對水杯,再連結照護系統');
    }
    final hardwareId = await _hardwareIdOf(cup);
    if (!_hardwareIdPattern.hasMatch(hardwareId)) {
      throw const CareLinkException('這個水杯的識別碼不能用來連結照護系統(含有不支援的字元)');
    }
    final platform = _platform();
    final base = Uri.parse(_serverUrl);
    final serverUrl = _serverUrl;

    _stopPolling();
    final session = _session;
    _pairing = null;
    notifyListeners();

    final started = await _api.startLink(
      base,
      installId: await _store.installId(),
      residentId: resident.id,
      cupHardwareId: hardwareId,
      cupName: _clip(cup.name, _maxCupNameLength),
      platform: platform,
      appVersion: appVersion,
    );
    if (_disposed || session != _session) return;

    _deviceCode = started.deviceCode;
    _pollInterval = started.interval;
    _pairing = CarePairing(
      resident: resident,
      pairingCode: started.pairingCode,
      expiresAt: _clock().add(started.expiresIn),
      status: CarePairingStatus.waiting,
    );
    notifyListeners();
    _schedulePoll(
        session,
        _PendingCup(
            serverUrl: serverUrl,
            localId: cup.id,
            hardwareId: hardwareId,
            name: cup.name));
  }

  /// 取消等待(使用者按取消或離開畫面):停止輪詢。
  ///
  /// 伺服器沒有「取消」的端點,那筆請求會留到過期;萬一取消的同時照護人員剛好核准,
  /// 進行中的那一次輪詢拿到 token 還是會存下來(見 [_poll])。
  void cancelPairing() {
    _stopPolling();
    if (_pairing == null) return;
    _pairing = null;
    notifyListeners();
  }

  void _stopPolling() {
    _session++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _deviceCode = null;
  }

  void _schedulePoll(int session, _PendingCup cup) {
    _pollTimer?.cancel();
    _pollTimer = Timer(_pollInterval, () => unawaited(_poll(session, cup)));
  }

  Future<void> _poll(int session, _PendingCup cup) async {
    final deviceCode = _deviceCode;
    final pairing = _pairing;
    if (_disposed ||
        session != _session ||
        deviceCode == null ||
        pairing == null) {
      return;
    }
    if (!_clock().isBefore(pairing.expiresAt)) {
      _finishPairing(session, CarePairingStatus.expired, '配對碼已過期,請重新連結');
      return;
    }

    final CareLinkPoll result;
    try {
      result = await _api.pollLink(Uri.parse(cup.serverUrl), deviceCode);
    } on CareApiException catch (e) {
      if (_disposed || session != _session) return;
      switch (e.code) {
        case 'DENIED':
          _finishPairing(
              session, CarePairingStatus.denied, '照護人員拒絕了這次連結請求');
        case 'EXPIRED':
          _finishPairing(
              session, CarePairingStatus.expired, '配對碼已過期,請重新連結');
        case 'SLOW_DOWN':
          _pollInterval += slowDownStep;
          _schedulePoll(session, cup);
        default:
          if (e.retryable) {
            // 暫時連不上:提示使用者,繼續輪詢到過期為止。
            _pairing = pairing._with(warning: '暫時連不上伺服器,會繼續嘗試(${e.message})');
            notifyListeners();
            _schedulePoll(session, cup);
          } else {
            _finishPairing(session, CarePairingStatus.failed, e.message);
          }
      }
      return;
    }

    switch (result) {
      case CareLinkPending():
        if (_disposed || session != _session) return;
        if (pairing.warning != null) {
          _pairing = pairing._with();
          notifyListeners();
        }
        _schedulePoll(session, cup);
      case CareLinkApproved():
        // 伺服器只回這一次:就算使用者剛好按了取消也要存下來,否則網頁端顯示已綁定、
        // App 卻沒有 token。
        await _onApproved(result, cup, pairing);
    }
  }

  void _finishPairing(int session, CarePairingStatus status, String message) {
    if (session != _session) return;
    _stopPolling();
    _pairing = _pairing?._with(status: status, message: message);
    notifyListeners();
  }

  Future<void> _onApproved(
    CareLinkApproved approved,
    _PendingCup cup,
    CarePairing pairing,
  ) async {
    _stopPolling();
    // Server 會把收到的事件都算在 token 所屬的住民身上。連結到和上次不同的住民
    // (或第一次連結)時,本機原有的紀錄不可以上傳:在存 token 之前先標好。
    // 重新連結到同一位住民則照常補傳。
    final residentKey = '${cup.serverUrl}#${approved.resident.id}';
    if (await _store.loadLastResident() != residentKey) {
      final excluded = await _repo.excludeAllFromSync();
      debugPrint('[CareLink] 連結到新的住民:本機原有的 $excluded 筆紀錄不上傳');
    }
    final link = CareLink(
      token: approved.token,
      linkId: approved.linkId,
      resident: approved.resident,
      dailyGoalMl: approved.goal.dailyGoalMl,
      goalEffectiveFrom: approved.goal.effectiveFrom,
      linkedAtMs: _clock().millisecondsSinceEpoch,
      serverUrl: cup.serverUrl,
      cupLocalId: cup.localId,
      cupHardwareId: cup.hardwareId,
      cupName: cup.name,
    );
    await _store.saveLink(link);
    await _store.saveLastResident(residentKey);
    await _store.saveNotice(null);
    await _repo.applyServerGoal(link.dailyGoalMl);
    debugPrint('[CareLink] 已連結:$link');
    if (_disposed) return;
    _link = link;
    _notice = null;
    _pairing = pairing._with(status: CarePairingStatus.approved);
    notifyListeners();
  }

  /// 水杯的 `cup_hardware_id`:韌體 0.4.0 起用水杯自己回報的 BLE 位址(連線中的
  /// Device Status,或之前記在資料庫的);舊韌體用平台給的 remoteId。
  Future<String> _hardwareIdOf(RememberedDevice cup) async {
    if (_cups.activeDeviceId == cup.id) {
      final live = _cups.deviceStatus?.bleAddress;
      if (live != null) return live;
    }
    return (await _repo.cup(cup.id))?.bleAddress ?? cup.id;
  }

  static String _clip(String text, int maxChars) =>
      text.runes.length <= maxChars
          ? text
          : String.fromCharCodes(text.runes.take(maxChars));

  // ---------------------------------------------------------------- 已連結

  /// 解除連結:只清掉這台裝置上的 token(伺服器沒有給 App 用的解除端點,網頁端也要
  /// 請照護人員解除綁定)。本機紀錄保留,每日目標回到單機行為。
  Future<void> unlink() => _clearLink(notice: null);

  /// 伺服器回 401 TOKEN_EXPIRED(token 無效或綁定已在網頁端解除):清掉 token,
  /// 回到「尚未連結」,並留下說明讓畫面顯示。本機紀錄保留。
  ///
  /// [token] 是收到 401 的那個請求用的 token:已經不是目前的連結(例如同時有兩個請求
  /// 都收到 401,或已經重新連結)就不處理。
  Future<void> handleTokenExpired(String serverMessage, {String? token}) async {
    final current = _link;
    if (current == null || (token != null && current.token != token)) return;
    await _clearLink(
      notice: '照護系統的連結已失效(可能已在網頁端解除綁定),請重新連結。'
          '本機紀錄仍保留。伺服器的說明:$serverMessage',
    );
  }

  Future<void> _clearLink({required String? notice}) async {
    _stopPolling();
    await _store.clearLink();
    await _store.saveNotice(notice);
    await _repo.clearServerGoal();
    debugPrint('[CareLink] 已清除本機的連結'
        '${notice == null ? '(使用者解除)' : '(token 失效)'}');
    _link = null;
    _pairing = null;
    _notice = notice;
    notifyListeners();
  }

  /// 使用者看過提示了。
  Future<void> dismissNotice() async {
    await _store.saveNotice(null);
    _notice = null;
    notifyListeners();
  }

  /// 套用伺服器回傳的每日目標(與住民資訊)。[token] 是送出請求時用的 token:
  /// 回應到的時候已經解除連結或換了連結就忽略。
  Future<void> applyServerInfo(
    String token, {
    required CareGoal goal,
    CareResident? resident,
  }) async {
    final current = _link;
    if (current == null || current.token != token) return;
    var updated = current.withGoal(goal);
    if (resident != null) updated = updated.withResident(resident);
    final changed = updated.dailyGoalMl != current.dailyGoalMl ||
        updated.goalEffectiveFrom != current.goalEffectiveFrom ||
        updated.resident.id != current.resident.id ||
        updated.resident.label != current.resident.label ||
        updated.resident.nameMasked != current.resident.nameMasked;
    if (!changed) return;
    await _store.saveLink(updated);
    await _repo.applyServerGoal(updated.dailyGoalMl);
    if (_link?.token != token) return;
    _link = updated;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _cups.removeListener(_onCupsChanged);
    super.dispose();
  }
}

/// 送出綁定請求當下的伺服器與水杯,核准後寫進 [CareLink]。
class _PendingCup {
  const _PendingCup({
    required this.serverUrl,
    required this.localId,
    required this.hardwareId,
    required this.name,
  });

  final String serverUrl;
  final String localId;
  final String hardwareId;
  final String name;
}
