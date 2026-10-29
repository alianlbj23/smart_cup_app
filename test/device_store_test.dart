import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/services/device_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('無記憶裝置時回傳 null', () async {
    expect(await DeviceStore().load(), isNull);
  });

  test('儲存、讀回、忘記裝置', () async {
    final store = DeviceStore();
    await store.save(
        const RememberedDevice(id: 'AA:BB:CC:DD:EE:FF', name: 'SmartCup'));

    final loaded = await store.load();
    expect(loaded?.id, 'AA:BB:CC:DD:EE:FF');
    expect(loaded?.name, 'SmartCup');

    await store.clear();
    expect(await store.load(), isNull);
  });
}
