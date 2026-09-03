#!/bin/bash
# 앱을 안에 담은 **단일 설치 파일**을 만든다.
# 받는 사람은 파일 하나만 실행하면 설치·격리해제·실행까지 다 끝난다.
#
#   ./scripts/make-installer.sh            현재 build.noindex/PokeBattleBar.app 을 담는다
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build.noindex/PokeBattleBar.app"
OUT="$ROOT/build.noindex/PokeBattleBar-설치.command"
OUT_ASCII="$ROOT/build.noindex/Install-PokeBattleBar.command"

[ -d "$APP" ] || { echo "먼저 ./scripts/bundle.sh 를 실행하세요" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

echo "==> 앱 압축 (v$VERSION)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
( cd "$ROOT/build.noindex" && tar czf "$TMP/app.tgz" PokeBattleBar.app )
echo "    $(du -h "$TMP/app.tgz" | cut -f1)"

echo "==> 설치 스크립트 생성"
cat > "$OUT_ASCII" <<'STUB'
#!/bin/bash
# PokeBattleBar 설치 파일 — 이 파일 하나로 설치가 끝납니다.
#
# ★ 실행 방법 (이게 가장 확실합니다)
#   터미널을 열고  bash  를 치고 (뒤에 공백 한 칸)
#   이 파일을 터미널 창으로 끌어다 놓고 엔터.
#
#      bash /경로/PokeBattleBar-설치.command
#
#   전송 과정에서 실행 권한이 벗겨지기 때문에, 그냥 끌어다 놓고 엔터를 치면
#   "permission denied" 가 납니다. bash 를 앞에 붙이면 권한과 무관하게 실행되고
#   Gatekeeper 경고도 나오지 않습니다.
set -uo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'
say()  { printf "%s\n" "$*"; }
ok()   { printf "%s✓%s %s\n" "$GRN" "$RST" "$*"; }
warn() { printf "%s!%s %s\n" "$YEL" "$RST" "$*"; }
die()  { printf "%s✗ %s%s\n" "$RED" "$*" "$RST"; printf "\n엔터를 누르면 창이 닫힙니다."; read -r _; exit 1; }

SELF="${BASH_SOURCE[0]}"
[ -f "$SELF" ] || SELF="$0"

clear 2>/dev/null || true
say "${BLD}PokeBattleBar 설치${RST}"
say "────────────────────────────────────"
say ""

# --- macOS 버전 확인 ---
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then
  die "macOS 14 이상이 필요합니다 (현재 $(sw_vers -productVersion))"
fi
ok "macOS $(sw_vers -productVersion)"

# --- PokeTokenBar 확인 (없으면 배틀할 포켓몬이 없다) ---
STATE="$HOME/Library/Application Support/PokeTokenBar/companion-state.json"
if [ ! -f "$STATE" ]; then
  warn "PokeTokenBar 가 안 보입니다."
  say  "  PokeBattleBar 는 PokeTokenBar 의 도감 포켓몬으로 배틀합니다."
  say  "  먼저 설치하고 한 번 실행해주세요:"
  say  "      ${BLD}brew install --cask poke-token-bar${RST}"
  say  ""
  printf "그래도 계속 설치할까요? [y/N] "
  read -r ans
  case "$ans" in [yY]*) ;; *) say "설치를 취소했습니다."; exit 0 ;; esac
else
  COUNT=$(python3 -c "
import json
try:
    d=json.load(open('$STATE'))
    n=len(d.get('dex',[])) + (1 if d.get('active') else 0)
    print(n)
except Exception: print('?')
" 2>/dev/null || echo "?")
  ok "PokeTokenBar 확인 — 배틀에 쓸 수 있는 포켓몬 ${COUNT}마리"
fi

# --- 실행 중인 기존 앱 종료 ---
if pgrep -f "PokeBattleBar.app/Contents/MacOS/PokeBattleBar" >/dev/null 2>&1; then
  say "기존 PokeBattleBar 를 종료합니다…"
  pkill -f "PokeBattleBar.app/Contents/MacOS/PokeBattleBar" 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "PokeBattleBar.app/Contents/MacOS/PokeBattleBar" >/dev/null 2>&1 || break
    sleep 0.5
  done
  ok "기존 앱 종료"
fi

# --- 기존 버전 확인 ---
OLDV=""
if [ -d "/Applications/PokeBattleBar.app" ]; then
  OLDV=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
         "/Applications/PokeBattleBar.app/Contents/Info.plist" 2>/dev/null || echo "?")
fi

# --- 압축 해제 ---
say ""
say "앱을 꺼내는 중…"
WORK=$(mktemp -d) || die "임시 폴더를 만들 수 없습니다"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

