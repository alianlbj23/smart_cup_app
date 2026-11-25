/// BLE 通訊抽象層。
///
/// App 其餘部分(狀態管理、UI、DeviceStore)只依賴本檔定義的介面與型別,
/// 不得直接 import 任何 BLE 套件。更換 BLE 套件時只需提供新的
/// [BleService] 實作(目前為 `flutter_blue_plus_service.dart`)。
library;

import 'dart:math' as math;

/// 掃描到的裝置。
class BleDeviceInfo {
  const BleDeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
  });

  /// iOS 為系統產生的 UUID,Android 為 MAC address。
  final String deviceId;

  /// 廣播名稱,可能為空字串。
  final String deviceName;
  final int rssi;
}

/// BLE 連線層的狀態(與 UI 顯示用的狀態分開)。
enum BleConnectionState {
  /// 未連線、未掃描。
  idle,
  scanning,
  connecting,

  /// 鏈路已建立,正在探索服務/訂閱。
  connected,

  /// 服務探索完成且已訂閱 Data Notify,可讀寫。
  ready,

  /// 已建立的連線意外中斷(主動 [BleService.disconnect] 會回到 [idle])。
  disconnected,
}

/// Data Notify 封包(9-byte payload:type(1) + value(4) + timestamp(4))。
///
/// 韌體(https://github.com/alianlbj23/smart_cup_firmware ,ESP-IDF)的
/// `main/ble_gatt_svr.h` 定義各 message type 的 value 編碼;解碼在 `cup_protocol.dart`。
sealed class CupDataPacket {
  const CupDataPacket({required this.timestamp});

  /// 裝置端 Unix 秒數;TimeSync 前為裝置開機後秒數。
  final int timestamp;

  DateTime get time =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true)
          .toLocal();
}

/// type 0x01:遞增計數器,只在開機後感測基準建立前出現,App 忽略即可。
class DummyDataPacket extends CupDataPacket {
  const DummyDataPacket({required this.value, required super.timestamp});

  final int value;
}

/// type 0x02:水量。
class WaterPacket extends CupDataPacket {
  const WaterPacket({
    required this.fill25,
    required this.level,
    required super.timestamp,
  });

  /// 水量,25-bit 分數:0(空杯)..[fill25Max](滿杯)。
  final int fill25;

  /// 粗刻度 0..10。
  final int level;

  static const int maxLevel = 10;
  static const int fill25Bits = 25;
  static const int fill25Max = (1 << fill25Bits) - 1;

  /// 水量比例 0.0..1.0。
  double get fillFraction => fill25 / fill25Max;

  /// 水量百分比 0.0..100.0。
  double get fillPercent => fillFraction * 100;
}

/// type 0x03:濾波後的電容原始計數,僅供除錯與校正。
class RawPacket extends CupDataPacket {
  const RawPacket({required this.count, required super.timestamp});

  final int count;
}

/// 水杯姿態(type 0x04 的 bits 23..16)。
enum CupPose {
  unknown,
  upright,
  tilted,
  drinking,
  lying;

  static CupPose fromCode(int code) =>
      code >= 0 && code < CupPose.values.length
          ? CupPose.values[code]
          : CupPose.unknown;

  String get label => switch (this) {
        CupPose.unknown => '未知',
        CupPose.upright => '直立',
        CupPose.tilted => '傾斜',
        CupPose.drinking => '飲用中',
        CupPose.lying => '倒下',
      };
}

/// type 0x04:姿態分類,每秒一次且姿態改變時立即送出。
class PosePacket extends CupDataPacket {
  const PosePacket({
    required this.tiltDeciDegrees,
    required this.pose,
    required this.moving,
    required super.timestamp,
  });

  /// 相對直立的傾斜角,單位 0.1 度,0..1800。
  final int tiltDeciDegrees;
  final CupPose pose;
  final bool moving;

  double get tiltDegrees => tiltDeciDegrees / 10;
}

/// type 0x05:即時姿態角,約每秒 5 次。
///
/// 屬即時資料:App 不回 ACK、不寫入接收紀錄,只保留最新一筆。
/// 直立時 pitch 與 roll 皆約為 0。
class AttitudePacket extends CupDataPacket {
  const AttitudePacket({
    required this.pitchDeciDegrees,
    required this.rollDeciDegrees,
    required super.timestamp,
  });

  /// 角度上下限(0.1 度):±180.0°。
  static const int maxDeciDegrees = 1800;

  /// 前後傾斜,單位 0.1 度,-1800..1800;正 = 杯口往前(遠離觀看者)。
  final int pitchDeciDegrees;

