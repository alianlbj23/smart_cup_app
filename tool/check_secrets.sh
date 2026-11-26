#!/usr/bin/env bash
# 檢查是否有敏感資料（私鑰、密碼、token、憑證檔）即將被 commit 或 push。
#
# 不帶參數執行會出現選單。給 git hook 與 CI 用的參數：
#   --staged              檢查已 git add 的內容（pre-commit）
#   --tracked             檢查目前所有受版控的檔案
#   --commits <rev...>    檢查指定 commit 的完整內容，參數同 git rev-list
#                         例：--commits HEAD（整段歷史）、--commits A..B
#
# 回傳值：0 沒問題、1 找到疑似敏感資料、2 用法或執行錯誤。
# 只會印出位置與規則名稱，不會印出內容本身。
#
# 確定是誤判時有兩種略過方式：
#   - 在該行結尾加上註解 secret-scan:allow
#   - 把那段字串（例如測試用的假 token）加進 .secret-scan-allow，一行一個
set -euo pipefail

ALLOW_MARKER='secret-scan:allow'
ALLOW_FILE='.secret-scan-allow'

# 規則：名稱、git grep 額外旗標、POSIX ERE。
RULE_NAMES=()
RULE_FLAGS=()
RULE_PATTERNS=()
add_rule() {
  RULE_NAMES+=("$1")
  RULE_FLAGS+=("$2")
  RULE_PATTERNS+=("$3")
}
add_rule 'private-key' '' '-----BEGIN [A-Z ]*PRIVATE KEY'
add_rule 'aws-access-key' '' '(AKIA|ASIA)[0-9A-Z]{16}'
add_rule 'github-token' '' '(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})'
add_rule 'google-api-key' '' 'AIza[0-9A-Za-z_-]{35}'
add_rule 'slack-token' '' 'xox[baprs]-[A-Za-z0-9-]{10,}'
add_rule 'llm-api-key' '' 'sk-[A-Za-z0-9_-]{24,}'
add_rule 'jwt' '' 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
add_rule 'url-with-password' '' '[a-z][a-z0-9+.-]*://[^/[:space:]:@"'"'"']+:[^/[:space:]:@"'"'"'$<{]{6,}@'
add_rule 'hardcoded-credential' '-i' '(password|passwd|secret|api[_-]?key|access[_-]?key|token|storePassword|keyPassword)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]$<{]{12,}["'"'"']'

found=0

report() {
  # $1 規則名稱；stdin：每行一個位置
  local location
  while IFS= read -r location; do
    [ -n "$location" ] || continue
    printf '  [%s] %s\n' "$1" "$location"
    found=1
  done
}

is_forbidden_name() {
  local base="${1##*/}"
  base="${base,,}"
  case "$base" in
    .env.example | .env.sample | .env.template) return 1 ;;
    .env | .env.* | *.pem | *.key | *.p12 | *.pfx | *.jks | *.keystore | *.mobileprovision) return 0 ;;
    key.properties | .netrc | id_rsa | id_dsa | id_ecdsa | id_ed25519) return 0 ;;
    credentials.json | service-account*.json | service_account*.json) return 0 ;;
  esac
  return 1
}

check_names() {
  # stdin：每行一個路徑
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if is_forbidden_name "$path"; then
      printf '  [forbidden-file] %s\n' "$path"
      found=1
    fi
  done
}

grep_rule() {
  # $1 規則索引、$2 位置欄位數，其餘傳給 git grep。只輸出位置，不輸出內容。
  local index="$1" fields="$2" output status
  shift 2
  set +e
  # shellcheck disable=SC2086
  output=$(git -c core.quotepath=off grep -nIE ${RULE_FLAGS[$index]} -e "${RULE_PATTERNS[$index]}" "$@")
  status=$?
  set -e
  if [ "$status" -gt 1 ]; then
    echo "check_secrets: git grep 執行失敗（規則 ${RULE_NAMES[$index]}，狀態 $status）" >&2
    exit 2
  fi
  [ -n "$output" ] || return 0
  printf '%s\n' "$output" | { grep -vFf "$allow_patterns" || true; } | cut -d: -f"1-$fields"
}

