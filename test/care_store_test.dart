import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/models/resident.dart';
import 'package:stut_food_intake_project/state/care_store.dart';

void main() {
  late CareStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = CareStore();
    await store.load();
  });

  test('首次啟動載入示範住民,之後從儲存還原', () async {
    expect(store.residents, isNotEmpty);
    final first = store.residents.first;
    await store.addIntake(first.id, 200);
    final total = first.totalOn(DateTime.now());

    final reloaded = CareStore();
    await reloaded.load();
    expect(reloaded.residents.length, store.residents.length);
    expect(reloaded.byId(first.id)!.totalOn(DateTime.now()), total);
  });

  test('登錄與復原飲水量', () async {
    final r = await store.addResident(
        name: '測試', room: 'T1', age: 80, goalMl: 1000);
    await store.addIntake(r.id, 150);
    await store.addIntake(r.id, 200);
    expect(r.totalOn(DateTime.now()), 350);

    await store.undoLastIntake(r.id);
    expect(r.totalOn(DateTime.now()), 150);
  });

  test('一個水杯只配對一位住民,改配時移除原配對', () async {
    final a = store.residents[0];
    final b = store.residents[1];
    await store.assignCup(a.id, 'AA:BB', 'SmartCup');
    expect(store.ownerOfCup('AA:BB')?.id, a.id);

    await store.assignCup(b.id, 'AA:BB', 'SmartCup');
    expect(a.hasCup, isFalse);
    expect(store.ownerOfCup('AA:BB')?.id, b.id);

    await store.unassignCup(b.id);
    expect(store.ownerOfCup('AA:BB'), isNull);
  });

  test('時程:06:00–20:00 線性,落後 15% 以上需要提醒', () {
    final noon = DateTime(2026, 10, 1, 13);
    expect(HydrationSchedule.expectedFraction(noon), 0.5);
    expect(HydrationSchedule.expectedFraction(DateTime(2026, 10, 1, 5)), 0);
    expect(HydrationSchedule.expectedFraction(DateTime(2026, 10, 1, 22)), 1);

    final r = Resident(id: 'x', name: 'x', room: '', age: 0, goalMl: 1000)
      ..intakes.add(IntakeEntry(time: DateTime(2026, 10, 1, 9), ml: 300));
    expect(HydrationSchedule.isBehind(r, noon), isTrue);
    expect(HydrationSchedule.lagMl(r, noon), 200);
    expect(HydrationSchedule.suggestedMl(r, noon), 100);

    r.intakes.add(IntakeEntry(time: DateTime(2026, 10, 1, 11), ml: 100));
    expect(HydrationSchedule.isBehind(r, noon), isFalse);
  });
}
