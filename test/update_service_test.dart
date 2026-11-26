import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stut_food_intake_project/services/update_service.dart';

const _repo = 'owner/cup';
const _linuxAsset = 'smart_cup_app-linux-x64.tar.gz';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object?> _asset(String tag, String name, {int size = 1234}) => {
      'name': name,
      'size': size,
      'browser_download_url':
          'https://github.com/$_repo/releases/download/$tag/$name',
    };

/// GitHub `releases/latest` 的回應(只留 App 會讀的欄位)。
Map<String, Object?> _release(
  String tag, {
  List<Map<String, Object?>>? assets,
  bool draft = false,
  bool prerelease = false,
  Object? body = '修正問題',
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'html_url': 'https://github.com/$_repo/releases/tag/$tag',
      'body': body,
      'assets': assets ??
          [
            _asset(tag, 'smart_cup_app-android.apk'),
            _asset(tag, _linuxAsset),
            _asset(tag, 'smart_cup_app-windows-x64.zip'),
          ],
    };

TypeMatcher<UpdateException> _updateError(String code) =>
    isA<UpdateException>().having((e) => e.code, 'code', code);

void main() {
  late List<http.Request> requests;

  UpdateService service(
    FutureOr<http.Response> Function(http.Request r) handler, {
    String currentVersion = '1.1.0',
    UpdatePlatform platform = UpdatePlatform.linux,
    Duration timeout = const Duration(seconds: 20),
  }) =>
      UpdateService(
        client: MockClient((r) async {
          requests.add(r);
          return handler(r);
        }),
        repo: _repo,
        currentVersion: currentVersion,
        platform: platform,
        timeout: timeout,
      );

  setUp(() => requests = []);

  group('版本號', () {
    test('有沒有 v 開頭都能解析', () {
      expect(AppVersion.tryParse('v1.2.3'), AppVersion.tryParse('1.2.3'));
      expect(AppVersion.tryParse('1.2.3').toString(), '1.2.3');
    });

    test('逐段以數字比較,不是字串比較', () {
      final v = AppVersion.tryParse;
      expect(v('1.10.0')!.compareTo(v('1.9.9')!), greaterThan(0));
      expect(v('2.0.0')!.compareTo(v('1.99.99')!), greaterThan(0));
      expect(v('1.1.0')!.compareTo(v('1.1.1')!), lessThan(0));
      expect(v('1.1.0')!.compareTo(v('v1.1.0')!), 0);
    });

    test('格式不對回傳 null', () {
      for (final bad in ['', '1.2', '1.2.3.4', 'abc', '1.2.3-beta', 'v', '1.-2.3',
          '1.2.x', '999999999999999999999.0.0']) {
        expect(AppVersion.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('檢查更新', () {
    test('有較新的版本:回傳版本、說明、發佈頁與這個平台的安裝檔', () async {
      final info = await service((_) => _json(_release('v1.2.0'))).check();

      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(),
          'https://api.github.com/repos/owner/cup/releases/latest');
      expect(info, isNotNull);
      expect(info!.version, '1.2.0');
      expect(info.notes, '修正問題');
      expect(info.pageUrl.toString(),
          'https://github.com/owner/cup/releases/tag/v1.2.0');
      expect(info.asset!.name, _linuxAsset);
      expect(info.asset!.size, 1234);
      expect(info.asset!.url.toString(),
          'https://github.com/owner/cup/releases/download/v1.2.0/$_linuxAsset');
    });

    test('每個平台拿到自己的安裝檔', () async {
      final info = await service((_) => _json(_release('v1.2.0')),
              platform: UpdatePlatform.windows)
          .check();
      expect(info!.asset!.name, 'smart_cup_app-windows-x64.zip');
    });

    test('版本相同或較舊:沒有更新', () async {
      expect(await service((_) => _json(_release('v1.1.0'))).check(), isNull);
      expect(await service((_) => _json(_release('v1.0.9'))).check(), isNull);
    });

    test('還沒有任何 release(404):沒有更新', () async {
      final info =
          await service((_) => _json({'message': 'Not Found'}, 404)).check();
      expect(info, isNull);
    });

    test('草稿或預先發行版不算', () async {
      expect(
          await service((_) => _json(_release('v1.2.0', draft: true))).check(),
          isNull);
      expect(
          await service((_) => _json(_release('v1.2.0', prerelease: true)))
              .check(),
          isNull);
    });

    test('新版沒有這個平台的安裝檔:仍回報有新版,asset 為 null', () async {
      final info = await service((_) => _json(_release('v1.2.0')),
              platform: UpdatePlatform.macos)
          .check();
      expect(info!.version, '1.2.0');
      expect(info.asset, isNull);
    });

    test('說明不是字串時當成空字串', () async {
      final info =
          await service((_) => _json(_release('v1.2.0', body: null))).check();
      expect(info!.notes, '');
    });

    test('安裝檔的下載網址不在這個 repo 的 release 底下:拒絕', () async {
      for (final url in [
        'https://evil.test/owner/cup/releases/download/v1.2.0/$_linuxAsset',
        'http://github.com/owner/cup/releases/download/v1.2.0/$_linuxAsset',
        'https://github.com/other/repo/releases/download/v1.2.0/$_linuxAsset',
        'https://github.com/owner/cup/releases/download/v1.2.0/../x/$_linuxAsset',
      ]) {
        final release = _release('v1.2.0', assets: [
          {'name': _linuxAsset, 'size': 10, 'browser_download_url': url},
        ]);
        await expectLater(service((_) => _json(release)).check(),
            throwsA(_updateError(UpdateException.badResponse)),
            reason: url);
      }
    });

    test('安裝檔大小不合理:拒絕', () async {
      for (final size in [0, -1, 600 * 1024 * 1024, '12']) {
        final release = _release('v1.2.0', assets: [
          {..._asset('v1.2.0', _linuxAsset), 'size': size},
        ]);
        await expectLater(service((_) => _json(release)).check(),
            throwsA(_updateError(UpdateException.badResponse)),
            reason: '$size');
      }
    });

    test('回應不是預期的格式:BAD_RESPONSE', () async {
      final bodies = <Object>[
        [1, 2],
        {'tag_name': 5},
        {'tag_name': 'latest', 'assets': []},
        {..._release('v1.2.0'), 'assets': 'x'},
        {..._release('v1.2.0'), 'html_url': 'https://evil.test/x'},
      ];
      for (final body in bodies) {
        await expectLater(service((_) => _json(body)).check(),
            throwsA(_updateError(UpdateException.badResponse)),
            reason: '$body');
      }
      await expectLater(
          service((_) => http.Response('<html>', 200)).check(),
          throwsA(_updateError(UpdateException.badResponse)));
    });

    test('伺服器錯誤或被限流:HTTP 錯誤', () async {
      for (final status in [403, 429, 500]) {
        await expectLater(
            service((_) => _json({'message': 'x'}, status)).check(),
            throwsA(_updateError(UpdateException.http)
                .having((e) => e.message, 'message', contains('$status'))),
            reason: '$status');
      }
    });

    test('逾時', () async {
      final never = Completer<http.Response>();
      await expectLater(
          service((_) => never.future,
                  timeout: const Duration(milliseconds: 20))
              .check(),
          throwsA(_updateError(UpdateException.timeout)));
    });

    test('連不上網路', () async {
      await expectLater(
          service((_) => throw const SocketException('no route')).check(),
          throwsA(_updateError(UpdateException.network)));
    });
  });

  group('下載安裝檔', () {
    late Directory dir;
    final asset = UpdateAsset(
      name: _linuxAsset,
      size: 6,
      url: Uri.parse(
          'https://github.com/$_repo/releases/download/v1.2.0/$_linuxAsset'),
    );

    UpdateService streaming(
      Stream<List<int>> Function() body, {
      int status = 200,
      Duration idleTimeout = const Duration(seconds: 30),
    }) =>
        UpdateService(
          client: MockClient.streaming((request, _) async {
            requests.add(http.Request(request.method, request.url));
            return http.StreamedResponse(body(), status);
          }),
          repo: _repo,
          currentVersion: '1.1.0',
          platform: UpdatePlatform.linux,
          downloadIdleTimeout: idleTimeout,
        );

    setUp(() => dir = Directory.systemTemp.createTempSync('update_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('存成安裝檔的檔名,內容完整,並回報進度', () async {
      final progress = <(int, int)>[];
      final file = await streaming(() => Stream.fromIterable([
            [1, 2, 3],
            [4, 5, 6],
          ])).download(asset, dir,
          onProgress: (received, total) => progress.add((received, total)));

      expect(requests.single.url, asset.url);
      expect(file.path, '${dir.path}${Platform.pathSeparator}$_linuxAsset');
      expect(file.readAsBytesSync(), [1, 2, 3, 4, 5, 6]);
      expect(progress, [(3, 6), (6, 6)]);
    });

    test('已經有同名的舊檔:覆蓋', () async {
      File('${dir.path}/$_linuxAsset').writeAsBytesSync(List.filled(50, 9));
      final file = await streaming(() => Stream.value([1, 2, 3, 4, 5, 6]))
          .download(asset, dir);
      expect(file.readAsBytesSync(), [1, 2, 3, 4, 5, 6]);
    });

    test('大小和 release 記載的不同:失敗,不留下檔案', () async {
      for (final bytes in [
        [1, 2, 3],
        [1, 2, 3, 4, 5, 6, 7, 8],
      ]) {
        await expectLater(
            streaming(() => Stream.value(bytes)).download(asset, dir),
            throwsA(_updateError(UpdateException.badDownload)));
        expect(dir.listSync(), isEmpty);
      }
    });

    test('下載回應不是 200:失敗,不留下檔案', () async {
      await expectLater(
          streaming(() => Stream.value([1, 2, 3, 4, 5, 6]), status: 404)
              .download(asset, dir),
          throwsA(_updateError(UpdateException.http)));
      expect(dir.listSync(), isEmpty);
    });

    test('下載中斷:失敗,不留下檔案', () async {
      await expectLater(
          streaming(() => Stream.fromFutures([
                Future.value([1, 2, 3]),
                Future.error(const SocketException('reset')),
              ])).download(asset, dir),
          throwsA(_updateError(UpdateException.network)));
      expect(dir.listSync(), isEmpty);
    });

    test('下載中途太久沒有資料:逾時,不留下檔案', () async {
      final stalled = StreamController<List<int>>();
      addTearDown(stalled.close);
      stalled.add([1, 2, 3]);
      await expectLater(
          streaming(() => stalled.stream,
                  idleTimeout: const Duration(milliseconds: 30))
              .download(asset, dir),
          throwsA(_updateError(UpdateException.timeout)));
      expect(dir.listSync(), isEmpty);
    });
  });
}
