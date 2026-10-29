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
  CupConnectionManager({required BleService ble, DeviceStore? store})
      : _ble = ble,
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

  /// 超過此時間沒收到 WATER 就視為過期(韌體每 1 秒送一次)。
  static const waterStaleAfter = Duration(seconds: 5);

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

  /// [BleService.connect] 已完成,之後的斷線才算「連線中斷」。
  bool _linkUp = false;
  int _reconnectAttempts = 0;
  int _session = 0;
  bool _disposed = false;

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

  /// 最近一筆水量;尚未收到或已換杯/斷線時為 null。
  WaterPacket? get latestWater => _latestWater;

  /// 收到 [latestWater] 的手機時間。
  DateTime? get latestWaterAt => _latestWaterAt;

  /// 最近一筆姿態;韌體尚未送出時為 null。
  PosePacket? get latestPose => _latestPose;
  DateTime? get latestPoseAt => _latestPoseAt;

  /// [latestWater] 是否已超過 [waterStaleAfter] 沒更新。
  bool isWaterStale(DateTime now) {
    final at = _latestWaterAt;
    return at == null || now.difference(at) > waterStaleAfter;
  }

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
      _message = '找不到「${_displayName(target.name)}」,請確認裝置已開機並在附近';
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
    _receivedCount++;
    switch (packet) {
      case WaterPacket():
        _latestWater = packet;
        _latestWaterAt = now;
      case PosePacket():
        _latestPose = packet;
        _latestPoseAt = now;
      case DummyDataPacket() || RawPacket() || UnknownPacket():
        break;
    }
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

  void _onStatus(DeviceStatus status) {
    if (!_linkUp) return;
    _deviceStatus = status;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 工具

  /// 開始新流程:使先前流程的非同步延續失效並停止掃描。
  int _beginFlow() {
    final session = ++_session;
    _pairingScanActive = false;
    unawaited(_ble.stopScan().catchError((Object _) {}));
    return session;
  }

  void _clearLink() {
    _linkUp = false;
    _deviceId = null;
    _deviceName = null;
    _deviceStatus = null;
  }

  void _clearReadings() {
    _latestWater = null;
    _latestWaterAt = null;
    _latestPose = null;
    _latestPoseAt = null;
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
    notifyListeners();
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
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_safeDisconnect());
    super.dispose();
  }
}
