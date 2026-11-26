import 'package:flutter/material.dart';

import '../state/disconnect_log.dart';
import 'theme.dart';

/// 設定頁的「連線紀錄」:每次意外斷線的時間、原因、當時 App 在前景或背景、水杯是否休眠。
/// 用來判斷斷線是手機、App 還是水杯造成的。
class DisconnectLogPanel extends StatelessWidget {
  const DisconnectLogPanel({super.key, required this.log});

  final DisconnectLog log;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _time(DateTime t) =>
      '${_two(t.month)}/${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final records = log.records;
        return Panel(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '連線紀錄',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (records.isNotEmpty)
                    TextButton(onPressed: log.clear, child: const Text('清除')),
                ],
              ),
              if (records.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('沒有斷線紀錄'),
                )
              else
                for (final r in records)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bluetooth_disabled),
                    title: Text('${_time(r.at)}  ${r.reasonText}'),
                    subtitle: Text(
                      [
                        r.deviceName ?? '水杯',
                        r.inBackground ? 'App 在背景' : 'App 在前景',
                        if (r.wasDozing) '水杯休眠中',
                      ].join(' · '),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