  /// 左右傾斜,單位 0.1 度,-1800..1800;正 = 杯口往右倒。
  final int rollDeciDegrees;

  double get pitchDegrees => pitchDeciDegrees / 10;
  double get rollDegrees => rollDeciDegrees / 10;

  /// 相對直立的總傾斜角 0..180 度:acos(cos(pitch)·cos(roll))。
  double get tiltDegrees {
    const toRad = math.pi / 180;
    final c = math.cos(pitchDegrees * toRad) * math.cos(rollDegrees * toRad);
    return math.acos(c.clamp(-1.0, 1.0)) / toRad;
  }
}

/// 水杯活動狀態(type 0x06 的 bits 7..0)。
enum CupActivity {
  /// 活動中:WATER / POSE / ATTITUDE 照常即時推送。
  active,

  /// 休眠中(淺眠):BLE 連線保持,但不送 POSE / ATTITUDE,
  /// WATER 改為變化 ≥1% 時立即送、否則每 30 秒一次。
  dozing,

  /// 未定義的狀態代碼。
  unknown;

  static CupActivity fromCode(int code) => switch (code) {
        0 => CupActivity.active,
        1 => CupActivity.dozing,
        _ => CupActivity.unknown,
      };

  String get label => switch (this) {
        CupActivity.active => '活動中',
        CupActivity.dozing => '休眠中',
        CupActivity.unknown => '未知',
      };
}

/// type 0x06:水杯活動狀態(活動中 / 休眠中)。
///
/// 韌體在狀態改變時、App 訂閱 Data Notify 後立即送一次,休眠中每 10 秒再送一次
/// (keepalive)。App 回 ACK 並寫入接收紀錄。
class StatePacket extends CupDataPacket {
  const StatePacket({
    required this.activity,
    required this.secondsInState,
    required super.timestamp,
  });

  /// [secondsInState] 的上限(uint24)。
  static const int maxSecondsInState = 0xFFFFFF;

  final CupActivity activity;

  /// 進入目前狀態已經幾秒(韌體送出當下),0..[maxSecondsInState]。
  final int secondsInState;
}

/// 韌體事件的種類(type 0x07 的 bits 17..16)。
enum FirmwareEventKind {
  /// 喝水:水位下降。
  drink,

  /// 加水:水位上升。
  refill,

  /// 保留值(2、3),目前的韌體不會送。
  unknown;

  static FirmwareEventKind fromCode(int code) => switch (code) {
        0 => FirmwareEventKind.drink,
        1 => FirmwareEventKind.refill,
        _ => FirmwareEventKind.unknown,
      };

  String get label => switch (this) {
        FirmwareEventKind.drink => '喝水',
        FirmwareEventKind.refill => '加水',
        FirmwareEventKind.unknown => '未知事件',
      };
}

/// type 0x07:韌體偵測到的喝水/加水事件(韌體 0.3.0 起)。
///
/// 連線中即時送出,斷線時存在水杯的 flash、重新訂閱後補傳。App 把事件存進資料庫後
/// 要回 3-byte ACK(`[0x07, seq 低 8 bits, seq 高 3 bits]`),韌體收到才從 flash 刪除;
/// ACK 晚到時同一筆會重送,用 [dedupKey] 去重,重複收到也要再回 ACK。
///
/// [timestamp] 是事件「開始」的時間,不是送出的時間;[timeUnknown] 時為 0。
class DrinkEventPacket extends CupDataPacket {
  const DrinkEventPacket({
    required this.beforeHalfPercent,
    required this.afterHalfPercent,
    required this.kind,
    required this.sawDrinking,
    required this.tooLong,
    required this.timeUnknown,
    required this.seq,
    required super.timestamp,
  });

  /// 水位欄位的上限:200 = 100%(單位 0.5%)。
  static const int maxHalfPercent = 200;

  /// seq 的上限(11 bits,0..2047 循環)。
  static const int maxSeq = 0x7FF;

  /// 事件前的水位 A,單位 0.5%,0..[maxHalfPercent]。
  final int beforeHalfPercent;

  /// 事件後的水位 B,單位 0.5%,0..[maxHalfPercent]。
  final int afterHalfPercent;
  final FirmwareEventKind kind;

  /// 過程中出現過「飲用中」姿態。用吸管喝時為 false,一樣算喝水。
  final bool sawDrinking;

  /// 過程超過 10 分鐘。
  final bool tooLong;

  /// 時間不可信(對時前、上一次開機留下的事件):[timestamp] 為 0,
  /// App 改用收到的時間並記成「時間為估計」。
  final bool timeUnknown;

