#!/bin/bash
# PokeBattleBar 를 실행 가능한 .app 번들로 묶고, 배포용 zip 을 만든다.
#
#   ./scripts/bundle.sh              유니버설(arm64 + x86_64) — 배포용, 기본값
#   NATIVE=1 ./scripts/bundle.sh     이 맥의 아키텍처만 — 빠르다, 내 테스트용
#
# 로컬 네트워크(Bonjour) 권한 선언이 Info.plist 에 반드시 있어야 macOS 14+ 에서 방 검색이 된다.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build.noindex/PokeBattleBar.app"
ZIP="$ROOT/build.noindex/PokeBattleBar.zip"
CONFIG=release

if [ "${NATIVE:-0}" = "1" ]; then
  ARCH_FLAGS=()
  echo "==> 빌드 (release / 네이티브 전용)"
else
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  echo "==> 빌드 (release / 유니버설 arm64+x86_64)"
fi

swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/PokeBattleBar"
[ -x "$BIN" ] || { echo "실행 파일을 찾을 수 없습니다: $BIN" >&2; exit 1; }

echo "==> 번들 구성: $APP"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PokeBattleBar"

# release.sh 가 넘겨주면 그 버전을, 아니면 git 태그를 쓴다
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 1.0.0)}"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.pokebattlebar</string>
    <key>CFBundleName</key><string>PokeBattleBar</string>
    <key>CFBundleDisplayName</key><string>PokeBattleBar</string>
    <key>CFBundleExecutable</key><string>PokeBattleBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>

    <!-- 같은 네트워크의 상대를 찾기 위해 Bonjour 를 쓴다.
         이 두 키가 없으면 macOS 14+ 에서 방 검색이 조용히 실패한다. -->
    <key>NSLocalNetworkUsageDescription</key>
    <string>같은 네트워크에 있는 동료의 배틀 방을 찾고 접속하기 위해 로컬 네트워크를 사용합니다.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_pokebattle._tcp</string>
        <!-- 로비 존재 알림 + 초대. 여기 없으면 광고와 검색이 조용히 실패해
             "로비 0명" 이 된다 — 번들 밖에서 바이너리를 직접 돌리면
             제한이 없어서 통과하므로 특히 놓치기 쉽다. -->
        <string>_pokelobby._tcp</string>
    </array>
</dict>
</plist>
PLIST

echo "==> 서명 (ad-hoc)"
codesign --force --sign - --identifier local.pokebattlebar "$APP" >/dev/null 2>&1 \
  || echo "   경고: 서명 실패"

# 배포 폴더를 만든다. 파일명은 전부 ASCII 로 — 한글 파일명은 zip 전송 중 깨진다.
STAGE="$ROOT/build.noindex/stage/PokeBattleBar"
rm -rf "$ROOT/build.noindex/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

# 설치 스크립트. 단, 이 .command 파일도 전송되면 격리 대상이 되어
# 더블클릭이 막힐 수 있다. 그래서 READ-ME 에는 터미널 한 줄 붙여넣기를 먼저 안내한다.
cat > "$STAGE/Install.command" <<'INSTALL'
#!/bin/bash
# PokeBattleBar 설치
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d "PokeBattleBar.app" ]; then
  echo "PokeBattleBar.app 을 이 파일과 같은 폴더에 두고 다시 실행하세요."
  read -r -p "엔터를 누르면 닫힙니다." _; exit 1
fi

echo "==> 격리 속성 제거 (서명이 ad-hoc 이라 필요합니다)"
xattr -dr com.apple.quarantine "PokeBattleBar.app" 2>/dev/null || true

echo "==> /Applications 로 복사"
rm -rf "/Applications/PokeBattleBar.app"
cp -R "PokeBattleBar.app" "/Applications/"
xattr -dr com.apple.quarantine "/Applications/PokeBattleBar.app" 2>/dev/null || true

echo "==> 실행"
open "/Applications/PokeBattleBar.app"

