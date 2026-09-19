import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/main.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';

import 'fakes/fake_ble_service.dart';

void main() {
  testWidgets('未初始化時顯示配對畫面', (tester) async {
    final ble = FakeBleService();
    final manager = CupConnectionManager(ble: ble);
    addTearDown(() {
      manager.dispose();
      ble.dispose();
    });
    await tester.pumpWidget(SmartCupApp(manager: manager));

    expect(find.text('閒置'), findsOneWidget);
    expect(find.text('尚未找到裝置'), findsOneWidget);
    expect(find.text('重新掃描'), findsOneWidget);
  });
}
