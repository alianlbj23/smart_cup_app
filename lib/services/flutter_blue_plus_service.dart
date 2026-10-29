// 本檔是全專案唯一 import flutter_blue_plus 的地方。
// 更換 BLE 套件時,改寫(或以新檔取代)本檔並保留 createBleService() 即可。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_service.dart';
import 'cup_protocol.dart';

/// App 取得 [BleService] 實作的唯一入口(見 main.dart)。
BleService createBleService() => FlutterBluePlusService();

/// 以 flutter_blue_plus 實作的 [BleService]。
///
/// flutter_blue_plus 2.x 需在 connect 時宣告授權:目前為學校/非營利用途使用
/// [License.nonprofit];商業使用需購買商業授權或改用其他套件。
class FlutterBluePlusService implements BleService {
  FlutterBluePlusService();

  static const _connectTimeout = Duration(seconds: 10);

  static final _service = Guid(CupGatt.service);
  static final _timeSyncUuid = Guid(CupGatt.timeSync);
  static final _dataUuid = Guid(CupGatt.dataNotify);
  static final _ackUuid = Guid(CupGatt.ack);
  static final _statusUuid = Guid(CupGatt.deviceStatus);

  final _stateCtrl = StreamController<BleConnectionState>.broadcast();
  final _scanCtrl = StreamController<List<BleDeviceInfo>>.broadcast();
  final _dataCtrl = StreamController<CupDataPacket>.broadcast();
  final _statusCtrl = StreamController<DeviceStatus>.broadcast();

  BleConnectionState _state = BleConnectionState.idle;

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _linkUp = false;
  BluetoothCharacteristic? _timeSyncChar;
  BluetoothCharacteristic? _ackChar;
  BluetoothCharacteristic? _statusChar;

  int _scanGen = 0;
  Completer<void>? _scanDone;

  @override
  Stream<BleConnectionState> get connectionState => _stateCtrl.stream;

  @override
  Stream<List<BleDeviceInfo>> get scanResults => _scanCtrl.stream;

  @override
  Stream<CupDataPacket> get dataNotifications => _dataCtrl.stream;

  @override
  Stream<DeviceStatus> get deviceStatusUpdates => _statusCtrl.stream;

  // ---------------------------------------------------------------- 掃描

  @override
  Future<List<BleDeviceInfo>> scanForDevices({
    Duration timeout = const Duration(seconds: 15),
    String? deviceId,
  }) async {
    final gen = ++_scanGen;
    _completeScan();
    await _ensureBluetoothOn();

    final found = <String, BleDeviceInfo>{};
    final done = Completer<void>();
    _scanDone = done;

    final sub = FlutterBluePlus.onScanResults.listen((results) {
      if (gen != _scanGen) return;
      for (final r in results) {
        // 部分 Android 機型的硬體 Service 過濾器會漏放無關裝置,需再自行確認。
        if (deviceId == null &&
            !r.advertisementData.serviceUuids.contains(_service)) {
          continue;
        }
        final info = _toInfo(r);
        found[info.deviceId] = info;
      }
      _addTo(_scanCtrl, found.values.toList());
      if (deviceId != null && found.containsKey(deviceId)) _completeScan();
    }, onError: (Object e) {
      if (!done.isCompleted) {
        done.completeError(BleException(BleErrorCode.scanFailed, '$e'));
      }
    });

    try {
      // 定向掃描用 remoteId 過濾;flutter_blue_plus 的多個過濾條件是 OR,不可與 service 並用。
      await FlutterBluePlus.startScan(
        withServices: deviceId == null ? [_service] : const [],
        withRemoteIds: deviceId == null ? const [] : [deviceId],
      );
      if (_state == BleConnectionState.idle ||
          _state == BleConnectionState.disconnected) {
        _emit(BleConnectionState.scanning);
      }
      await done.future.timeout(timeout, onTimeout: () {});
    } on BleException {
      rethrow;
    } catch (e) {
      throw BleException(BleErrorCode.scanFailed, _describe(e));
    } finally {
      await sub.cancel();
      // 新的掃描已接手時,不可停掉它。
      if (gen == _scanGen) {
        _scanDone = null;
        await _stopPlatformScan();
        if (_state == BleConnectionState.scanning) {
          _emit(BleConnectionState.idle);
        }
      }
    }
    return found.values.toList();
  }

