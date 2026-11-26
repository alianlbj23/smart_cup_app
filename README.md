# smart_cup_app（智慧水杯）

透過 BLE 連線 ESP32-C6 智慧水杯，顯示水量、姿態、飲水紀錄與統計的 Flutter App（版本 1.1.2）；可以連結照護系統，把飲水紀錄傳給照護人員。

- BLE：`flutter_blue_plus`（只在 [lib/services/flutter_blue_plus_service.dart](lib/services/flutter_blue_plus_service.dart) 使用）
- 本地儲存：飲水紀錄用 SQLite（`drift`，見[飲水紀錄與統計](#飲水紀錄與統計)）；記住的水杯用 `shared_preferences`
- 圖表：`fl_chart`
- 照護系統（Server）：HTTPS／JSON，`http`（只在 [lib/services/care_api.dart](lib/services/care_api.dart) 使用），見[連結照護系統](#連結照護系統)；三邊的介面寫在 food_intake 專案的 `docs/smart-cup/CONTRACT.md`
- 自動更新：App 會向這個 repo 的 [GitHub Releases](https://github.com/alianlbj23/smart_cup_app/releases) 查詢新版，見[發佈與自動更新](#發佈與自動更新)
- 水杯韌體：[smart_cup_firmware](https://github.com/alianlbj23/smart_cup_firmware)（另一個 repo，見下方[水杯韌體](#水杯韌體)）

## 水杯韌體

水杯上跑的程式在另一個 repo：**[smart_cup_firmware](https://github.com/alianlbj23/smart_cup_firmware)**（ESP-IDF v6.1，XIAO ESP32-C6）。這個 App 只負責連線、顯示與記錄，水位、姿態都是韌體算好再送過來的；韌體 0.3.0 起，喝水／加水事件也由韌體偵測。

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
| 1.0.0（2026-11-19 起） | 0.2.0 | 支援 WATER、POSE、ATTITUDE（0x05）、STATE（0x06，休眠中）與電量未知（0xFF）；韌體休眠時 BLE 連線不斷。喝水由 App 自己偵測（`DrinkDetector`） |
| 1.1.0（2026-11-25 起） | 0.3.0 | 加上 DRINK_EVENT（0x07）：喝水／加水由韌體偵測，斷線時存在水杯的 flash、連上後補傳；App 回 3-byte ACK 並去重，關掉自己的偵測 |
| 1.1.0 | 0.4.0 | Device Status 多 6 bytes BLE 位址（連結照護系統時當 `cup_hardware_id`）；直立不動時水位下降（用吸管喝）也會產生喝水事件，休眠中也會 |

App 1.1.0 同時支援以上三個韌體版本：看 Device Status 的版本號決定由誰偵測喝水（≥ 0.3.0 韌體；< 0.3.0 App）。舊的 App（1.0.0）接 0.3.0 以上的韌體時不認得 0x07，事件會留在水杯的 flash 裡，而且 App 自己的偵測仍在跑。

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

- App 下方有三個分頁：**水杯**、**飲水統計**、**設定**。先打開水杯電源，按「配對水杯」，再從清單點選水杯；連線後會顯示電量、水量和水杯姿態（側視圖、水平儀、傾斜角）。
- 配對過的水杯會被記住，下次開 App 會自動重連；不要用了可以按「忘記此水杯」。
- 水杯靜止 30 秒會進入休眠（韌體功能，見下方[水杯韌體](#水杯韌體)），**藍牙連線不斷**，App 顯示「水杯休眠中」；拿起杯子馬上回到即時畫面。
- 如果水杯真的找不到（關機、太遠，或韌體開了深度睡眠），App 會顯示「找不到水杯」並**每 20 秒在背景重試**，水杯回來後自動連回去，不用按任何按鈕。
- 桌面版（Linux／Windows）關閉視窗前會先斷開藍牙。Linux 的 BlueZ 不會因為 App 結束就斷線，連線留著的話水杯不會廣播，下次開 App 會找不到。
- 電量顯示在連線區塊右上角：40% 以上綠色、20～39% 橘色、低於 20% 紅色；沒接電池時顯示「--」。
- 執行中在終端機按 `r` 熱重載、`R` 重新啟動、`q` 結束。
- 看不到裝置的話，先執行 `flutter devices` 確認裝置有被偵測到。

## 飲水紀錄與統計

### 喝水怎麼記錄

韌體只有「水位比例」，沒有 mL 的概念；App 用 **水量 = 水位比例 × 水杯容量** 換算 mL（容量在「設定」改，預設 350 mL，存在 `cups.capacity_ml`）。事件由誰偵測看韌體版本（[lib/state/intake_recorder.dart](lib/state/intake_recorder.dart)）：

**韌體 ≥ 0.3.0：由韌體偵測（DRINK_EVENT `0x07`）**。App 關掉自己的偵測，否則同一口水會算兩次。

1. 收到 `0x07` → mL = |A − B| ÷ 100 × 該水杯的容量（四捨五入），寫進 `intake_events`，來源 `firmware`。
2. 種類 0 = 喝水，**一律計入（`status = ok`）**，不論有沒有「飲用中」姿態（`saw_drinking`）、過程是否超過 10 分鐘（`too_long`）：住民可能用吸管喝，杯子一直直立不動。種類 1 = 加水，照樣記錄、不計入飲水量。
3. 時間用韌體的時間戳（事件開始的時間）。`time_unknown`（對時前、上一次開機留下的事件）或時間戳明顯不合理（早於 2024 年、比手機時間晚超過 10 分鐘）時，改用 App 收到的時間，並記下「時間為估計」（`intake_events.time_estimated`，統計頁的紀錄會標示）。
4. **先存好才回 ACK**：存進資料庫（或確認是重複的）之後才寫 3-byte ACK `[0x07, seq 低 8 bits, seq 高 3 bits]`，韌體收到才從 flash 刪除。寫入失敗、或連線還在初始化（還不知道容量）時不回，韌體會重送。
5. **去重**：同一個水杯、seq＋時間戳＋A／B 都相同就是同一筆（`intake_events.fw_key`，唯一索引 `idx_intake_fw`），不會產生第二筆，但每次都回 ACK。`time_unknown` 的事件時間戳固定是 0，所以每次收到的時間不同也認得出來。前後相接的事件（上一筆的 B = 下一筆的 A）seq 不同，每一筆都計入。使用者刪除的紀錄（軟刪除）被重送也不會復活。
6. 水杯沒連著 App 時事件存在水杯的 flash（最多 256 筆），下次連上補傳；休眠中也會送新的事件。

**韌體 < 0.3.0：由 App 偵測**（原本的行為，[lib/state/drink_detector.dart](lib/state/drink_detector.dart)），由水位與姿態判斷每一次喝水：

1. 只相信「直立、靜止至少 3 秒」時的水位（取最近 5 筆的中位數）；傾斜、移動時的電容讀值直接丟掉。
2. 拿起前的穩定水位 A → 杯子被拿起（傾斜／飲用中／移動）→ 放回後重新穩定的水位 B。
3. A − B ≥ 10 mL 且中間有「飲用中」姿態 → **喝水**；沒有「飲用中」→ **待確認**（可能是倒掉，在統計頁按「確認是喝水」或「不是喝水」）；B − A ≥ 10 mL → **加水**（不計入飲水量；如果這次拿起時出現過「飲用中」，可能是喝了又裝水、喝的量被抵掉，標成待確認，在統計頁按「有喝，補記」補上喝了多少，或按「只是加水」）；變化小於 10 mL 視為雜訊。
4. 一次拿起超過 10 分鐘才放回，事件照記但標成待確認。
5. 斷線後**同一個水杯**重新連上，會拿斷線前的水位比較，期間的變化記成一筆（下降一律待確認，除非重連後看到「飲用中」）。

舊韌體的限制：**App 沒連線時不會記錄**；用吸管喝（杯子一直直立不動）不會被偵測到。這兩種都可以在統計頁「手動新增」補記，或把韌體更新到 0.4.0。

### 統計頁

- **日**：今日總量／目標、時間分布圖（上：累積水量階梯線＋理想進度虛線（06:00 → 20:00 達標）；下：每一次喝了多少），以及三個「集中還是平均」指標：
  - **時段覆蓋**：06–20 點切成 7 個 2 小時時段，有喝水的時段數（今天只算已經開始的時段）。
  - **最集中時段占比**：連續 2 小時內喝最多的量佔全天幾 %。
  - **最長未喝水間隔**：06–20 點之間最久沒喝水的時間（含 06:00 到第一次、最後一次到現在／20:00）。
  - 下方是當天每一筆紀錄，可以修改、刪除、確認。
- **週**（週一開始）／**月**：每日長條＋目標線，累積量、日平均（只算到今天）、達標天數。
- **每日目標**：未連結照護系統時由使用者在「設定」修改（預設 1500 mL）。已連結時以照護系統為準、App 不能改；照護系統還沒設定目標時，統計頁顯示「照護系統尚未設定目標」，不畫目標線與理想進度、不算達成率與達標天數，**不會套用任何預設值**。

### 資料存在哪裡

- 紀錄存在本機 SQLite（[lib/data/database.dart](lib/data/database.dart)）。手機／桌面是 App 資料夾裡的 `smart_cup.sqlite`；Web 存在瀏覽器裡，清除瀏覽資料會不見，只適合展示。
- 連結照護系統之後，新的紀錄會**另外上傳一份**到 Server（見[連結照護系統](#連結照護系統)）；本機仍然是完整的一份，沒有網路時照常記錄、之後補傳。
- **解除安裝 App 會刪掉本機所有紀錄**，請定期在「設定 → 資料備份」匯出：
  - **匯出紀錄（CSV）**：可以用 Excel／Google 試算表打開。
  - **匯出備份檔**（JSON）／**從備份檔匯入**：換手機用。匯入是合併，不會刪掉現有紀錄，重複匯入同一個檔案不會重複；每日目標會改成備份檔裡的值（已連結照護系統時不會改）。匯入的紀錄不會上傳到照護系統。1.0.0 匯出的備份檔可以直接匯入。
- 資料表（`schemaVersion` 2）：
  - `cups`：水杯、容量、水杯自己回報的 BLE 位址（`ble_address`，韌體 0.4.0 起）。
  - `drinkers`：飲用者（一台裝置只有一位）、每日目標；`goal_from_server`／`server_goal_ml` 記錄目標是不是由照護系統設定（`server_goal_ml` 為 null = 照護系統尚未設定）。
  - `intake_events`：每次喝水／加水／倒掉。UUID 主鍵（上傳時就是 `client_event_id`）、UTC 毫秒時間＋當地日期 `local_day`、軟刪除。韌體事件另外有 `fw_key`（去重）、`fw_seq`、`saw_drinking`、`too_long`、`time_estimated`、事件前後的水位 %、當下的容量。同步狀態：`synced_at_ms`（上傳成功的時間，null = 還沒同步）、`sync_error`（被照護系統拒收的原因）、`sync_excluded`（不上傳）。
  - 日／週／月累積都是查詢時即時計算，不另存統計表。
- 1.0.0 的資料庫（schema 1）第一次用 1.1.0 開啟時會自動升級，舊紀錄保留（`test/database_migration_test.dart`）。
- 記住的水杯、照護系統的伺服器位址、`install_id`、連結資料（含 token）存在 `shared_preferences`（[lib/services/care_link_store.dart](lib/services/care_link_store.dart)）。
- 改了 `lib/data/database.dart` 的資料表之後要重新產生程式碼，並遞增 `schemaVersion`、寫 migration：

  ```bash
  dart run build_runner build --delete-conflicting-outputs
  ```

- Web 版需要 [web/sqlite3.wasm](web/sqlite3.wasm) 和 [web/drift_worker.js](web/drift_worker.js)，版本要和 `pubspec.lock` 的 `sqlite3`（3.5.2）、`drift`（2.35.4）一致；升級這兩個套件時要從它們的 GitHub release 重新下載。

## 連結照護系統

傳輸路徑是 **水杯 —BLE→ 手機 App —HTTPS→ Server**，沒有閘道器。App 這一端的程式：網路層 [lib/services/care_api.dart](lib/services/care_api.dart)、連結流程 [lib/state/care_link_manager.dart](lib/state/care_link_manager.dart)、背景同步 [lib/state/care_sync.dart](lib/state/care_sync.dart)、畫面 [lib/ui/care_link_panel.dart](lib/ui/care_link_panel.dart)／[lib/ui/care_link_page.dart](lib/ui/care_link_page.dart)。所有路徑都在 `/api/machine/` 底下，回應是 `{"success": true, "data": …}` 或 `{"success": false, "error": {"code", "message", "retryable"}}`；每個請求都有逾時（連線 10 秒、整體 20 秒）。

### 連結流程（「設定 → 照護系統」）

1. **伺服器位址**：預設 `https://foodintakesystem.com`，可以改（必須是 http／https 網址）。「測試連線」會打 `GET /api/machine/health/`，並在手機時間和伺服器差超過 5 分鐘時提醒。http 沒有加密，只適合內部網路測試，而且 Android／iOS 預設不允許 http。
2. 要先配對過水杯才能連結。按「連結照護系統」→ App 抓 `cup/residents/` → **選「我是誰」**（只顯示房號-床號與遮蔽後的姓名，例如 `101-1 王○明`）→ 確認後送出 `cup/link/start/`。
3. 畫面顯示**配對碼**、「等待照護人員在網頁按下確定」與倒數；App 依伺服器給的間隔輪詢 `cup/link/poll/`。照護人員（營養師以上）在網頁上核對配對碼、按「確定綁定」。
   - 被拒絕（`DENIED`）、過期（`EXPIRED`，或 App 自己數到時間）：停止輪詢並說明原因，可以重新選擇。
   - `SLOW_DOWN`：輪詢間隔加 5 秒。暫時連不上（網路、5xx）：顯示提示，繼續輪詢到過期為止。
   - 按「取消」或離開畫面：停止輪詢。
4. 核准後 App 存下 token、住民資訊與每日目標，畫面顯示「已連結：101-1 王○明」與每日目標。
5. **解除連結**只會清掉這台裝置上的 token；網頁端也要請照護人員解除綁定，否則網頁仍會顯示已綁定。
6. Server 回 401 `TOKEN_EXPIRED`（token 無效，或已在網頁端解除綁定）時，App 自動清掉 token、回到「尚未連結」，在設定頁說明原因；本機紀錄保留。

送給 Server 的識別資料：

| 欄位 | 內容 |
| --- | --- |
| `install_id` | 這個 App 安裝的 UUID v4，第一次需要時產生後存起來 |
| `cup_hardware_id` | 韌體 0.4.0：Device Status 的 BLE 位址（例如 `58:E6:C5:12:E0:CE`；連線中直接用，沒連線時用之前記在 `cups.ble_address` 的）。舊韌體：平台給的 remoteId（Android／Linux／Windows 是 MAC 位址；iOS／macOS 是系統產生的 UUID）。必須符合 `[A-Za-z0-9:._-]{1,64}` |
| `cup_name` | 水杯的廣播名稱（最多 64 字） |
| `platform`、`app_version` | `android`／`ios`／`linux`／`windows`／`macos`／`web`；版本來自 [lib/app_info.dart](lib/app_info.dart)（要和 `pubspec.yaml` 一致，有測試檢查） |

**token 存放的限制**：這個 App 沒有安全儲存套件（Keychain／Keystore），token 存在 `shared_preferences`，沒有額外加密。token 不會出現在 log 或錯誤訊息裡。

### 上傳紀錄（`cup/events/`）

- 已連結時，新增、修改、刪除（軟刪除）、確認的紀錄都會上傳：`client_event_id` = `intake_events.id`、`updated_at` = `updatedAtMs`（每次修改一定變大），Server 以較新的版本為準。一批最多 200 筆，Server 回成功才標成已同步（`synced_at_ms`）。
- 什麼時候試：App 啟動、連結成功、每次有新事件（等 2 秒把連續的變更併成一次）、每 5 分鐘，以及「設定」頁的「立即同步」。
- 失敗時看 `retryable`：
  - 可重試（網路、逾時、5xx、429）：紀錄留在佇列，30 秒後重試，之後每次加倍（60、120、240 秒），最多 5 分鐘。
  - `INVALID_EVENT`、`CLIENT_EVENT_ID_TAKEN`（某一筆紀錄的問題，Server 只回整批失敗）：把這一批對半拆開再送，找出修不了的那一筆，把原因記在 `sync_error`、移出佇列並記 log，其他紀錄照常上傳；設定頁會顯示有幾筆被拒收。那一筆之後被使用者修改會重新上傳。（例：手動新增最多可以輸入 3000 mL，但照護系統只接受 0–2000 mL。）
  - 其他不可重試的錯誤：這一輪放棄並記 log，紀錄留著，下一次（5 分鐘或有新事件）再試。
- **哪些紀錄會上傳**：
  - 只上傳已連結的那個水杯的紀錄，以及手動輸入的紀錄。連著別的水杯時設定頁會提醒「它的紀錄不會上傳」；要換水杯請先解除連結再重新連結。
  - Server 會把收到的事件都算在 token 所屬的住民身上，所以**第一次連結、或連結到和上次不同的住民時，本機原有的紀錄全部標成不上傳**（`sync_excluded`），之後再修改也不會上傳。重新連結到**同一位**住民（例如 token 失效後重新連結）時，還沒上傳的紀錄會照常補傳。
  - 從備份檔匯入的紀錄不上傳。

### 狀態回報與每日目標（`cup/status/`、`cup/me/`）

- App 啟動、連結成功、每 5 分鐘、以及已連結的水杯連上／斷線時，回報：水杯是否連線、最後看到水杯的時間、電量、韌體版本、水位、還沒上傳的筆數。不知道的值送 `null`。
- 回應裡的每日目標會套用到本機（`drinkers.daily_goal_ml`）。**目標以 Server 為準**：Server 回 `null` 時 App 顯示「照護系統尚未設定目標」，不套用預設值。App 啟動時另外用 `cup/me/` 更新住民資訊（例如換床位）；狀態回報的回應也帶住民目前的資料，所以 App 一直開著沒重啟時，最慢 5 分鐘也會跟上換房、換床（舊版 Server 沒有這個欄位就不動）。
- 尚未連結時，App 完全不連網。

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
| `0x07` | DRINK_EVENT（韌體 0.3.0 起） | 每筆事件；連線中即時送，斷線時存 flash、重新訂閱後補傳；休眠中也會送 | bits 7..0 事件前水位 A、bits 15..8 事件後水位 B（單位 0.5%，0..200）；bits 17..16 種類（0 喝水 / 1 加水，其他保留）；bit 18 `saw_drinking`；bit 19 `too_long`；bit 20 `time_unknown`；bits 31..21 seq（11 bits，0..2047）。**timestamp 是事件開始的時間**，`time_unknown` 時為 0 | 記入接收紀錄；**存進資料庫後**回 3-byte ACK（見下）；重複收到也回 ACK、不重複記錄。詳見[喝水怎麼記錄](#喝水怎麼記錄) |

**ACK**（App → 水杯，Write）：一般封包回 1 byte `[0x01]`（只計數）。DRINK_EVENT 回 3 bytes `[0x07, seq & 0xFF, (seq >> 8) & 0x07]`，韌體收到 seq 相符的 ACK 才把事件從 flash 刪除；保留的種類（2、3）App 不記錄但照樣回 ACK，免得卡住後面的事件。

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

**Device Status**（Read / Notify）至少 4 bytes，韌體 0.4.0 起 10 bytes（Read 與 Notify 都一樣；位址還沒準備好時韌體只回 4 bytes）：

| Byte | 內容 |
| --- | --- |
| 0 | 電量 %（uint8，0..100）；**`0xFF` = 未知**（例如沒接電池），App 顯示「電量 --」 |
| 1..3 | 韌體版本 major、minor、patch。≥ 0.3.0 時 App 關掉自己的喝水偵測，事件只來自韌體 |
| 4..9 | 水杯的 BLE 位址 6 bytes，**顯示順序**（最高位元組在前，不用反轉）。長度 ≥ 10 時 App 組成大寫、冒號分隔的字串（`58 E6 C5 12 E0 CE` → `58:E6:C5:12:E0:CE`），記在 `cups.ble_address`，連結照護系統時當 `cup_hardware_id`（iOS 拿不到 BLE 位址，只能靠這個）。全 0 或全 FF 視為沒有 |

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

- 藍牙權限（`BLUETOOTH_SCAN`、`BLUETOOTH_CONNECT`，以及 Android 11 以下需要的 `ACCESS_FINE_LOCATION`）與連結照護系統用的 `INTERNET` 權限已經寫在 [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)。
- Android 預設不允許 http（明文）連線，照護系統的伺服器位址要用 https。
- 簽章（[android/app/build.gradle.kts](android/app/build.gradle.kts) 的 `signingConfig`）：有 `android/key.properties` 時用裡面指定的正式 keystore；沒有時退回 **debug key**，只適合自己測試（debug key 每台機器不同，裝不上別台機器編出來的版本）。用 `bash tool/android_keystore.sh` 建立 keystore，見[發佈與自動更新](#發佈與自動更新)。keystore 和 `key.properties` 已被 [android/.gitignore](android/.gitignore) 排除，不要 commit。
- 自動更新需要 `REQUEST_INSTALL_PACKAGES` 權限與一個 `FileProvider`（只開放快取資料夾裡的 `smart_cup_update/`），都已經寫在 [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)。
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
- 連結照護系統走 https，`Info.plist` 不需要額外設定（沒有加 ATS 例外，所以 http 的伺服器位址在 iOS 上連不上）。
- iOS 拿不到水杯的 BLE 位址：韌體 0.4.0 起由 Device Status 提供，舊韌體的 `cup_hardware_id` 會是系統產生的 UUID。
- iOS 會給每台裝置一個隨機 UUID 當 `remoteId`，跟 Android 上看到的 MAC 位址不同，所以水杯的配對紀錄不能跨平台共用。

### macOS（只能在 macOS 上編譯）

**需要**：Xcode。

```bash
flutter build macos --release
```

- 藍牙權限已設定好（2026-11-19）：
  - [DebugProfile.entitlements](macos/Runner/DebugProfile.entitlements) 和 [Release.entitlements](macos/Runner/Release.entitlements) 有 `com.apple.security.device.bluetooth`（App Sandbox 底下沒有它就掃描不到水杯）。
  - [Info.plist](macos/Runner/Info.plist) 有 `NSBluetoothAlwaysUsageDescription`，第一次啟動時系統會詢問是否允許使用藍牙，要按「允許」。不小心按了拒絕的話，到「系統設定 → 隱私權與安全性 → 藍牙」打開。
- **連結照護系統在 macOS 上還不能用**：App Sandbox 底下對外連線需要 `com.apple.security.network.client` entitlement，目前兩個 entitlements 檔都還沒加（要加請一併在 Mac 上驗證）。
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

## 發佈與自動更新

### 發佈（GitHub Actions）

[.github/workflows/build-release.yml](.github/workflows/build-release.yml) 在每次推到 `main` 時：

1. 跑 `flutter analyze` 和 `flutter test`。
2. 編譯 Linux、Windows、macOS、Android、iOS 五個平台（PR 也會編譯，但不發佈）。
3. 讀 `pubspec.yaml` 的 `version`。**還沒有對應的 tag（例如 `v1.2.0`）時**，自動建立 tag 和 GitHub Release，附上下表的檔案和 `SHA256SUMS.txt`；release 的說明是上一版之後的 commit 標題。tag 已經存在就只編譯、不發佈。

**要發新版**：把 `pubspec.yaml` 的 `version`、[lib/app_info.dart](lib/app_info.dart) 的 `appVersion`、[test/app_info_test.dart](test/app_info_test.dart) 裡的版本一起調高，推到 `main`。不用自己打 tag。

| 平台 | Release 裡的檔案 | 怎麼安裝 |
| --- | --- | --- |
| Android | `smart_cup_app-android.apk` | 直接安裝（第一次要允許安裝未知來源的應用程式） |
| Windows | `smart_cup_app-windows-x64.zip` | 解壓縮到自己有寫入權限的資料夾（不要放 `Program Files`），執行裡面的 exe |
| Linux | `smart_cup_app-linux-x64.tar.gz` | 解壓縮到自己有寫入權限的資料夾，執行 `stut_food_intake_project` |
| macOS | `smart_cup_app-macos.zip` | 解壓縮後把 App 拖到「應用程式」。**沒有簽章**，第一次要在「系統設定 → 隱私權與安全性」按「仍要打開」 |
| iOS | `smart_cup_app-ios-unsigned.ipa` | **沒有簽章**，不能直接安裝；要用自己的 Apple 帳號重新簽章（sideload）或改走 TestFlight |

檔名是 App 自動更新認的名字（`UpdatePlatform.assetName`），改檔名要兩邊一起改。

- 測試沒過就不發佈。某個平台編譯失敗時，其餘平台照樣發佈，那次執行會顯示失敗；修好設定後在 Actions 對同一次執行按「Re-run failed jobs」，缺的檔案會補進同一個 release。如果要改程式碼才修得好，就要再調高版本號。
- **Android 簽章**：發佈時一定要有四個 secrets（`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`），沒有的話 Android 的工作會失敗、release 裡不會有 APK。執行 `bash tool/android_keystore.sh`（互動選單）建立 keystore 並上傳 secrets；沒有安裝 `gh` 的話選單裡有手動設定的步驟。
  - **keystore 要備份**。弄丟或換掉之後，已經安裝的 App 裝不上新版，只能解除安裝重裝，本機紀錄會消失（先在「設定 → 資料備份」匯出）。
  - 之前用 debug key 簽章安裝的版本，同樣要先匯出備份、解除安裝，才能裝第一個正式簽章的版本。

### App 自動更新

App 啟動時、之後每 6 小時，向 `https://api.github.com/repos/alianlbj23/smart_cup_app/releases/latest` 查詢（[lib/services/update_service.dart](lib/services/update_service.dart)；repo 寫在 [lib/app_info.dart](lib/app_info.dart) 的 `updateRepo`，**repo 必須是公開的**）。最新 release 的版本比 `appVersion` 新時，App 會自動跳出視窗告知有新版本可以更新（不顯示版本號和更新內容），讓使用者選「立即更新」或「稍後再說」（同一個版本只主動問一次）。選了稍後，畫面上方會留著「有新版本」的提示列，按「查看」到「設定 → 軟體更新」；也可以在那裡手動按「檢查更新」。不會自己偷偷下載或重新啟動，一定要使用者按下「立即更新」或「下載並安裝」。

| 平台 | 按「下載並安裝」之後 |
| --- | --- |
| Android | 下載 APK，開啟系統的安裝程式，使用者按「安裝」。第一次會先帶到系統設定，允許「智慧水杯」安裝應用程式後再回來按一次 |
| Windows / Linux | 下載壓縮檔並解壓縮到暫存資料夾 → App 正常結束（會先斷開藍牙）→ 背景程式把新檔案蓋進 App 所在的資料夾 → 重新啟動（[lib/services/update_installer.dart](lib/services/update_installer.dart)）。App 所在的資料夾不能寫入時會提示手動下載 |
| macOS / iOS | 不能由 App 自行安裝（macOS 版在 App Sandbox 裡，iOS 不允許），只提示有新版，可以複製下載頁的連結 |
| Web | 沒有更新功能（重新整理就是新版） |

- 下載網址只接受這個 repo、該版本 release 底下的固定檔名，下載完會核對檔案大小。Android 另外由系統檢查簽章：不是同一把 key 簽的 APK 裝不上去。
- 更新不會動到本機的紀錄（SQLite 在 App 資料夾，不在安裝資料夾裡）。
- Windows / Linux 的更新只會覆蓋和新增檔案，不會刪掉新版已經沒有的舊檔。暫存資料夾裡的 `smart_cup_update/update.log` 有背景程式的紀錄（App 60 秒內沒有結束時不會動任何檔案）。
- macOS 目前連查詢都做不到：和連結照護系統一樣，缺 `com.apple.security.network.client` entitlement（見上面的 [macOS](#macos只能在-macos-上編譯)）。

## 驗證紀錄

| 平台 | 狀態 |
| --- | --- |
| Linux | 已用 `flutter build linux --release` 編譯成功，並連實際水杯驗證水位、姿態、電量顯示、90 秒連續傳輸、休眠中連線不斷（休眠中連上 1.4 秒內顯示完整畫面、晃杯子恢復即時）、關閉視窗會斷開藍牙（2026-11-19） |
| Windows | 已用 `flutter build windows --release` 編譯成功（2026-10-29） |
| Web | 已用 `flutter build web --release` 編譯成功（2026-11-25，1.1.0，含照護系統連結），尚未在瀏覽器實際執行；連結照護系統還需要 Server 允許跨來源請求（CORS），尚未驗證 |
| macOS | 已加上藍牙權限設定（entitlement、Info.plist），還沒在 Mac 上編譯驗證 |
| Android | 已用 `flutter build apk --release` 編譯成功並確認簽章（2026-11-26），還沒裝到實機 |
| iOS | 還沒在本機編譯驗證 |

自動更新與發佈流程（2026-11-26）：

- 已驗證：單元／widget 測試（假的 GitHub 回應）；對真的 GitHub API 查詢過（還沒有 release 時回報沒有更新）；Linux 的「解壓縮 → App 結束後替換檔案 → 重新啟動」用假的 App 資料夾實際執行過（[test/update_installer_test.dart](test/update_installer_test.dart)）；workflow 裡判斷要不要發佈的 shell 邏輯在本機用臨時 repo 跑過。
- Android 已在本機用 `flutter build apk --release` 編譯成功（JDK 17、Android SDK 36）：沒有 `key.properties` 時是 debug key 簽章，用 `tool/android_keystore.sh` 建立 keystore 後是正式 key 簽章（`apksigner verify` 確認過）；APK 的 manifest 裡有安裝權限和 `FileProvider`。
- **還沒驗證**：workflow 還沒在 GitHub Actions 上實際跑過；Android 版還沒裝到實機上，系統安裝程式那一段（`MainActivity.kt`）沒有實際執行過；`tool/android_keystore.sh` 上傳 secrets 的選項沒跑過；Windows 的替換流程要等 CI 的 Windows 工作跑同一個測試檔；iOS 的未簽章 IPA 沒有試裝過；還沒有用真的 release 從舊版更新到新版。

1.1.0（2026-11-25）新增的韌體事件（0x07、3-byte ACK、Device Status 的 BLE 位址）與照護系統連結，目前只有單元／widget 測試（假的 BLE 與假的 HTTP client），**還沒有接實際的水杯與實際的 Server 驗證**。Linux 那一列的實機驗證是 1.0.0 的結果。
