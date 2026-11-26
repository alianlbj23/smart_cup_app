import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/update_manager.dart';
import 'theme.dart';

/// 「設定」頁的「軟體更新」:目前版本、檢查更新、下載並安裝。
///
/// 不能自行安裝的平台(iOS / macOS),或新版沒有這個平台的安裝檔時,改成提供
/// 下載頁的連結讓使用者複製。
class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key, required this.updates});

  final UpdateManager updates;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '軟體更新',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('目前版本 ${updates.currentVersion}', style: mutedSmall),
            ..._status(),
            const SizedBox(height: 12),
            ..._actions(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _status() {
    final info = updates.available;
    final error = updates.error;
    return [
      if (info != null) ...[
        const SizedBox(height: 12),
        Text(
          '有新版本 ${info.version}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.teal,
          ),
        ),
      ] else if (updates.phase == UpdatePhase.upToDate) ...[
        const SizedBox(height: 12),
        const Text('已是最新版本'),
      ],
      if (updates.phase == UpdatePhase.checking) ...[
        const SizedBox(height: 12),
        const Text('正在檢查更新…', style: mutedSmall),
      ],
      if (updates.phase == UpdatePhase.downloading) ...[
        const SizedBox(height: 12),
        LinearProgressIndicator(value: updates.progress),
        const SizedBox(height: 4),
        Text(
          '下載中 ${((updates.progress ?? 0) * 100).floor()}%',
          style: mutedSmall,
        ),
      ],
      if (updates.phase == UpdatePhase.installing) ...[
        const SizedBox(height: 12),
        const Text('正在安裝…', style: mutedSmall),
      ],
      if (error != null && updates.phase == UpdatePhase.failed) ...[
        const SizedBox(height: 12),
        Text(error, style: const TextStyle(color: AppColors.red)),
      ],
    ];
  }

  List<Widget> _actions(BuildContext context) {
    // 下載、安裝中不顯示按鈕(進度在上面)。
    if (updates.phase == UpdatePhase.downloading ||
        updates.phase == UpdatePhase.installing) {
      return const [];
    }
    final info = updates.available;
    final style = OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    if (info == null) {
      return [
        OutlinedButton.icon(
          onPressed: updates.busy ? null : updates.check,
          icon: const Icon(Icons.refresh),
          label: const Text('檢查更新'),
          style: style,
        ),
      ];
    }
    if (updates.canInstall) {
      return [
        FilledButton.icon(
          onPressed: updates.busy ? null : updates.install,
          icon: const Icon(Icons.system_update_alt),
          label: const Text('下載並安裝'),
        ),
        const SizedBox(height: 8),
        const Text('安裝新版不會刪除這台裝置上的紀錄。', style: mutedSmall),
      ];
    }
    return [
      Text(
        updates.platform.canSelfInstall
            ? '這一版沒有這個平台的安裝檔,請到下載頁確認。'
            : '這個平台無法由 App 自行安裝新版,請複製連結,用瀏覽器開啟下載頁。',
        style: mutedSmall,
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          await Clipboard.setData(ClipboardData(text: '${info.pageUrl}'));
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('已複製下載連結')));
        },
        icon: const Icon(Icons.link),
        label: const Text('複製下載連結'),
        style: style,
      ),
    ];
  }
}
