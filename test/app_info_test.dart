import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/app_info.dart';

void main() {
  test('appVersion 和 pubspec.yaml 的 version 一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*(\S+)$', multiLine: true).firstMatch(pubspec)![1]!;
    expect(version, '1.1.1+3');
    expect(appVersion, version.split('+').first);
  });
}
