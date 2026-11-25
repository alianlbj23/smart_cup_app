import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/services/care_api.dart';
import 'package:stut_food_intake_project/services/care_link_store.dart';

const _link = CareLink(
  token: 'cup_secret_token',
  linkId: 7,
  resident: CareResident(id: 12, label: '101-1', nameMasked: '王○明'),
  dailyGoalMl: 1500,
  goalEffectiveFrom: '2026-11-25',
  linkedAtMs: 1795600000000,
  serverUrl: 'https://care.test',
  cupLocalId: 'AA:BB',
  cupHardwareId: '58:E6:C5:12:E0:CE',
  cupName: 'SmartCup-E0CE',
);

void main() {
  late CareLinkStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = CareLinkStore();
  });

  test('伺服器位址:預設 https://foodintakesystem.com,可儲存', () async {
    expect(await store.loadServerUrl(), 'https://foodintakesystem.com');
    await store.saveServerUrl('https://care.test');
    expect(await CareLinkStore().loadServerUrl(), 'https://care.test');
  });

  test('install_id:首次產生 UUID v4,之後每次都一樣', () async {
    final id = await store.installId();
    expect(
        id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(await store.installId(), id);
    expect(await CareLinkStore().installId(), id);
  });

  test('連結:存取、清除;沒有目標時為 null', () async {
    expect(await store.loadLink(), isNull);
    await store.saveLink(_link);
    final loaded = (await CareLinkStore().loadLink())!;
    expect(loaded.token, 'cup_secret_token');
    expect(loaded.linkId, 7);
    expect(loaded.resident.display, '101-1 王○明');
    expect((loaded.dailyGoalMl, loaded.goalEffectiveFrom), (1500, '2026-11-25'));
    expect(loaded.linkedAtMs, 1795600000000);
    expect(loaded.serverUrl, 'https://care.test');
    expect((loaded.cupLocalId, loaded.cupHardwareId, loaded.cupName),
        ('AA:BB', '58:E6:C5:12:E0:CE', 'SmartCup-E0CE'));

    await store.saveLink(_link.withGoal(
        const CareGoal(dailyGoalMl: null, effectiveFrom: null)));
    final noGoal = (await store.loadLink())!;
    expect((noGoal.dailyGoalMl, noGoal.goalEffectiveFrom), (null, null));

    await store.clearLink();
    expect(await store.loadLink(), isNull);
    // 清除連結不會動到 install_id 與伺服器位址。
    final id = await store.installId();
    await store.saveLink(_link);
    await store.clearLink();
    expect(await store.installId(), id);
  });

  test('儲存的連結資料損毀或欄位不對 → 當成沒有連結', () async {
    for (final bad in [
      'not json',
      '[]',
      '{"token":"","linkId":7}',
      '{"token":"cup_x","linkId":"7"}',
    ]) {
      SharedPreferences.setMockInitialValues({'care_link_v1': bad});
      expect(await CareLinkStore().loadLink(), isNull, reason: bad);
    }
  });

  test('toString 不會洩漏 token', () {
    expect('$_link', isNot(contains('cup_secret_token')));
    expect('$_link', contains('101-1'));
  });

  test('提示訊息(連結失效的原因)可存取、清除', () async {
    expect(await store.loadNotice(), isNull);
    await store.saveNotice('連結已失效');
    expect(await CareLinkStore().loadNotice(), '連結已失效');
    await store.saveNotice(null);
    expect(await store.loadNotice(), isNull);
  });

  test('水杯最後出現的時間與韌體版本', () async {
    expect(await store.loadCupSeen(), (lastSeenAtMs: null, firmware: null));
    await store.saveCupSeen(lastSeenAtMs: 1795600000000, firmware: '0.4.0');
    expect(await CareLinkStore().loadCupSeen(),
        (lastSeenAtMs: 1795600000000, firmware: '0.4.0'));
    await store.clearLink();
    expect(await store.loadCupSeen(), (lastSeenAtMs: null, firmware: null),
        reason: '解除連結一併清掉');
  });
}
