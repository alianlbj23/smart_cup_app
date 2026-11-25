import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/ble_service.dart';
import '../services/device_store.dart';

/// UI 顯示用的連線狀態(規格書 §5)。
enum CupConnectionState {
  idle,
  scanning,
  connecting,
  connected,
  serviceDiscovered,
  ready,

  /// 自動重連逾時找不到記憶裝置。
  notFound,
}

/// 目前的連線流程。
enum CupFlow {
  /// 首次配對:依 Service UUID 過濾並列出清單,由使用者選擇。
  pairing,

  /// 自動重連:定向掃描記憶的 deviceId,不顯示清單。
  reconnect,
}

class ReceivedPacket {
  const ReceivedPacket(this.packet, this.receivedAt, {required this.acked});

  final CupDataPacket packet;
  final DateTime receivedAt;
  final bool acked;
}

/// App 端連線流程狀態機,只依賴 [BleService] 抽象介面。
///
/// 每個流程(掃描/連線/斷線)開始時遞增 [_session],非同步步驟完成後
/// 若 session 已變更即放棄後續動作,避免使用者中途操作造成狀態錯亂。
class CupConnectionManager extends ChangeNotifier {
  CupConnectionManager({
    required BleService ble,
    DeviceStore? store,
    this.backgroundRetryInterval = const Duration(seconds: 20),
  })  : _ble = ble,
        _store = store ?? DeviceStore() {
    _subs = [
      ble.connectionState.listen(_onBleState),
      ble.scanResults.listen(_onScanResults),
      ble.dataNotifications.listen(_onData),
      ble.deviceStatusUpdates.listen(_onStatus),
    ];
  }

  static const reconnectScanTimeout = Duration(seconds: 15);
  static const pairingScanTimeout = Duration(seconds: 30);

  /// 自動重連流程中,連線/初始化連續失敗的重試上限。
  static const maxReconnectAttempts = 3;
  static const maxLogEntries = 50;

  /// 找不到記憶的水杯([CupConnectionState.notFound])時,隔多久在背景再試一次。
  ///
  /// 水杯靜止一段時間會進入深度睡眠(韌體 smart_cup_firmware),拿起杯子才會醒來並
  /// 廣播至少 30 秒;間隔要比這段時間短,醒來後才接得到。
  final Duration backgroundRetryInterval;
  Timer? _retryTimer;

  /// 超過此時間沒收到 WATER 就視為過期(韌體每 1 秒送一次)。
  static const waterStaleAfter = Duration(seconds: 5);

  /// 超過此時間沒收到 POSE 就視為過期(韌體每 1 秒送一次)。
  static const poseStaleAfter = Duration(seconds: 5);

  /// 超過此時間沒收到 ATTITUDE 就視為過期(韌體約每秒 5 次)。
  static const attitudeStaleAfter = Duration(seconds: 2);

  /// 休眠中韌體每 10 秒送一次 STATE keepalive;超過此時間(約 3 次)沒收到
  /// 就不再當作休眠中,回到一般的過期判斷。
  static const dozeKeepaliveTimeout = Duration(seconds: 25);

  final BleService _ble;
  final DeviceStore _store;
  late final List<StreamSubscription<Object?>> _subs;

  CupConnectionState _state = CupConnectionState.idle;
  CupFlow _flow = CupFlow.pairing;
  RememberedDevice? _remembered;
  List<BleDeviceInfo> _scanResults = const [];
  bool _pairingScanActive = false;
  String? _message;
  String? _deviceId;
  String? _deviceName;
  DeviceStatus? _deviceStatus;
  final List<ReceivedPacket> _log = [];
  int _receivedCount = 0;
  String? _logDeviceId;
  WaterPacket? _latestWater;
  DateTime? _latestWaterAt;
  PosePacket? _latestPose;
  DateTime? _latestPoseAt;
  AttitudePacket? _latestAttitude;
  DateTime? _latestAttitudeAt;
  StatePacket? _latestState;
  DateTime? _latestStateAt;

  /// [BleService.connect] 已完成,之後的斷線才算「連線中斷」。
  bool _linkUp = false;
  int _reconnectAttempts = 0;
  int _session = 0;
  bool _disposed = false;

  final _packets = StreamController<CupDataPacket>.broadcast();

  CupConnectionState get state => _state;
  CupFlow get flow => _flow;
  RememberedDevice? get rememberedDevice => _remembered;
  List<BleDeviceInfo> get scanResults => _scanResults;
  bool get pairingScanActive => _pairingScanActive;

