#!/bin/bash
# 버전을 붙인 배포본을 만든다.
#
#   ./scripts/release.sh 1.1.0
#
# 산출물:
#   build.noindex/PokeBattleBar-1.1.0.zip     동료에게 보낼 파일
#   build.noindex/poke-battle-bar.rb          Homebrew cask 초안 (tap 에 올릴 때)
#   build.noindex/RELEASE-NOTES.txt           변경 요약
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

VERSION="${1:-}"
# 버전은 x.y.z 형태여야 한다. 안 그러면 --testall 같은 플래그가
# 버전으로 들어가 PokeBattleBar---testall-Install.command 가 만들어진다.
if [ -n "$VERSION" ] && ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "버전이 x.y.z 형태가 아닙니다: $VERSION" >&2
    echo "사용법: ./scripts/release.sh 1.9.0   (테스트는 항상 실행됩니다)" >&2
    exit 1
fi
if [ -z "$VERSION" ]; then
  echo "사용법: ./scripts/release.sh <버전>   예: ./scripts/release.sh 1.1.0" >&2
  exit 1
fi

# 프로토콜 버전을 소스에서 읽는다 (호환성 안내에 쓴다)
PROTO=$(grep -oE 'static let version = [0-9]+' Sources/PokeBattleBar/Net/Wire.swift | grep -oE '[0-9]+$')
echo "==> 버전 $VERSION / 프로토콜 v$PROTO"

# Showdown 데이터가 없으면 빌드가 안 된다 (생성 파일)
if [ ! -f Sources/PokeBattleBar/Generated/ShowdownData.swift ]; then
  echo "==> Showdown 데이터 생성"
  ./scripts/fetch-showdown.sh
fi

echo "==> 검증 먼저"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)/PokeBattleBar"
# 전체 스위트를 한 번에 — 하나라도 실패하면 배포를 중단한다
if ! "$BIN" --testall --battles 60 2>/dev/null | sed -n '/^요약/,$p'; then
  echo "검증이 실패했습니다. 배포를 중단합니다." >&2
  exit 1
fi

# 업데이트가 사용자 데이터를 건드리지 않는지 확인한다.
# **반드시 테스트 프로필 파일로만** 한다 — 실제 record.json / loadouts.json 에
# 검증용 값을 쓰면 사용자가 설정한 내용을 지워버린다 (한 번 그랬다).
SUP="$HOME/Library/Application Support/PokeBattleBar"
GUARD="$SUP/loadouts-test-releasecheck.json"
mkdir -p "$SUP"
echo '{"guard":{"item":"life-orb","ability":"cursed-body","form":null}}' > "$GUARD"

echo "==> 번들"
VERSION="$VERSION" ./scripts/bundle.sh >/dev/null

VZIP="$ROOT/build.noindex/PokeBattleBar-$VERSION.zip"
mv "$ROOT/build.noindex/PokeBattleBar.zip" "$VZIP"
SHA=$(shasum -a 256 "$VZIP" | cut -d' ' -f1)

echo "==> 단일 설치 파일"
./scripts/make-installer.sh >/dev/null
VINST="$ROOT/build.noindex/PokeBattleBar-$VERSION-설치.command"
mv "$ROOT/build.noindex/Install-PokeBattleBar.command" "$ROOT/build.noindex/PokeBattleBar-$VERSION-Install.command"
rm -f "$ROOT/build.noindex/PokeBattleBar-설치.command"
VINST="$ROOT/build.noindex/PokeBattleBar-$VERSION-Install.command"

cat > "$ROOT/build.noindex/poke-battle-bar.rb" <<CASK
# Homebrew cask 초안. 자기 tap 저장소의 Casks/ 아래에 두면
# 동료들이 'brew upgrade --cask poke-battle-bar' 로 업데이트할 수 있다.
cask "poke-battle-bar" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/<계정>/<저장소>/releases/download/v#{version}/PokeBattleBar-#{version}.zip"
  name "PokeBattleBar"
  desc "PokeTokenBar 도감 포켓몬으로 같은 네트워크의 동료와 배틀"
  homepage "https://github.com/<계정>/<저장소>"

  app "PokeBattleBar/PokeBattleBar.app"

  caveats <<~EOS
    첫 실행 때 "로컬 네트워크 접근 허용"을 눌러주세요.
    배틀하려면 상대와 같은 버전이어야 합니다 (프로토콜 v$PROTO).
  EOS
end
CASK

cat > "$ROOT/build.noindex/RELEASE-NOTES.txt" <<NOTES
PokeBattleBar $VERSION  (프로토콜 v$PROTO)

** 중요: 배틀하려면 양쪽이 같은 버전이어야 합니다 **
프로토콜 버전이 다르면 방 목록에 "버전 불일치"로 표시되고 접속이 막힙니다.
그러니 팀원 전원이 함께 업데이트해주세요.

설치 / 업데이트 — 파일 하나 실행하면 끝
  PokeBattleBar-$VERSION-Install.command
  기존 앱 종료, 설치, 격리 해제, 실행까지 전부 자동으로 처리합니다.

  ★ 실행 방법
    1) 터미널을 엽니다 (Spotlight 에서 "터미널")
    2) bash 를 치고 스페이스바를 한 번 누릅니다
    3) 이 파일을 터미널 창으로 끌어다 놓습니다
    4) 엔터

       bash /Users/본인/Downloads/PokeBattleBar-$VERSION-Install.command

  ※ 파일을 그냥 더블클릭하거나, bash 없이 끌어다 놓으면
    "permission denied" 또는 "확인되지 않은 개발자" 오류가 납니다.
    전송 과정에서 실행 권한이 벗겨지기 때문입니다.
    bash 를 앞에 붙이면 권한과 무관하게, 경고 없이 실행됩니다.

  ※ 사전 준비: PokeTokenBar 가 설치되어 포켓몬이 1마리 이상 있어야 합니다
       brew install --cask poke-token-bar

sha256 (zip): $SHA
NOTES

echo
if [ -f "$GUARD" ] && grep -q '"guard"' "$GUARD"; then
    echo "==> 사용자 데이터 보존 확인 (테스트 프로필 파일)"
    rm -f "$GUARD"
else
    echo "==> 경고: 사용자 데이터가 유지되지 않았습니다" >&2
    exit 1
fi

echo "==> 완료"
echo "   ${BLD:-}설치 파일 : $VINST  ($(du -h "$VINST" | cut -f1))${RST:-}"
echo "               ↑ 동료에게 이것만 보내면 됩니다"
echo "   zip     : $VZIP  ($(du -h "$VZIP" | cut -f1))"
echo "   sha256  : $SHA"
echo "   cask    : $ROOT/build.noindex/poke-battle-bar.rb"
echo "   릴리즈노트: $ROOT/build.noindex/RELEASE-NOTES.txt"
echo
echo "   동료에게: zip + RELEASE-NOTES.txt 내용을 함께 전달"