LINE=$(awk '/^__PAYLOAD_BELOW__$/{print NR+1; exit}' "$SELF")
[ -n "${LINE:-}" ] || die "설치 파일이 손상됐습니다 (페이로드를 찾을 수 없음)"

tail -n +"$LINE" "$SELF" | base64 --decode | tar xzf - -C "$WORK" \
  || die "압축 해제에 실패했습니다. 파일이 전송 중 손상됐을 수 있습니다."
[ -d "$WORK/PokeBattleBar.app" ] || die "앱을 찾을 수 없습니다"

NEWV=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
       "$WORK/PokeBattleBar.app/Contents/Info.plist" 2>/dev/null || echo "?")
if [ -n "$OLDV" ]; then
  ok "설치됨: v$OLDV  →  설치할 버전: v$NEWV"
else
  ok "설치할 버전: v$NEWV"
fi

# --- 격리 속성 제거 ---
# Apple 유료 개발자 서명이 없어서, 이걸 안 떼면 앱이 실행되지 않는다.
xattr -dr com.apple.quarantine "$WORK/PokeBattleBar.app" 2>/dev/null || true
ok "격리 속성 제거"

# --- /Applications 로 설치 ---
say ""
say "/Applications 에 설치하는 중…"
if ! rm -rf "/Applications/PokeBattleBar.app" 2>/dev/null; then
  warn "관리자 권한이 필요합니다. 암호를 물어볼 수 있습니다."
  sudo rm -rf "/Applications/PokeBattleBar.app" || die "기존 앱을 지울 수 없습니다"
  sudo cp -R "$WORK/PokeBattleBar.app" /Applications/ || die "복사에 실패했습니다"
  sudo xattr -dr com.apple.quarantine "/Applications/PokeBattleBar.app" 2>/dev/null || true
  sudo chown -R "$(id -u):$(id -g)" "/Applications/PokeBattleBar.app" 2>/dev/null || true
else
  cp -R "$WORK/PokeBattleBar.app" /Applications/ || die "복사에 실패했습니다"
  xattr -dr com.apple.quarantine "/Applications/PokeBattleBar.app" 2>/dev/null || true
fi
ok "설치 완료: /Applications/PokeBattleBar.app"

# --- 실행 ---
say ""
open "/Applications/PokeBattleBar.app" 2>/dev/null && ok "실행했습니다" \
  || warn "자동 실행에 실패했습니다. Launchpad 에서 PokeBattleBar 를 열어주세요."

say ""
say "────────────────────────────────────"
say "${BLD}${GRN}설치가 끝났습니다.${RST}"
say ""
say "${BLD}처음 실행할 때 꼭 해야 할 것${RST}"
say "  \"로컬 네트워크 접근을 허용하시겠습니까?\" 가 뜨면 ${BLD}반드시 허용${RST}을 눌러주세요."
say "  거부하면 같은 네트워크의 방을 찾지 못합니다."
say "  실수로 거부했으면: 시스템 설정 > 개인정보 보호 및 보안 > 로컬 네트워크"
say ""
say "${BLD}배틀하는 방법${RST}"
say "  한 명이 \"방 열기\" → 다른 한 명이 \"자동 매칭\""
say "  ※ 양쪽 앱 버전이 같아야 합니다. 다르면 목록에 \"버전 불일치\" 로 표시됩니다."
say ""
say "첫 실행은 포켓몬 데이터를 받아오므로 조금 느립니다."
say ""
say "이 설치 파일을 다른 사람에게 전달할 때는 다음 한 줄을 함께 알려주세요:"
say "  터미널에 ${BLD}bash${RST} 를 치고 공백 한 칸 뒤에 파일을 끌어다 놓고 엔터"
say ""
printf "엔터를 누르면 창이 닫힙니다."
read -r _
exit 0

__PAYLOAD_BELOW__
STUB

base64 < "$TMP/app.tgz" >> "$OUT_ASCII"
chmod +x "$OUT_ASCII"
cp "$OUT_ASCII" "$OUT"

echo
echo "==> 완료"
echo "   설치 파일: $OUT_ASCII  ($(du -h "$OUT_ASCII" | cut -f1))"
echo "   (한글 이름 사본도 함께: $(basename "$OUT"))"
echo
echo "   동료에게 이 파일 하나만 보내면 됩니다."
echo
echo "   ※ 실행은 반드시 이렇게 안내하세요 (전송 시 실행권한이 벗겨집니다):"
echo "        터미널에  bash  치고 공백 한 칸, 파일을 끌어다 놓고 엔터"