  /// 給使用者看的提示/錯誤訊息。
  String? get message => _message;

  /// 正在連線或已連線的裝置名稱。
  String? get connectingName => _deviceName;

  /// 正在連線或已連線的裝置 id。
  String? get activeDeviceId => _deviceId;
  DeviceStatus? get deviceStatus => _deviceStatus;
  List<ReceivedPacket> get log => List.unmodifiable(_log);
  int get receivedCount => _receivedCount;

  /// 連線中收到的每一筆 Data Notify 封包(含 ATTITUDE / STATE / keepalive),
  /// 供飲水偵測等功能訂閱;未連線時收到的封包不會送出。dispose 時關閉。
  Stream<CupDataPacket> get packets => _packets.stream;

  /// 最近一筆水量;尚未收到或已換杯/斷線時為 null。
  WaterPacket? get latestWater => _latestWater;

  /// 收到 [latestWater] 的手機時間。
  DateTime? get latestWaterAt => _latestWaterAt;

  /// 最近一筆姿態分類(POSE);尚未收到或已換杯時為 null。
  PosePacket? get latestPose => _latestPose;
  DateTime? get latestPoseAt => _latestPoseAt;

  /// 最近一筆即時姿態角(ATTITUDE);尚未收到、已斷線或已換杯時為 null。
  AttitudePacket? get latestAttitude => _latestAttitude;

  /// 收到 [latestAttitude] 的手機時間。
  DateTime? get latestAttitudeAt => _latestAttitudeAt;

  /// 最近一筆水杯活動狀態(STATE);尚未收到、已斷線或已換杯時為 null。
  StatePacket? get latestState => _latestState;

  /// 收到 [latestState] 的手機時間。
  DateTime? get latestStateAt => _latestStateAt;

  /// 水杯是否休眠中:最新 STATE 為休眠,且收到它到 [now] 不超過
  /// [dozeKeepaliveTimeout]。
  bool isDozing(DateTime now) {
    final state = _latestState, at = _latestStateAt;
    return state != null &&
        at != null &&
        state.activity == CupActivity.dozing &&
        now.difference(at) <= dozeKeepaliveTimeout;
  }

  /// 已休眠多久:封包的 secondsInState 加上收到後經過的時間;
  /// 不在休眠中([isDozing] 為 false)時為 null。
  Duration? dozingFor(DateTime now) {
    if (!isDozing(now)) return null;
    final elapsed = now.difference(_latestStateAt!);
    return Duration(seconds: _latestState!.secondsInState) +
        (elapsed.isNegative ? Duration.zero : elapsed);
  }

  /// [latestWater] 是否已超過 [waterStaleAfter] 沒更新。
  ///
  /// 休眠中 WATER 約 30 秒才一筆,屬正常,只要有資料就不算過期。
  bool isWaterStale(DateTime now) {
    if (_latestWaterAt != null && isDozing(now)) return false;
    return _isStale(_freshSince(_latestWaterAt), now, waterStaleAfter);
  }

  /// [latestPose] 是否已超過 [poseStaleAfter] 沒更新。
  ///
  /// 休眠中韌體不送 POSE,此值會變成 true;UI 應先看 [isDozing]。
  bool isPoseStale(DateTime now) =>
      _isStale(_freshSince(_latestPoseAt), now, poseStaleAfter);

  /// [latestAttitude] 是否已超過 [attitudeStaleAfter] 沒更新。
  ///
  /// 休眠中韌體不送 ATTITUDE,此值會變成 true;UI 應先看 [isDozing]。
  bool isAttitudeStale(DateTime now) =>
      _isStale(_freshSince(_latestAttitudeAt), now, attitudeStaleAfter);

  /// 過期判斷的起算時間:剛收到「活動中」STATE(喚醒)時,從喚醒那一刻起算,
  /// 給韌體恢復即時推送的時間,避免喚醒瞬間閃一下「資料過期」。
  /// 尚未收到過資料([at] 為 null)仍視為沒有資料。
  DateTime? _freshSince(DateTime? at) {
    final wokeAt = _latestState?.activity == CupActivity.active
        ? _latestStateAt
        : null;
    if (at == null || wokeAt == null || wokeAt.isBefore(at)) return at;
    return wokeAt;
  }

  static bool _isStale(DateTime? at, DateTime now, Duration after) =>
      at == null || now.difference(at) > after;

