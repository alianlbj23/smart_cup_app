#!/usr/bin/env bash
# Android 正式簽章的 keystore:建立、設定本機編譯、上傳成 GitHub Actions 的 secrets。
#
# App 的自動更新要能裝上去,每一版 APK 都要用同一把 key 簽章。這把 key 放在
# android/app/upload-keystore.jks,密碼放在 android/key.properties,兩個檔案都已經
# 被 android/.gitignore 排除,不會進 git。
#
# 用法:bash tool/android_keystore.sh(互動選單,不需要參數)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

KEYSTORE=android/app/upload-keystore.jks
PROPERTIES=android/key.properties
KEY_ALIAS=upload
SECRET_NAMES=(ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD)

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "找不到 $1:$2" >&2
    return 1
  fi
}

# 從 key.properties 讀一個值(檔案是這支腳本產生的 key=value,沒有跳脫字元)。
property() {
  sed -n "s/^$1=//p" "$PROPERTIES" | head -n 1
}

have_keystore() {
  if [ ! -f "$KEYSTORE" ] || [ ! -f "$PROPERTIES" ]; then
    echo "還沒有 keystore,請先選「建立新的 keystore」。" >&2
    return 1
  fi
}

create_keystore() {
  need keytool "請先安裝 JDK 17(keytool 是 JDK 附的工具)" || return 0
  if [ -e "$KEYSTORE" ] || [ -e "$PROPERTIES" ]; then
    echo "已經有 $KEYSTORE 或 $PROPERTIES,不會覆蓋。" >&2
    echo "換掉 keystore 之後,已經安裝的 App 就裝不上新版;確定要重建的話請自己先把舊檔移走。" >&2
    return 0
  fi
  # 只用英數字:key.properties 和 GitHub secrets 都不用處理跳脫字元。
  local password
  password=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)
  if [ "${#password}" -ne 32 ]; then
    echo "產生密碼失敗。" >&2
    return 1
  fi
  # 密碼用環境變數交給 keytool,不出現在指令列上。
  KEYSTORE_PASSWORD="$password" keytool -genkeypair \
    -keystore "$KEYSTORE" -storetype PKCS12 \
    -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=smart_cup_app" \
    -storepass:env KEYSTORE_PASSWORD -keypass:env KEYSTORE_PASSWORD
  (
    umask 077
    {
      echo "storeFile=app/upload-keystore.jks"
      echo "storePassword=$password"
      echo "keyAlias=$KEY_ALIAS"
      echo "keyPassword=$password"
    } >"$PROPERTIES"
  )
  chmod 600 "$KEYSTORE"
  echo
  echo "已建立:$KEYSTORE 和 $PROPERTIES"
  echo "請把這兩個檔案備份到安全的地方(密碼管理器、加密的隨身碟)。"
  echo "弄丟的話,已經安裝的 App 就再也收不到更新,只能解除安裝重裝(本機紀錄會消失)。"
  echo "下一步:選「上傳到 GitHub Actions 的 secrets」。"
}

show_fingerprint() {
  have_keystore || return 0
  need keytool "請先安裝 JDK 17" || return 0
  KEYSTORE_PASSWORD="$(property storePassword)" keytool -list -v \
    -keystore "$KEYSTORE" -alias "$(property keyAlias)" \
    -storepass:env KEYSTORE_PASSWORD | grep -E 'Alias name|Valid from|SHA256:'
}

upload_secrets() {
  have_keystore || return 0
  need gh "請先安裝 GitHub CLI 並執行 gh auth login,或改選「顯示手動設定的步驟」" || return 0
  need base64 "需要 base64 指令" || return 0
  echo "會在目前 repo 設定這些 secrets:${SECRET_NAMES[*]}"
  local answer
  read -r -p "確定要上傳嗎?(y/N) " answer
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "已取消。"
    return 0
  fi
  # 值都從 stdin 給 gh,不出現在指令列,也不印出來。
  base64 <"$KEYSTORE" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64
  property storePassword | tr -d '\n' | gh secret set ANDROID_KEYSTORE_PASSWORD
  property keyAlias | tr -d '\n' | gh secret set ANDROID_KEY_ALIAS
  property keyPassword | tr -d '\n' | gh secret set ANDROID_KEY_PASSWORD
  echo "已上傳。到 GitHub 的 Actions 重跑 Build android,或推一個新版本就會用這把 key 簽章。"
}

show_manual_steps() {
  have_keystore || return 0
  cat <<EOF
到 GitHub repo 的 Settings → Secrets and variables → Actions → New repository secret,
新增這四個(值不會顯示在這裡,請自己從檔案複製):

  ANDROID_KEYSTORE_BASE64    執行 base64 -w0 $KEYSTORE 的輸出
  ANDROID_KEYSTORE_PASSWORD  $PROPERTIES 裡 storePassword= 後面的值
  ANDROID_KEY_ALIAS          $PROPERTIES 裡 keyAlias= 後面的值
  ANDROID_KEY_PASSWORD       $PROPERTIES 裡 keyPassword= 後面的值
EOF
}

echo "Android 簽章 keystore"
PS3="請選擇(輸入數字):"
select choice in \
  "建立新的 keystore(本機編譯也會開始用它簽章)" \
  "上傳到 GitHub Actions 的 secrets(需要 gh)" \
  "顯示手動設定 secrets 的步驟" \
  "顯示 keystore 的指紋" \
  "離開"; do
  case "$REPLY" in
    1) create_keystore ;;
    2) upload_secrets ;;
    3) show_manual_steps ;;
    4) show_fingerprint ;;
    5) break ;;
    *) echo "請輸入 1–5。" ;;
  esac
  echo
done
