# smart_cup_app（智慧水杯）

透過 BLE 連線 ESP32-C6 智慧水杯，顯示水量、姿態與接收紀錄的 Flutter App。

- BLE：`flutter_blue_plus`（只在 [lib/services/flutter_blue_plus_service.dart](lib/services/flutter_blue_plus_service.dart) 使用）
- 本地儲存：飲水紀錄用 SQLite（`drift`，見[飲水紀錄與統計](#飲水紀錄與統計)）；記住的水杯用 `shared_preferences`
- 圖表：`fl_chart`
- 水杯韌體：[smart_cup_firmware](https://github.com/alianlbj23/smart_cup_firmware)（另一個 repo，見下方[水杯韌體](#水杯韌體)）

## 水杯韌體

水杯上跑的程式在另一個 repo：**[smart_cup_firmware](https://github.com/alianlbj23/smart_cup_firmware)**（ESP-IDF v6.1，XIAO ESP32-C6）。這個 App 只負責連線和顯示，水位、姿態都是韌體算好再送過來的。

| 韌體負責 | 在韌體 repo 的哪裡 |
| --- | --- |
| 接線、燒錄步驟 | README 第 1、3 節 |
| 水位校正（空杯、滿杯） | README 第 4 節，校正值在 `main/cup_state.c` |
| BLE 協定、姿態判斷門檻 | README 第 5 節，程式在 `main/ble_gatt_svr.c` / `main/ble_gatt_svr.h` |
| 不用 App 測試 BLE | `tools/ble_check.py` |

使用順序：

1. 照韌體 repo 的 README 燒錄韌體。杯子**直立放在桌上**再開機，開機時的姿態會被當成「直立」的零點。
2. 韌體開始廣播 `SmartCup-XXXX`（XXXX 是 BLE 位址最後兩個 byte）。
3. 打開這個 App，按「配對水杯」，選 `SmartCup-XXXX`。

**改 BLE 協定時兩邊都要改**：App 的 [lib/services/cup_protocol.dart](lib/services/cup_protocol.dart)，以及韌體的 `main/ble_gatt_svr.c` / `.h`。

| App | 對應的韌體 | 說明 |
| --- | --- | --- |
| `main`（2026-11-19 起） | `main`，韌體版本 0.2.0 | 支援 WATER、POSE、ATTITUDE（0x05）、STATE（0x06，休眠中）與電量未知（0xFF）；韌體休眠時 BLE 連線不斷 |

## 快速試跑（不打包，直接執行）

裝好 Flutter 之後，在專案根目錄執行：

```bash
flutter pub get
flutter run -d windows     # Windows 電腦（可以連真的水杯）
flutter run -d chrome      # 任何電腦（用 Chrome 開啟）
flutter run -d macos       # Mac
flutter run -d linux       # Linux
flutter run                # 手機用 USB 接上電腦（Android 要開啟 USB 偵錯）
```

- App 下方有三個分頁：**水杯**、**飲水統計**、**設定**。先打開水杯電源，按「配對水杯」，再從清單點選水杯；連線後會顯示電量、水量、水杯姿態（側視圖、水平儀、傾斜角）和接收紀錄。
- 配對過的水杯會被記住，下次開 App 會自動重連；不要用了可以按「忘記此水杯」。
- 水杯靜止 30 秒會進入休眠（韌體功能，見下方[水杯韌體](#水杯韌體)），**藍牙連線不斷**，App 顯示「水杯休眠中」；拿起杯子馬上回到即時畫面。
- 如果水杯真的找不到（關機、太遠，或韌體開了深度睡眠），App 會顯示「找不到水杯」並**每 20 秒在背景重試**，水杯回來後自動連回去，不用按任何按鈕。
- 桌面版（Linux／Windows）關閉視窗前會先斷開藍牙。Linux 的 BlueZ 不會因為 App 結束就斷線，連線留著的話水杯不會廣播，下次開 App 會找不到。
- 電量顯示在連線區塊右上角：40% 以上綠色、20～39% 橘色、低於 20% 紅色；沒接電池時顯示「--」。
- 執行中在終端機按 `r` 熱重載、`R` 重新啟動、`q` 結束。
- 看不到裝置的話，先執行 `flutter devices` 確認裝置有被偵測到。

## 飲水紀錄與統計

### 喝水怎麼記錄

韌體只送「水位比例」（0..1），App 用 **水量 = 水位比例 × 水杯容量** 換算 mL（容量在「設定」改，預設 350 mL），再由水位與姿態判斷每一次喝水（[lib/state/drink_detector.dart](lib/state/drink_detector.dart)）：

1. 只相信「直立、靜止至少 3 秒」時的水位（取最近 5 筆的中位數）；傾斜、移動時的電容讀值直接丟掉。
2. 拿起前的穩定水位 A → 杯子被拿起（傾斜／飲用中／移動）→ 放回後重新穩定的水位 B。
3. A − B ≥ 10 mL 且中間有「飲用中」姿態 → **喝水**；沒有「飲用中」→ **待確認**（可能是倒掉，在統計頁按「確認是喝水」或「不是喝水」）；B − A ≥ 10 mL → **加水**（不計入飲水量；如果這次拿起時出現過「飲用中」，可能是喝了又裝水、喝的量被抵掉，標成待確認，在統計頁按「有喝，補記」補上喝了多少，或按「只是加水」）；變化小於 10 mL 視為雜訊。
4. 一次拿起超過 10 分鐘才放回，事件照記但標成待確認。
5. 斷線後**同一個水杯**重新連上，會拿斷線前的水位比較，期間的變化記成一筆（下降一律待確認，除非重連後看到「飲用中」）。

限制：**App 沒連線時不會記錄**；用吸管喝（杯子一直直立不動）不會被偵測到。這兩種都可以在統計頁「手動新增」補記。之後要讓韌體自己偵測並存起來、連上再補傳（第二階段）。

### 統計頁

- **日**：今日總量／目標、時間分布圖（上：累積水量階梯線＋理想進度虛線（06:00 → 20:00 達標）；下：每一次喝了多少），以及三個「集中還是平均」指標：
  - **時段覆蓋**：06–20 點切成 7 個 2 小時時段，有喝水的時段數（今天只算已經開始的時段）。
  - **最集中時段占比**：連續 2 小時內喝最多的量佔全天幾 %。
  - **最長未喝水間隔**：06–20 點之間最久沒喝水的時間（含 06:00 到第一次、最後一次到現在／20:00）。
  - 下方是當天每一筆紀錄，可以修改、刪除、確認。
- **週**（週一開始）／**月**：每日長條＋目標線，累積量、日平均（只算到今天）、達標天數。

### 資料存在哪裡

- 全部存在本機 SQLite（[lib/data/database.dart](lib/data/database.dart)），沒有伺服器。手機／桌面是 App 資料夾裡的 `smart_cup.sqlite`；Web 存在瀏覽器裡，清除瀏覽資料會不見，只適合展示。
- **解除安裝 App 會刪掉所有紀錄**，請定期在「設定 → 資料備份」匯出：
  - **匯出紀錄（CSV）**：可以用 Excel／Google 試算表打開。
  - **匯出備份檔**（JSON）／**從備份檔匯入**：換手機用。匯入是合併，不會刪掉現有紀錄，重複匯入同一個檔案不會重複；每日目標會改成備份檔裡的值。
- 資料表：`cups`（水杯、容量）、`drinkers`（飲用者、每日目標；單機版只有一位）、`intake_events`（每次喝水／加水／倒掉，UUID 主鍵、UTC 毫秒時間＋當地日期 `local_day`、軟刪除）。日／週／月累積都是查詢時即時計算，不另存統計表。
- 改了 `lib/data/database.dart` 的資料表之後要重新產生程式碼，並遞增 `schemaVersion`、寫 migration：

  ```bash
  dart run build_runner build
  ```

- Web 版需要 [web/sqlite3.wasm](web/sqlite3.wasm) 和 [web/drift_worker.js](web/drift_worker.js)，版本要和 `pubspec.lock` 的 `sqlite3`（3.5.2）、`drift`（2.35.4）一致；升級這兩個套件時要從它們的 GitHub release 重新下載。

## BLE 資料格式

GATT Service 與各 Characteristic 的 UUID 定義在 [lib/services/cup_protocol.dart](lib/services/cup_protocol.dart)，必須和韌體 `main/ble_gatt_svr.h` 一致。

**Data Notify**（ESP32 → App）固定 9 bytes：`type`(1) + `value`(uint32 LE, 4) + `timestamp`(uint32 LE, 4，Unix 秒)。

| type | 名稱 | 頻率 | value 內容 | App 處理 |
| --- | --- | --- | --- | --- |
| `0x02` | WATER | 1 次/秒；**休眠中**：水位變化 ≥1% 時立即送，否則每 30 秒 1 次 | bits 24..0 水量 25-bit 分數（0 空杯 .. 2^25-1 滿杯）；bits 28..25 粗刻度 0..10 | 回 ACK、記入接收紀錄 |
| `0x03` | RAW | 除錯用 | 濾波後電容計數 | 回 ACK、記入接收紀錄 |
| `0x04` | POSE | 1 次/秒，姿態改變時立即送；**休眠中不送** | bits 15..0 傾斜角（0.1°，0..1800）；bits 23..16 姿態（0 未知 / 1 直立 / 2 傾斜 / 3 飲用中 / 4 倒下）；bits 31..24 移動旗標（非 0 = 移動中） | 回 ACK、記入接收紀錄 |
| `0x05` | ATTITUDE | 約 5 次/秒；**休眠中不送** | bits 15..0 pitch、bits 31..16 roll，皆為 **int16 有號**、單位 0.1°、範圍 -1800..1800。roll 正 = 杯口往右倒；pitch 正 = 杯口往前（遠離觀看者）；直立時兩者約 0 | 即時資料：**不回 ACK、不記入接收紀錄、不計入已接收筆數**，只保留最新值；超過 2 秒沒更新視為過期 |
| `0x06` | STATE | 狀態改變時立即送；App 訂閱 Data Notify 後 1.5 秒送 1 次（休眠中會一起補送水位與最後的姿態）；休眠中每 10 秒 1 次（keepalive） | bits 7..0 狀態（0 活動中 / 1 休眠中，其他值當未知）；bits 31..8 進入目前狀態已經幾秒（uint24） | 回 ACK；只有狀態**改變**時記入接收紀錄（「水杯進入休眠」「水杯已喚醒」），keepalive 只回 ACK 不記錄。秒數 App 不顯示 |

總傾斜角由 App 計算：`tilt = acos(cos(pitch) · cos(roll))`，0..180°。

**休眠中（淺眠）**：水杯靜止一陣子會進入休眠，**BLE 連線保持不斷**，不會出現斷線或重新連線。

| 封包 | 活動中 | 休眠中 |
| --- | --- | --- |
| WATER `0x02` | 1 次/秒 | 水位變化 ≥1% 立即送，否則每 30 秒 1 次（杯子靜止，水位仍可信） |
| POSE `0x04` | 1 次/秒 | 不送 |
| ATTITUDE `0x05` | 約 5 次/秒 | 不送 |
| STATE `0x06` | 狀態改變、訂閱時 | 每 10 秒 1 次（keepalive，順便更新秒數） |
| Device Status | 照舊 | 照舊 |

拿起杯子 → 韌體送 STATE=0（活動中），接著恢復 WATER 每秒、POSE 每秒、ATTITUDE 每秒 5 次。

App 的休眠畫面（[lib/ui/doze_banner.dart](lib/ui/doze_banner.dart)，夜間靛藍色，不用警示的橘/紅色）：

- 連線面板和水位面板之間出現「水杯休眠中」橫幅：月亮圖示、「藍牙保持連線 · 拿起杯子就會喚醒」（不顯示已休眠多久）；進入/離開休眠時淡入淡出。
- 連線面板顯示「目前連線:已連線 · 休眠中」，藍牙圖示與電量照舊。
- 水位面板照常顯示最新水位（不變灰），副標題「休眠中 · 每 30 秒更新 · 更新於 HH:mm」。
- 姿態面板以柔和的灰靛色顯示最後的姿態，改成一個「休眠中」Chip，副標題「休眠中 · 拿起杯子後恢復即時姿態」。
- 收到最後一筆休眠 STATE 後超過 25 秒（約 3 次 keepalive）沒再收到，就不再當作休眠，回到一般的「資料過期」判斷。
- 收到 STATE=0（喚醒）後畫面回到即時顯示；過期判斷從喚醒那一刻起算，喚醒瞬間不會閃「資料過期」。

**Device Status**（Read / Notify）至少 4 bytes：

| Byte | 內容 |
| --- | --- |
| 0 | 電量 %（uint8，0..100）；**`0xFF` = 未知**（例如沒接電池），App 顯示「電量 --」 |
| 1..3 | 裝置端版本號（App 不使用） |

## 共通環境

| 項目 | 版本 |
| --- | --- |
| Flutter | 3.47.5（stable） |
| Dart | 3.13.x（`pubspec.yaml` 要求 `^3.13.3`） |

```bash
flutter doctor          # 確認目標平台的工具鏈都是 ✓
flutter pub get         # 安裝相依套件
flutter analyze         # 靜態檢查
flutter test            # 單元 / widget 測試
```

開發時用 `flutter devices` 列出裝置，再用 `flutter run -d <device-id>` 執行。

> 要接真的水杯，執行 App 的機器必須有藍牙硬體並開啟藍牙。

## 各平台編譯

| 平台 | 編譯主機 | 指令 | 輸出位置 |
| --- | --- | --- | --- |
| Android | Windows / macOS / Linux | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| iOS | macOS | `flutter build ipa --release` | `build/ios/ipa/` |
| macOS | macOS | `flutter build macos --release` | `build/macos/Build/Products/Release/` |
| Windows | Windows | `flutter build windows --release` | `build\windows\x64\runner\Release\` |
| Linux | Linux | `flutter build linux --release` | `build/linux/x64/release/bundle/` |
| Web | 任一 | `flutter build web --release` | `build/web/` |

### Android

**需要**：Android Studio（或 Android SDK command-line tools）、JDK 17。

```bash
flutter doctor --android-licenses   # 第一次使用要同意授權
flutter build apk --release         # 產生 APK
flutter build appbundle --release   # 上架 Google Play 用的 AAB
```

- 藍牙權限（`BLUETOOTH_SCAN`、`BLUETOOTH_CONNECT`，以及 Android 11 以下需要的 `ACCESS_FINE_LOCATION`）已經寫在 [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)。
- 目前 release 版本用 **debug key 簽章**（[android/app/build.gradle.kts](android/app/build.gradle.kts) 的 `signingConfig`），只適合內部測試。要上架的話，請先設定正式的 keystore，keystore 和密碼不要 commit。
- `applicationId` 目前是 `com.example.stut_food_intake_project`，上架前要改掉。

### iOS（只能在 macOS 上編譯）

**需要**：Xcode、Apple Developer 帳號（實機安裝和發佈時要用）。

```bash
open ios/Runner.xcworkspace      # 第一次：在 Signing & Capabilities 選擇 Team
flutter run -d <iPhone-id>       # 實機測試（模擬器沒有藍牙，無法連水杯）
flutter build ipa --release      # 產生 IPA
```

- 最低支援 iOS 15.0。
- 藍牙使用說明 `NSBluetoothAlwaysUsageDescription` 已經寫在 [ios/Runner/Info.plist](ios/Runner/Info.plist)。
- iOS 會給每台裝置一個隨機 UUID 當 `remoteId`，跟 Android 上看到的 MAC 位址不同，所以水杯的配對紀錄不能跨平台共用。

### macOS（只能在 macOS 上編譯）

**需要**：Xcode。

```bash
flutter build macos --release
```

- 藍牙權限已設定好（2026-11-19）：
  - [DebugProfile.entitlements](macos/Runner/DebugProfile.entitlements) 和 [Release.entitlements](macos/Runner/Release.entitlements) 有 `com.apple.security.device.bluetooth`（App Sandbox 底下沒有它就掃描不到水杯）。
  - [Info.plist](macos/Runner/Info.plist) 有 `NSBluetoothAlwaysUsageDescription`，第一次啟動時系統會詢問是否允許使用藍牙，要按「允許」。不小心按了拒絕的話，到「系統設定 → 隱私權與安全性 → 藍牙」打開。
- 最低支援 macOS 12.0。
- 和 iOS 一樣，macOS 給每台裝置的 `remoteId` 是系統產生的 UUID，不是 MAC 位址，配對紀錄不能和其他平台共用。
- 自己用的話 `flutter run -d macos` 或 `flutter build macos --release` 就好；要給別人用，需要在 Xcode 設定簽章（Signing & Capabilities 選 Team），沒簽章的 App 在別台 Mac 上會被 Gatekeeper 擋下。

### Windows

**需要**：Visual Studio 2022 以上，並安裝「使用 C++ 的桌面開發」工作負載。

```bash
flutter build windows --release
```

- 輸出資料夾 `build\windows\x64\runner\Release\` 整個複製出去就能執行（exe 加上 `data\` 和 DLL）。
- BLE 透過 `flutter_blue_plus_winrt` 使用 Windows 內建的藍牙堆疊，需要 Windows 10 以上並開啟藍牙。

### Linux

**需要**：Flutter 的 Linux 桌面工具鏈和 BlueZ。以 Ubuntu / Debian 為例：

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev bluez
flutter build linux --release
```

- 執行時透過 D-Bus 使用 BlueZ，`bluetooth` 服務要先啟動（`systemctl status bluetooth`）。
- 輸出資料夾 `build/linux/x64/release/bundle/` 要整個一起帶走。

### Web

```bash
flutter build web --release
```

- Web Bluetooth 只能在 Chromium 系瀏覽器（Chrome、Edge）使用，而且網頁必須透過 **HTTPS 或 `localhost`** 開啟。Firefox 和 Safari 不支援。
- 瀏覽器規定掃描（選擇裝置）一定要由使用者點擊觸發，所以 App 啟動時無法自動重連記憶的水杯，每次都要重新選擇。
- 本機預覽：`flutter run -d chrome`。

## 驗證紀錄

| 平台 | 狀態 |
| --- | --- |
| Linux | 已用 `flutter build linux --release` 編譯成功，並連實際水杯驗證水位、姿態、電量顯示、90 秒連續傳輸、休眠中連線不斷（休眠中連上 1.4 秒內顯示完整畫面、晃杯子恢復即時）、關閉視窗會斷開藍牙（2026-11-19） |
| Windows | 已用 `flutter build windows --release` 編譯成功（2026-10-29） |
| Web | 已用 `flutter build web --release` 編譯成功（2026-11-23，含飲水紀錄 SQLite），尚未在瀏覽器實際執行 |
| macOS | 已加上藍牙權限設定（entitlement、Info.plist），還沒在 Mac 上編譯驗證 |
| Android / iOS | 還沒在本機編譯驗證 |