  /// App 啟動:有記憶裝置 → 自動重連;否則維持 Idle,由使用者為住民配對水杯。
  Future<void> init() async {
    _remembered = await _store.load();
    if (_disposed) return;
    if (_remembered != null) await startAutoReconnect();
  }

  // ---------------------------------------------------------------- 掃描

  /// 為住民配對水杯:僅支援單一連線,先中斷目前水杯再開始配對掃描。
  Future<void> beginPairing() async {
    final pending = disconnect();
    final session = _session;
    await pending;
    if (session != _session) return;
    await startPairingScan();
  }

  /// 取消配對:停止掃描/連線,並回頭連線先前記憶的水杯。
  Future<void> cancelPairing() async {
    final pending = disconnect();
    final session = _session;
    await pending;
    if (session != _session || _remembered == null) return;
    await startAutoReconnect();
  }

  /// 首次配對:依 Service UUID 過濾掃描,結果列於 [scanResults]。
  Future<void> startPairingScan() async {
    final session = _beginFlow();
    _flow = CupFlow.pairing;
    _scanResults = const [];
    _message = null;
    _pairingScanActive = true;
    _setState(CupConnectionState.scanning);

    try {
      final results = await _ble.scanForDevices(timeout: pairingScanTimeout);
      if (session != _session) return;
      _scanResults = _sorted(results);
    } on BleException catch (e) {
      if (session != _session) return;
      _message = e.message;
    }
    _pairingScanActive = false;
    _setState(CupConnectionState.idle);
  }

  void _onScanResults(List<BleDeviceInfo> results) {
    if (_flow != CupFlow.pairing || !_pairingScanActive) return;
    _scanResults = _sorted(results);
    notifyListeners();
  }

  static List<BleDeviceInfo> _sorted(List<BleDeviceInfo> list) =>
      [...list]..sort((a, b) => b.rssi.compareTo(a.rssi));

  /// 自動重連:定向掃描記憶的 deviceId,找到後自動連線;15 秒找不到 → [CupConnectionState.notFound]。
  Future<void> startAutoReconnect() {
    _reconnectAttempts = 0;
    return _startAutoReconnect();
  }

  Future<void> _startAutoReconnect() async {
    final target = _remembered;
    if (target == null) return startPairingScan();

    final session = _beginFlow();
    _flow = CupFlow.reconnect;
    _setState(CupConnectionState.scanning);

    final List<BleDeviceInfo> results;
    try {
      results = await _ble.scanForDevices(
        timeout: reconnectScanTimeout,
        deviceId: target.id,
      );
    } on BleException catch (e) {
      if (session != _session) return;
      _message = e.message;
      _setState(CupConnectionState.notFound);
      return;
    }
    if (session != _session) return;

    if (results.any((d) => d.deviceId == target.id)) {
      await _connect(target.id, target.name);
    } else {
      _message = '找不到「${_displayName(target.name)}」:水杯可能在休眠,'
          '拿起杯子就會自動重新連線';
      _setState(CupConnectionState.notFound);
    }
  }

  /// 切換到已配對的 [device]:記憶為目前水杯並走自動重連流程。
  Future<void> reconnectTo(RememberedDevice device) async {
    final session = _beginFlow();
    _clearLink();
    _message = null;
    _remembered = device;
    _flow = CupFlow.reconnect;
    _setState(CupConnectionState.scanning);
    await _safeDisconnect();
    await _store.save(device);
    if (session != _session) return;
    await startAutoReconnect();
  }

  // ---------------------------------------------------------------- 連線

  /// 首次配對:使用者從清單選擇裝置。
  Future<void> connectTo(BleDeviceInfo device) =>
      _connect(device.deviceId, device.deviceName);

  Future<void> _connect(String deviceId, String name) async {
    final session = _beginFlow();
    if (_logDeviceId != deviceId) {
      // 接收紀錄只屬於單一水杯,換杯時重新計數。
      _log.clear();
      _receivedCount = 0;
      _logDeviceId = deviceId;
      _clearReadings();
    }
    _deviceId = deviceId;
    _deviceName = name;
    _linkUp = false;
    _message = null;
    _deviceStatus = null;
    _setState(CupConnectionState.connecting);

    try {
      await _ble.connect(deviceId);
      if (session != _session) return;
      _linkUp = true;
      _setState(CupConnectionState.serviceDiscovered);

      await _ble.writeTimeSync(DateTime.now().millisecondsSinceEpoch ~/ 1000);
      if (session != _session) return;

      try {
        _deviceStatus = await _ble.readDeviceStatus();
      } on BleException catch (e) {
        // 狀態讀取失敗不影響連線,之後的 Notify 仍會更新。
        debugPrint('[Cup] 讀取 Device Status 失敗:$e');
      }
      if (session != _session) return;

      final remembered = RememberedDevice(id: deviceId, name: name);
      await _store.save(remembered);
      if (session != _session) return;
      _remembered = remembered;
      _reconnectAttempts = 0;
      _setState(CupConnectionState.ready);
    } catch (e) {
      if (session != _session) return;
      await _onConnectFailed(deviceId, e);
    }
  }

