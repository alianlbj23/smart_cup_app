import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stut_food_intake_project/services/update_installer.dart';
import 'package:stut_food_intake_project/services/update_service.dart';

/// 假的 GitHub:`releases/latest` 與安裝檔下載。App 目前的版本固定當成 1.1.0。
class FakeUpdateServer {
  static const repo = 'owner/cup';

  /// 最新 release 的版本號(不含 `v`)。
  String latest = '1.1.0';
  String notes = '修正問題';

  /// `releases/latest` 與下載的 HTTP 狀態碼。
  int checkStatus = 200;
  int downloadStatus = 200;

  /// release 裡有哪些安裝檔;null = 每個平台都有。
  List<String>? assetNames;
  List<int> assetBytes = [1, 2, 3, 4];

  int checks = 0;
  int downloads = 0;

  Future<http.Response> handle(http.Request request) async {
    final tag = 'v$latest';
    if (request.url.host == 'api.github.com') {
      checks++;
      if (checkStatus != 200) {
        return http.Response(jsonEncode({'message': 'error'}), checkStatus);
      }
      final names =
          assetNames ?? [for (final p in UpdatePlatform.values) p.assetName];
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'tag_name': tag,
          'draft': false,
          'prerelease': false,
          'html_url': 'https://github.com/$repo/releases/tag/$tag',
          'body': notes,
          'assets': [
            for (final name in names)
              {
                'name': name,
                'size': assetBytes.length,
                'browser_download_url':
                    'https://github.com/$repo/releases/download/$tag/$name',
              },
          ],
        })),
        200,
      );
    }
    downloads++;
    return http.Response.bytes(
        downloadStatus == 200 ? assetBytes : const [], downloadStatus);
  }

  UpdateService service({UpdatePlatform platform = UpdatePlatform.linux}) =>
      UpdateService(
        client: MockClient(handle),
        repo: repo,
        currentVersion: '1.1.0',
        platform: platform,
      );
}

/// 假的安裝器:記下收到的安裝檔;[error] 不為 null 時丟出它。
class FakeUpdateInstaller implements UpdateInstaller {
  final installed = <File>[];
  UpdateException? error;

  @override
  Future<void> install(File package) async {
    final e = error;
    if (e != null) throw e;
    installed.add(package);
  }
}
