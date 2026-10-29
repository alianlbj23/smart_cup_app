# smart_cup_app（智慧水杯）

透過 BLE 連線 ESP32-C6 智慧水杯，顯示水量、姿態與接收紀錄的 Flutter App。

- BLE：`flutter_blue_plus`（只在 [lib/services/flutter_blue_plus_service.dart](lib/services/flutter_blue_plus_service.dart) 使用）
- 本地儲存：`shared_preferences`
- 水杯韌體：[firmware/smart_cup_esp32c6/](firmware/smart_cup_esp32c6/)（Arduino sketch，另外燒錄，不在本文件範圍）

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

- App 目前只有一個水杯頁面。先打開水杯電源，按「配對水杯」，再從清單點選水杯；連線後會顯示電量、水量、姿態和接收紀錄。
- 配對過的水杯會被記住，下次開 App 會自動重連；不要用了可以按「忘記此水杯」。
- 執行中在終端機按 `r` 熱重載、`R` 重新啟動、`q` 結束。
- 看不到裝置的話，先執行 `flutter devices` 確認裝置有被偵測到。macOS 版目前還不能連水杯（見下方 [macOS](#macos只能在-macos-上編譯)）。

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

- ⚠️ **目前還沒開藍牙權限**：App Sandbox 底下要加 Bluetooth entitlement，不然掃描不到水杯。
  在 [DebugProfile.entitlements](macos/Runner/DebugProfile.entitlements) 和 [Release.entitlements](macos/Runner/Release.entitlements) 都加上：

  ```xml
  <key>com.apple.security.device.bluetooth</key>
  <true/>
  ```

  也可以在 Xcode 的 Runner → Signing & Capabilities → App Sandbox → Hardware 勾選 Bluetooth。
- 另外要在 `macos/Runner/Info.plist` 加上 `NSBluetoothAlwaysUsageDescription`，第一次啟動時系統才會詢問使用者。

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
| Windows | 已用 `flutter build windows --release` 編譯成功（2026-10-29） |
| Web | 已用 `flutter build web --release` 編譯成功（2026-10-29） |
| Android / iOS / macOS / Linux | 還沒在本機編譯驗證 |