  @override
  Future<void> stopScan() async {
    _completeScan();
    await _stopPlatformScan();
  }

  void _completeScan() {
    final done = _scanDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<void> _stopPlatformScan() async {
    if (!FlutterBluePlus.isScanningNow) return;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('[BLE] stopScan 失敗:$e');
    }
  }

  Future<void> _ensureBluetoothOn() async {
    if (!await FlutterBluePlus.isSupported) {
      throw const BleException(BleErrorCode.unsupported, '此手機不支援藍牙 BLE');
    }
    if (!kIsWeb &&
        Platform.isAndroid &&
        FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        // 使用者拒絕開啟,交由下方逾時處理。
      }
    }
    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      throw const BleException(BleErrorCode.bluetoothOff, '請開啟藍牙後重試');
    }
  }

  static BleDeviceInfo _toInfo(ScanResult r) {
    final adv = r.advertisementData.advName;
    return BleDeviceInfo(
      deviceId: r.device.remoteId.str,
      deviceName: adv.isNotEmpty ? adv : r.device.platformName,
      rssi: r.rssi,
    );
  }

  // ---------------------------------------------------------------- 連線

  @override
  Future<void> connect(String deviceId) async {
    await stopScan();
    final previous = _device;
    if (previous != null && previous.remoteId.str != deviceId) {
      await _release(previous);
    }

    final device = BluetoothDevice.fromId(deviceId);
    _device = device;
    _linkUp = false;
    _clearChars();
    await _connSub?.cancel();
    _connSub = device.connectionState.listen((s) {
      if (!identical(_device, device)) return;
      if (s == BluetoothConnectionState.disconnected && _linkUp) {
        _linkUp = false;
        _clearChars();
        _emit(BleConnectionState.disconnected);
      }
    });
    _emit(BleConnectionState.connecting);

    try {
      await device.connect(license: License.nonprofit, timeout: _connectTimeout);
      _checkCurrent(device);
      _linkUp = true;
      _emit(BleConnectionState.connected);

      final services = await device.discoverServices();
      _checkCurrent(device);
      final service =
          services.where((s) => s.serviceUuid == _service).firstOrNull;
      if (service == null) {
        throw const BleException(
            BleErrorCode.serviceNotFound, '裝置上找不到智慧水杯 Service');
      }
      BluetoothCharacteristic find(Guid uuid) {
        final c = service.characteristics
            .where((c) => c.characteristicUuid == uuid)
            .firstOrNull;
        if (c == null) {
          throw BleException(
              BleErrorCode.serviceNotFound, '裝置上找不到 characteristic $uuid');
        }
        return c;
      }

      final timeSync = find(_timeSyncUuid);
      final data = find(_dataUuid);
      final ack = find(_ackUuid);
      final status = find(_statusUuid);

      device.cancelWhenDisconnected(data.onValueReceived.listen(_onDataRaw));
      await data.setNotifyValue(true);
      _checkCurrent(device);

      device
          .cancelWhenDisconnected(status.onValueReceived.listen(_onStatusRaw));
      if (status.properties.notify) await status.setNotifyValue(true);
      _checkCurrent(device);

      _timeSyncChar = timeSync;
      _ackChar = ack;
      _statusChar = status;
      _emit(BleConnectionState.ready);
    } catch (e) {
      if (identical(_device, device)) {
        _device = null;
        _linkUp = false;
        _clearChars();
        await _connSub?.cancel();
        _connSub = null;
        await _release(device);
        _emitNotConnected();
      }
      throw e is BleException
          ? e
          : BleException(BleErrorCode.connectionFailed, _describe(e));
    }
  }

  /// 連線途中被 [disconnect] 或新的 [connect] 取代時中止。
  void _checkCurrent(BluetoothDevice device) {
    if (!identical(_device, device)) {
      throw const BleException(BleErrorCode.connectionFailed, '連線已取消');
    }
  }

  @override
  Future<void> disconnect() async {
    final device = _device;
    _device = null;
    _linkUp = false;
    _clearChars();
    await _connSub?.cancel();
    _connSub = null;
    if (device != null) await _release(device);
    _emitNotConnected();
  }

  Future<void> _release(BluetoothDevice device) async {
    try {
      await device.disconnect(queue: false);
    } catch (e) {
      debugPrint('[BLE] disconnect 失敗:$e');
    }
  }

  void _clearChars() {
    _timeSyncChar = null;
    _ackChar = null;
    _statusChar = null;
  }

  // ---------------------------------------------------------------- 讀寫

  @override
  Future<void> writeTimeSync(int unixTimestamp) =>
      _write(_timeSyncChar, CupProtocol.encodeTimeSync(unixTimestamp));

  @override
  Future<void> writeAck() => _write(_ackChar, CupProtocol.encodeAck());

  @override
  Future<DeviceStatus> readDeviceStatus() async {
    final c = _requireReady(_statusChar);
    try {
      return CupProtocol.decodeDeviceStatus(await c.read());
    } on FormatException catch (e) {
      throw BleException(BleErrorCode.operationFailed, e.message);
    } catch (e) {
      throw BleException(BleErrorCode.operationFailed, _describe(e));
    }
  }

  Future<void> _write(BluetoothCharacteristic? c, List<int> value) async {
    final char = _requireReady(c);
    try {
      await char.write(value);
    } catch (e) {
      throw BleException(BleErrorCode.operationFailed, _describe(e));
    }
  }

  BluetoothCharacteristic _requireReady(BluetoothCharacteristic? c) {
    if (c == null || !_linkUp) {
      throw const BleException(BleErrorCode.notConnected, '裝置未連線');
    }
    return c;
  }

  void _onDataRaw(List<int> raw) {
    try {
      final packet = CupProtocol.decodeData(raw);
      if (packet is UnknownPacket) {
        debugPrint('[BLE] 未知的 message type 0x'
            '${packet.type.toRadixString(16)},value=${packet.value}');
      }
      _addTo(_dataCtrl, packet);
    } on FormatException catch (e) {
      debugPrint('[BLE] 忽略格式錯誤的資料:${e.message}');
    }
  }

  void _onStatusRaw(List<int> raw) {
    try {
      _addTo(_statusCtrl, CupProtocol.decodeDeviceStatus(raw));
    } on FormatException catch (e) {
      debugPrint('[BLE] 忽略格式錯誤的狀態:${e.message}');
    }
  }

  // ---------------------------------------------------------------- 工具

  /// 未連線時的狀態:掃描進行中則維持 scanning。
  void _emitNotConnected() => _emit(_scanDone != null
      ? BleConnectionState.scanning
      : BleConnectionState.idle);

  void _emit(BleConnectionState s) {
    _state = s;
    _addTo(_stateCtrl, s);
  }

  static void _addTo<T>(StreamController<T> ctrl, T value) {
    if (!ctrl.isClosed) ctrl.add(value);
  }

  static String _describe(Object e) =>
      e is FlutterBluePlusException ? (e.description ?? '$e') : '$e';

  @override
  void dispose() {
    _scanGen++;
    _completeScan();
    unawaited(_stopPlatformScan());
    final device = _device;
    _device = null;
    _connSub?.cancel();
    if (device != null) unawaited(_release(device));
    _stateCtrl.close();
    _scanCtrl.close();
    _dataCtrl.close();
    _statusCtrl.close();
  }
}
