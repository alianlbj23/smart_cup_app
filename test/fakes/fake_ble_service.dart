import 'dart:async';

import 'package:stut_food_intake_project/services/ble_service.dart';

/// 可由測試控制的 [BleService] 假實作。
class FakeBleService implements BleService {
  final _stateCtrl = StreamController<BleConnectionState>.broadcast();
  final _scanCtrl = StreamController<List<BleDeviceInfo>>.broadcast();
  final _dataCtrl = StreamController<CupDataPacket>.broadcast();
  final _statusCtrl = StreamController<DeviceStatus>.broadcast();

  /// 掃描時會「看到」的裝置。
  List<BleDeviceInfo> devicesInRange = [];

  /// 設定後 connect() 一律以此例外失敗。
  BleException? connectError;

  String? connectedId;
  final List<String> connectCalls = [];
  final List<String?> scanCalls = [];
  final List<int> timeSyncs = [];
  int ackCount = 0;

  /// readDeviceStatus() 回傳的狀態。
  DeviceStatus deviceStatus = const DeviceStatus(batteryPercent: 80);
  int disconnectCount = 0;

  bool _scanning = false;

  bool get isConnected => connectedId != null;

  @override
  Stream<BleConnectionState> get connectionState => _stateCtrl.stream;

  @override
  Stream<List<BleDeviceInfo>> get scanResults => _scanCtrl.stream;

  @override
  Stream<CupDataPacket> get dataNotifications => _dataCtrl.stream;

  @override
  Stream<DeviceStatus> get deviceStatusUpdates => _statusCtrl.stream;

  @override
  Future<List<BleDeviceInfo>> scanForDevices({
    Duration timeout = const Duration(seconds: 15),
    String? deviceId,
  }) async {
    scanCalls.add(deviceId);
    _scanning = true;
    _stateCtrl.add(BleConnectionState.scanning);
    await Future<void>.delayed(Duration.zero);
    final found = devicesInRange
        .where((d) => deviceId == null || d.deviceId == deviceId)
        .toList();
    _scanCtrl.add(found);
    _scanning = false;
    return found;
  }

  @override
  Future<void> stopScan() async {
    _scanning = false;
  }

  @override
  Future<void> connect(String deviceId) async {
    connectCalls.add(deviceId);
    _stateCtrl.add(BleConnectionState.connecting);
    await Future<void>.delayed(Duration.zero);
    final error = connectError;
    if (error != null) {
      _stateCtrl.add(BleConnectionState.idle);
      throw error;
    }
    connectedId = deviceId;
    _stateCtrl.add(BleConnectionState.connected);
    _stateCtrl.add(BleConnectionState.ready);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    connectedId = null;
    _stateCtrl.add(
        _scanning ? BleConnectionState.scanning : BleConnectionState.idle);
  }

  @override
  Future<void> writeTimeSync(int unixTimestamp) async {
    _requireConnected();
    timeSyncs.add(unixTimestamp);
  }

  @override
  Future<void> writeAck() async {
    _requireConnected();
    ackCount++;
  }

  @override
  Future<DeviceStatus> readDeviceStatus() async {
    _requireConnected();
    return deviceStatus;
  }

  void _requireConnected() {
    if (!isConnected) {
      throw const BleException(BleErrorCode.notConnected, '裝置未連線');
    }
  }

  /// 模擬裝置推送一筆 dummy Data Notify。
  void pushData(int value, int timestamp) =>
      _dataCtrl.add(DummyDataPacket(value: value, timestamp: timestamp));

  /// 模擬裝置推送任一種 Data Notify。
  void pushPacket(CupDataPacket packet) => _dataCtrl.add(packet);

  /// 模擬裝置推送 Device Status Notify。
  void pushStatus(DeviceStatus status) => _statusCtrl.add(status);

  /// 模擬意外斷線。
  void dropLink() {
    connectedId = null;
    _stateCtrl.add(BleConnectionState.disconnected);
  }

  @override
  void dispose() {
    _stateCtrl.close();
    _scanCtrl.close();
    _dataCtrl.close();
    _statusCtrl.close();
  }
}