scan_staged() {
  local files=() file index
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(git diff --cached --name-only --diff-filter=ACMR -z)
  [ "${#files[@]}" -gt 0 ] || return 0

  check_names < <(printf '%s\n' "${files[@]}")
  for index in "${!RULE_NAMES[@]}"; do
    report "${RULE_NAMES[$index]}" < <(grep_rule "$index" 2 --cached -- "${files[@]}" | sort -u)
  done
}

scan_tracked() {
  local index
  check_names < <(git -c core.quotepath=off ls-files)
  for index in "${!RULE_NAMES[@]}"; do
    report "${RULE_NAMES[$index]}" < <(grep_rule "$index" 2 | sort -u)
  done
}

scan_commits() {
  local revs=() rev index start chunk=200
  while IFS= read -r rev; do
    revs+=("$rev")
  done < <(git rev-list --abbrev-commit "$@")
  [ "${#revs[@]}" -gt 0 ] || return 0

  check_names < <(git -c core.quotepath=off log --name-only --diff-filter=ACMR --format= "$@" | sort -u)
  for index in "${!RULE_NAMES[@]}"; do
    # 同一個檔案的同一行會出現在很多 commit 裡，只列第一次。
    report "${RULE_NAMES[$index]}" < <(
      for ((start = 0; start < ${#revs[@]}; start += chunk)); do
        grep_rule "$index" 3 "${revs[@]:start:chunk}" --
      done | awk -F: '!seen[$2 ":" $3]++'
    )
  done
}

finish() {
  if [ "$found" -ne 0 ]; then
    cat >&2 <<EOF

找到疑似敏感資料（見上方清單），已中止。
- 真的是密碼／金鑰：從檔案移除，改由環境變數或未納入版控的檔案提供；
  若已經 commit 過，該金鑰要視為外洩並更換。
- 確定是誤判：在該行結尾加上註解 ${ALLOW_MARKER}，
  或把那段字串加進 ${ALLOW_FILE}
EOF
    exit 1
  fi
  echo "check_secrets: 沒有發現敏感資料。"
}

install_hooks() {
  git config core.hooksPath .githooks
  echo "已設定 core.hooksPath=.githooks（pre-commit 與 pre-push 會自動檢查）。"
}

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

menu() {
  local choice
  PS3='請選擇：'
  select choice in '檢查已 git add 的內容' '檢查所有受版控的檔案' '檢查整段 commit 歷史' '安裝 git hook' '離開'; do
    case "$REPLY" in
      1) scan_staged; finish ;;
      2) scan_tracked; finish ;;
      3) scan_commits HEAD; finish ;;
      4) install_hooks ;;
      5) ;;
      *) echo '請輸入 1 到 5。'; continue ;;
    esac
    break
  done
}

cd "$(git rev-parse --show-toplevel)"

# 要略過的固定字串：行內標記，加上 .secret-scan-allow 裡的每一行（# 開頭是註解）。
allow_patterns="$(mktemp)"
trap 'rm -f "$allow_patterns"' EXIT
printf '%s\n' "$ALLOW_MARKER" >"$allow_patterns"
if [ -f "$ALLOW_FILE" ]; then
  { grep -vE '^[[:space:]]*(#|$)' "$ALLOW_FILE" || true; } | tr -d '\r' >>"$allow_patterns"
fi

case "${1:-}" in
  --staged)
    scan_staged
    finish
    ;;
  --tracked)
    scan_tracked
    finish
    ;;
  --commits)
    shift
    if [ "$#" -eq 0 ]; then
      echo 'check_secrets: --commits 需要至少一個 rev 參數' >&2
      exit 2
    fi
    scan_commits "$@"
    finish
    ;;
  --install-hooks)
    install_hooks
    ;;
  '')
    if [ -t 0 ]; then
      menu
    else
      usage >&2
      exit 2
    fi
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