echo
echo "완료. 첫 실행 때 '로컬 네트워크 접근 허용'을 반드시 눌러주세요."
echo "거부했으면 시스템 설정 > 개인정보 보호 및 보안 > 로컬 네트워크 에서 켤 수 있습니다."
read -r -p "엔터를 누르면 닫힙니다." _
INSTALL
chmod +x "$STAGE/Install.command"

cat > "$STAGE/READ-ME-FIRST.txt" <<'RM'
PokeBattleBar 설치 방법
=======================

PokeTokenBar 도감 포켓몬으로 같은 네트워크의 동료와 배틀하는 앱입니다.

먼저 확인
---------
- macOS 14 이상 (Apple Silicon / 인텔 모두 됩니다)
- PokeTokenBar 가 설치되어 있고 포켓몬이 최소 1마리 있어야 합니다
    brew install --cask poke-token-bar
  포켓몬 정보는 각자 맥에 있으므로, 배틀할 사람 전원이 두 앱을 다 깔아야 합니다.


방법 1 — 터미널에 한 줄 붙여넣기 (권장)
---------------------------------------
이 앱은 Apple 유료 개발자 서명이 없어서 그냥 더블클릭하면 macOS 가 막습니다.
아래 한 줄이 그 처리까지 한 번에 합니다.

터미널을 열고(Spotlight 에서 "터미널") 이 폴더 경로에서 붙여넣으세요:

  xattr -dr com.apple.quarantine PokeBattleBar.app && cp -R PokeBattleBar.app /Applications/ && open /Applications/PokeBattleBar.app

폴더 경로를 모르면, 터미널에 `cd ` 를 입력하고 (뒤에 공백 한 칸)
이 폴더를 터미널 창으로 끌어다 놓은 뒤 엔터를 누르면 됩니다.


방법 2 — Install.command 더블클릭
---------------------------------
Install.command 를 더블클릭하세요.
"확인되지 않은 개발자" 경고가 뜨면 방법 1 을 쓰세요.


버전을 맞춰야 합니다 (중요)
--------------------------
배틀하려면 양쪽 PokeBattleBar 가 **같은 버전**이어야 합니다.
다르면 방 목록에 "버전 불일치" 로 표시되고 접속이 막힙니다 (조용히 실패하지 않습니다).
업데이트는 팀원이 함께 하는 게 좋습니다.


처음 실행할 때 (중요)
---------------------
"로컬 네트워크 접근을 허용하시겠습니까?" 가 뜨면 반드시 **허용**을 누르세요.
거부하면 방 검색이 조용히 실패합니다.

실수로 거부했으면:
  시스템 설정 > 개인정보 보호 및 보안 > 로컬 네트워크 > PokeBattleBar 켜기

첫 실행은 포켓몬 데이터를 받아오므로 조금 느립니다. 그 다음부터는 빠릅니다.


배틀하는 방법
-------------
1. 한 명이 "방 열기" — 최대 포켓몬 수, 레벨, 상태이상 등을 정합니다
2. 나머지 한 명이 "자동 매칭" 또는 목록에서 "참가"
3. 각자 선봉 포켓몬을 고릅니다
4. 매 턴 기술 4개 중 하나를 고릅니다. 교체는 없고, 쓰러지면 다음 포켓몬을 고릅니다

가진 포켓몬이 적으면 그만큼만 데려갑니다 — 2마리는 6마리 상대에게 불리합니다.
RM

echo "==> zip 생성: $ZIP"
( cd "$ROOT/build.noindex/stage" && ditto -c -k --sequesterRsrc --keepParent \
    PokeBattleBar "$ZIP" )
rm -rf "$ROOT/build.noindex/stage"

echo
echo "==> 완료"
echo "   앱   : $APP"
echo "   배포 : $ZIP   ($(du -h "$ZIP" | cut -f1))"
echo "   아키 : $(lipo -archs "$APP/Contents/MacOS/PokeBattleBar")"
echo
echo "   동료에게 줄 것: $ZIP  (이 파일 하나)"
echo
echo "   내 테스트:  '$APP/Contents/MacOS/PokeBattleBar' --selftest"
echo "              '$APP/Contents/MacOS/PokeBattleBar' --nettest"
