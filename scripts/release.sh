#!/bin/bash
# 버전을 붙인 배포본을 만든다.
#
#   ./scripts/release.sh 1.1.0
#
# 산출물:
#   build/PokeBattleBar-1.1.0.zip     동료에게 보낼 파일
#   build/poke-battle-bar.rb          Homebrew cask 초안 (tap 에 올릴 때)
#   build/RELEASE-NOTES.txt           변경 요약
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "사용법: ./scripts/release.sh <버전>   예: ./scripts/release.sh 1.1.0" >&2
  exit 1
fi

# 프로토콜 버전을 소스에서 읽는다 (호환성 안내에 쓴다)
PROTO=$(grep -oE 'static let version = [0-9]+' Sources/PokeBattleBar/Net/Wire.swift | grep -oE '[0-9]+$')
echo "==> 버전 $VERSION / 프로토콜 v$PROTO"

echo "==> 검증 먼저"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)/PokeBattleBar"
FAILED=0
for t in --selftest --movetest --formtest --pickertest --nettest; do
  printf "    %-14s " "$t"
  if "$BIN" "$t" >/dev/null 2>&1; then echo "✓"; else echo "✗"; FAILED=1; fi
done
if [ "$FAILED" = "1" ]; then
  echo "검증이 실패했습니다. 배포를 중단합니다." >&2
  exit 1
fi

echo "==> 번들"
VERSION="$VERSION" ./scripts/bundle.sh >/dev/null

VZIP="$ROOT/build/PokeBattleBar-$VERSION.zip"
mv "$ROOT/build/PokeBattleBar.zip" "$VZIP"
SHA=$(shasum -a 256 "$VZIP" | cut -d' ' -f1)

cat > "$ROOT/build/poke-battle-bar.rb" <<CASK
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

cat > "$ROOT/build/RELEASE-NOTES.txt" <<NOTES
PokeBattleBar $VERSION  (프로토콜 v$PROTO)

** 중요: 배틀하려면 양쪽이 같은 버전이어야 합니다 **
프로토콜 버전이 다르면 방 목록에 "버전 불일치"로 표시되고 접속이 막힙니다.
그러니 팀원 전원이 함께 업데이트해주세요.

설치 / 업데이트
  1) PokeBattleBar-$VERSION.zip 압축을 풀고
  2) 그 폴더에서 터미널을 열어 아래 한 줄 붙여넣기

  xattr -dr com.apple.quarantine PokeBattleBar.app && rm -rf /Applications/PokeBattleBar.app && cp -R PokeBattleBar.app /Applications/ && open /Applications/PokeBattleBar.app

  (기존 앱이 열려 있으면 먼저 종료해주세요)

sha256: $SHA
NOTES

echo
echo "==> 완료"
echo "   배포본  : $VZIP  ($(du -h "$VZIP" | cut -f1))"
echo "   sha256  : $SHA"
echo "   cask    : $ROOT/build/poke-battle-bar.rb"
echo "   릴리즈노트: $ROOT/build/RELEASE-NOTES.txt"
echo
echo "   동료에게: zip + RELEASE-NOTES.txt 내용을 함께 전달"