  /// 流水號 0..[maxSeq],ACK 用;清空 flash 後會從 0 重新開始。
  final int seq;

  /// 水位 A / B 的百分比 0.0..100.0。
  double get beforePercent => beforeHalfPercent / 2;
  double get afterPercent => afterHalfPercent / 2;

  /// 去重鍵:seq + 時間戳 + A/B。同一筆事件重送時完全相同(包含 [timeUnknown]
  /// 的事件:時間戳固定為 0,不受每次收到的時間影響)。
  String get dedupKey =>
      '$seq:$timestamp:$beforeHalfPercent:$afterHalfPercent';
}

/// 未知 message type:保留原始 value,不中斷資料流。
class UnknownPacket extends CupDataPacket {
  const UnknownPacket({
    required this.type,
    required this.value,
    required super.timestamp,
  });

  final int type;
  final int value;
}

/// 韌體版本(Device Status 的 Byte 1..3)。
class FirmwareVersion implements Comparable<FirmwareVersion> {
  const FirmwareVersion(this.major, this.minor, this.patch);

  /// 從這一版起由韌體偵測喝水/加水並送 DRINK_EVENT(0x07)。
  static const drinkEvents = FirmwareVersion(0, 3, 0);

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(FirmwareVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >=(FirmwareVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is FirmwareVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Device Status(格式見 `cup_protocol.dart`)。
class DeviceStatus {
  const DeviceStatus({
    required this.batteryPercent,
    this.firmwareVersion,
    this.bleAddress,
  });

  /// 電量 0..100 %;未知(韌體送 0xFF,例如沒接電池)時為 null。
  final int? batteryPercent;

  /// 韌體版本;沒有讀到 Device Status 時為 null。
  final FirmwareVersion? firmwareVersion;

  /// 水杯的 BLE 位址(大寫、冒號分隔,例如 `58:E6:C5:12:E0:CE`),韌體 0.4.0 起提供;
  /// 舊韌體為 null。iOS 拿不到 BLE 位址,只能靠這個當 `cup_hardware_id`。
  final String? bleAddress;

  bool get batteryKnown => batteryPercent != null;

  /// 韌體是否自己偵測喝水(版本 ≥ 0.3.0)。是的話 App 要關掉自己的偵測,否則重複計算。
  bool get firmwareDetectsDrinks {
    final v = firmwareVersion;
    return v != null && v >= FirmwareVersion.drinkEvents;
  }
}

enum BleErrorCode {
  unsupported,
  bluetoothOff,
  scanFailed,
  connectionFailed,

  /// 已連線但裝置上找不到智慧水杯 Service/Characteristic。
  serviceNotFound,
  notConnected,
  operationFailed,
}

/// [BleService] 所有方法失敗時丟出的例外,不夾帶套件專屬型別。
class BleException implements Exception {
  const BleException(this.code, this.message);

  final BleErrorCode code;
  final String message;

  @override
  String toString() => 'BleException(${code.name}): $message';
}

/// 智慧水杯 BLE 操作介面(單一裝置連線)。
abstract interface class BleService {
  /// 連線層狀態變化。
  Stream<BleConnectionState> get connectionState;

  /// 掃描期間的即時結果(累積清單),供配對畫面即時更新。
  Stream<List<BleDeviceInfo>> get scanResults;

  /// 掃描廣播智慧水杯 Service 的裝置,[timeout] 到期或 [stopScan] 後回傳結果。
  ///
  /// 指定 [deviceId] 時為定向掃描:只找該裝置,找到即提前結束。
  Future<List<BleDeviceInfo>> scanForDevices({
    Duration timeout = const Duration(seconds: 15),
    String? deviceId,
  });

  /// 提前結束進行中的掃描;沒有掃描時不做事。
  Future<void> stopScan();

  /// 連線、探索服務並訂閱 Data Notify;完成時狀態為 [BleConnectionState.ready]。
  Future<void> connect(String deviceId);

  /// 主動斷線(也會取消進行中的連線),之後狀態為 [BleConnectionState.idle]。
  /// 不影響進行中的掃描。
  Future<void> disconnect();

  Future<void> writeTimeSync(int unixTimestamp);

  Future<void> writeAck();

  /// 確認一筆 DRINK_EVENT(0x07):寫入 3-byte ACK,韌體收到才從 flash 刪除該事件。
  Future<void> writeDrinkEventAck(int seq);

  Stream<CupDataPacket> get dataNotifications;

  Future<DeviceStatus> readDeviceStatus();

  /// Device Status 的 Notify 與 read 結果。
  Stream<DeviceStatus> get deviceStatusUpdates;

  void dispose();
}