  Future<void> _onConnectFailed(String deviceId, Object error) async {
    final wasRemembered = _remembered?.id == deviceId;
    _beginFlow();
    _clearLink();
    unawaited(_safeDisconnect());

    if (wasRemembered && ++_reconnectAttempts < maxReconnectAttempts) {
      _message = '連線失敗,重試中($_reconnectAttempts/$maxReconnectAttempts)…';
      await _startAutoReconnect();
      return;
    }
    _message = '連線失敗:${error is BleException ? error.message : error}';
    _setState(_flow == CupFlow.reconnect
        ? CupConnectionState.notFound
        : CupConnectionState.idle);
  }

  void _onBleState(BleConnectionState s) {
    if (s == BleConnectionState.connected &&
        _state == CupConnectionState.connecting) {
      _setState(CupConnectionState.connected);
      return;
    }
    if (s != BleConnectionState.disconnected || !_linkUp) return;

    // 意外斷線(主動斷線會先清除 _linkUp,不會走到這裡)。
    final deviceId = _deviceId!;
    if (_state != CupConnectionState.ready) {
      // 尚未 Ready 就斷線,視同連線失敗,計入重試次數。
      unawaited(_onConnectFailed(deviceId, '裝置在初始化期間斷線'));
      return;
    }
    _clearLink();
    if (_remembered?.id == deviceId) {
      _message = '連線中斷,正在重新連線…';
      unawaited(startAutoReconnect());
    } else {
      _beginFlow();
      _message = '連線中斷';
      _setState(CupConnectionState.idle);
    }
  }

  /// 使用者主動斷線 → 回到 Idle,不自動重連。
  Future<void> disconnect() async {
    _beginFlow();
    _clearLink();
    _scanResults = const [];
    _message = null;
    _setState(CupConnectionState.idle);
    await _safeDisconnect();
  }

  /// 忘記此裝置:斷線、清除本地記憶,回到 Idle。
  Future<void> forgetDevice() async {
    _beginFlow();
    _clearLink();
    _remembered = null;
    _scanResults = const [];
    _message = null;
    _log.clear();
    _receivedCount = 0;
    _clearReadings();
    _flow = CupFlow.pairing;
    _setState(CupConnectionState.idle);
    await _safeDisconnect();
    await _store.clear();
  }

  // ---------------------------------------------------------------- 資料

  void _onData(CupDataPacket packet) {
    if (!_linkUp) return;
    final now = DateTime.now();
    _packets.add(packet);
    switch (packet) {
      case AttitudePacket():
        // 即時資料(約每秒 5 次):只保留最新值,不計數、不記錄、不回 ACK。
        _latestAttitude = packet;
        _latestAttitudeAt = now;
        notifyListeners();
        return;
      case WaterPacket():
        _latestWater = packet;
        _latestWaterAt = now;
      case PosePacket():
        _latestPose = packet;
        _latestPoseAt = now;
      case StatePacket():
        // 狀態沒變(休眠中每 10 秒的 keepalive、訂閱時的重送):只更新時間並回 ACK,
        // 不寫進接收紀錄,避免紀錄被「休眠中」洗版。只有「進入休眠」「已喚醒」會記下來。
        final repeat = _latestState?.activity == packet.activity;
        _latestState = packet;
        _latestStateAt = now;
        if (repeat) {
          notifyListeners();
          unawaited(_ble.writeAck().catchError((Object e) {
            debugPrint('[Cup] ACK 寫入失敗:$e');
          }));
          return;
        }
      case DrinkEventPacket():
        // 韌體事件:不回 1-byte ACK。IntakeRecorder 把事件存進資料庫(或確認是重複)
        // 之後才呼叫 [ackDrinkEvent] 回 3-byte ACK;先 ACK 的話韌體會把事件從 flash
        // 刪掉,萬一還沒存好(寫入失敗、連線還在初始化)這筆就永遠不見了。
        _receivedCount++;
        _log.add(ReceivedPacket(packet, now, acked: false));
        if (_log.length > maxLogEntries) _log.removeAt(0);
        notifyListeners();
        return;
      case DummyDataPacket() || RawPacket() || UnknownPacket():
        break;
    }
    _receivedCount++;
    _log.add(ReceivedPacket(packet, now, acked: false));
    if (_log.length > maxLogEntries) _log.removeAt(0);
    notifyListeners();

    // TODO: 傳輸失敗重傳/離線緩衝機制(規格書 §8)。
    final session = _session;
    _ble.writeAck().then((_) {
      if (session != _session) return;
      final idx = _log.indexWhere((e) => identical(e.packet, packet));
      if (idx >= 0) {
        _log[idx] = ReceivedPacket(packet, _log[idx].receivedAt, acked: true);
        notifyListeners();
      }
    }).catchError((Object e) {
      debugPrint('[Cup] ACK 寫入失敗:$e');
    });
  }

