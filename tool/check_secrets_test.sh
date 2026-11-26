#!/usr/bin/env bash
# check_secrets.sh 的測試：在暫存的 git repo 裡放入假的敏感資料，確認會被擋下。
# 假資料都在執行時才組合出來，這個檔案本身不含任何會被掃到的字串。
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/check_secrets.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
total=0

new_repo() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo"
  cd "$work/repo" || exit 2
  git init -q .
  git config user.email test@example.invalid
  git config user.name test
  git config commit.gpgsign false
  git config core.autocrlf false
  echo 'hello' >README.md
  git add README.md
  git commit -q -m init
}

expect() {
  # $1 說明、$2 預期回傳值，其餘是 check_secrets.sh 的參數
  local name="$1" want="$2" got
  shift 2
  total=$((total + 1))
  bash "$script" "$@" >"$work/out.txt" 2>&1 </dev/null
  got=$?
  if [ "$got" -eq "$want" ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name（預期 $want，實際 $got）"
    sed 's/^/       /' "$work/out.txt"
    failures=$((failures + 1))
  fi
}

expect_output_lacks() {
  # $1 說明、$2 不該出現在上一次輸出裡的字串
  total=$((total + 1))
  if grep -qF "$2" "$work/out.txt"; then
    echo "FAIL - $1"
    failures=$((failures + 1))
  else
    echo "ok   - $1"
  fi
}

aws_key="AKIA""ABCDEFGHIJKLMNOP"
pem_header="-----BEGIN RSA PRIVATE"" KEY-----"
password_line="const pass""word = 'hunter2hunter2hunter2';"
url_line="final u = 'https://admin:s3cr""etvalue@example.com/api';"

new_repo
expect '乾淨的 repo：--staged 通過' 0 --staged
expect '乾淨的 repo：--tracked 通過' 0 --tracked
expect '乾淨的 repo：--commits HEAD 通過' 0 --commits HEAD

new_repo
echo "key = $aws_key" >config.txt
git add config.txt
expect 'AWS 金鑰：--staged 擋下' 1 --staged
expect_output_lacks '輸出不含金鑰內容' "$aws_key"

new_repo
echo "$pem_header" >notes.txt
git add notes.txt
expect '私鑰內容：--staged 擋下' 1 --staged

new_repo
echo "$password_line" >a.dart
git add a.dart
expect '寫死的密碼：--staged 擋下' 1 --staged

new_repo
echo "$url_line" >b.dart
git add b.dart
expect '帶密碼的網址：--staged 擋下' 1 --staged

new_repo
echo "$password_line // secret-scan:allow" >a.dart
git add a.dart
expect '有 allow 標記的行：通過' 0 --staged

new_repo
echo "$password_line" >a.dart
echo 'hunter2hunter2hunter2' >.secret-scan-allow
git add a.dart .secret-scan-allow
expect '字串列在 .secret-scan-allow：通過' 0 --staged

new_repo
echo 'A=1' >.env
git add -f .env
expect '.env 檔：--staged 擋下' 1 --staged

new_repo
echo 'A=' >.env.example
git add .env.example
expect '.env.example：通過' 0 --staged

new_repo
mkdir android
echo 'x' >android/upload.jks
git add -f android/upload.jks
expect 'keystore 檔：--staged 擋下' 1 --staged

new_repo
echo "key = $aws_key" >config.txt
git add config.txt
git commit -q -m 'add key'
expect '已 commit 的金鑰：--tracked 擋下' 1 --tracked
git rm -q config.txt
git commit -q -m 'remove key'
expect '金鑰刪掉後：--tracked 通過' 0 --tracked
expect '金鑰仍在歷史裡：--commits HEAD 擋下' 1 --commits HEAD
expect '只看最後一個 commit：通過' 0 --commits HEAD~1..HEAD

new_repo
expect '未知參數：回傳 2' 2 --nope
expect '--commits 沒給 rev：回傳 2' 2 --commits
expect '非互動且沒參數：回傳 2' 2

echo
echo "$((total - failures))/$total 通過"
[ "$failures" -eq 0 ]
