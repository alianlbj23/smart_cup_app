import 'package:shared_preferences/shared_preferences.dart';

/// 已記憶的裝置(規格書 §6)。
class RememberedDevice {
  const RememberedDevice({required this.id, required this.name});

  /// iOS 為系統產生的 UUID,Android 為 MAC address。
  final String id;

  /// 顯示用名稱。
  final String name;
}

/// 裝置記憶儲存。
///
/// deviceId 並非機密資料,因此使用 shared_preferences;若之後需存放
/// 配對金鑰等敏感資料,可改以 flutter_secure_storage 實作同一介面。
class DeviceStore {
  static const _keyId = 'remembered_device_id';
  static const _keyName = 'remembered_device_name';

  Future<RememberedDevice?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keyId);
    if (id == null || id.isEmpty) return null;
    return RememberedDevice(id: id, name: prefs.getString(_keyName) ?? '');
  }

  Future<void> save(RememberedDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyId, device.id);
    await prefs.setString(_keyName, device.name);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyId);
    await prefs.remove(_keyName);
  }
}