  /// 確認一筆 DRINK_EVENT:寫入 3-byte ACK `[0x07, seq 低 8 bits, seq 高 3 bits]`,
  /// 韌體收到才從 flash 刪除。重複收到的事件也要呼叫(韌體沒收到上一次的 ACK)。
  ///
  /// 回傳是否寫入成功;已斷線或寫入失敗回傳 false(不丟例外),韌體會重送。
  Future<bool> ackDrinkEvent(DrinkEventPacket packet) async {
    if (!_linkUp) return false;
    final session = _session;
    try {
      await _ble.writeDrinkEventAck(packet.seq);
    } on BleException catch (e) {
      debugPrint('[Cup] DRINK_EVENT seq ${packet.seq} 的 ACK 寫入失敗:$e');
      return false;
    }
    if (session != _session) return true;
    final idx = _log.indexWhere((e) => identical(e.packet, packet) && !e.acked);
    if (idx >= 0) {
      _log[idx] = ReceivedPacket(packet, _log[idx].receivedAt, acked: true);
      notifyListeners();
    }
    return true;
  }

  void _onStatus(DeviceStatus status) {
    if (!_linkUp) return;
    _deviceStatus = status;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 工具

  /// 開始新流程:使先前流程的非同步延續失效並停止掃描。
  int _beginFlow() {
    final session = ++_session;
    _retryTimer?.cancel(); // 任何新流程(含使用者操作)都取消背景重試
    _retryTimer = null;
    _pairingScanActive = false;
    unawaited(_ble.stopScan().catchError((Object _) {}));
    return session;
  }

  void _clearLink() {
    _linkUp = false;
    _deviceId = null;
    _deviceName = null;
    _deviceStatus = null;
    // 即時姿態角與休眠狀態只對目前連線有意義,斷線即清除。
    _clearAttitude();
    _clearState();
  }

  void _clearReadings() {
    _latestWater = null;
    _latestWaterAt = null;
    _latestPose = null;
    _latestPoseAt = null;
    _clearAttitude();
    _clearState();
  }

  void _clearAttitude() {
    _latestAttitude = null;
    _latestAttitudeAt = null;
  }

  void _clearState() {
    _latestState = null;
    _latestStateAt = null;
  }

  Future<void> _safeDisconnect() async {
    try {
      await _ble.disconnect();
    } catch (e) {
      debugPrint('[Cup] disconnect 失敗:$e');
    }
  }

  void _setState(CupConnectionState s) {
    if (_disposed) return;
    _state = s;
    if (s == CupConnectionState.notFound) _scheduleBackgroundRetry();
    notifyListeners();
  }

  /// notFound 且有記憶的水杯 → [backgroundRetryInterval] 後自動再定向掃描一次。
  /// 水杯休眠時會一直重複,直到找到、使用者改做其他操作或 dispose。
  void _scheduleBackgroundRetry() {
    _retryTimer?.cancel();
    if (_remembered == null) return;
    _retryTimer = Timer(backgroundRetryInterval, () {
      _retryTimer = null;
      if (_disposed ||
          _state != CupConnectionState.notFound ||
          _remembered == null) {
        return;
      }
      unawaited(startAutoReconnect());
    });
  }

  static String _displayName(String name) => name.isEmpty ? '智慧水杯' : name;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _retryTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_packets.close());
    unawaited(_safeDisconnect());
    super.dispose();
  }
}
