#!/bin/bash
# GitHub 릴리스를 올린다. 동료들은 앱 안의 업데이트 버튼으로 받게 된다.
#
#   ./scripts/publish-release.sh 1.12.0
#
# 먼저 해야 할 것:
#   1. scripts/config.sh 의 REPO 를 자기 저장소로 채운다
#   2. gh auth login
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/config.sh

VERSION="${1:-}"
if [ -z "$VERSION" ]; then echo "사용법: $0 1.12.0" >&2; exit 1; fi
if [ -z "${REPO:-}" ]; then
    echo "scripts/config.sh 의 REPO 를 먼저 채워주세요 (예: younghoon/PokeBattleBar)" >&2
    exit 1
fi
command -v gh >/dev/null || { echo "gh 가 필요합니다: brew install gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh auth login 을 먼저 해주세요" >&2; exit 1; }

echo "==> 빌드 + 검증"
./scripts/release.sh "$VERSION"

INSTALLER="build.noindex/PokeBattleBar-${VERSION}-Install.command"
ZIP="build.noindex/PokeBattleBar-${VERSION}.zip"
[ -f "$INSTALLER" ] || { echo "설치 파일이 없습니다: $INSTALLER" >&2; exit 1; }

PROTO=$(grep -oE 'static let version = [0-9]+' Sources/PokeBattleBar/Net/Wire.swift \
        | grep -oE '[0-9]+' | head -1)

echo "==> 릴리스 올리기 (v$VERSION, 프로토콜 v$PROTO)"
NOTES=$(cat <<EOF
## 설치 / 업데이트

**\`PokeBattleBar-${VERSION}-Install.command\` 를 받아서** 터미널에 \`bash\` 를 치고
공백 한 칸 뒤에 파일을 끌어다 놓고 엔터를 누르세요.

- 처음이면 설치, 이미 있으면 업데이트로 알아서 진행됩니다.
- 전적·기술·도구 설정은 유지됩니다.
- 앱 안에서는 우측 상단 **업데이트** 버튼으로도 받을 수 있습니다.

## 주의

통신 규약 **프로토콜 v${PROTO}** 입니다. 배틀하려면 **양쪽 버전이 같아야** 합니다.
한쪽만 새 버전이면 방 목록에 "버전 불일치" 로 표시됩니다.

## 필요한 것

- macOS 14 이상 (인텔·애플실리콘 모두)
- [PokeTokenBar](https://github.com/anthropics/poke-token-bar) — 이 앱의 도감 포켓몬으로 배틀합니다
- 첫 실행 때 인터넷 (종족값·기술·스프라이트를 받아 캐시합니다)
EOF
)

gh release create "v$VERSION" \
    "$INSTALLER" "$ZIP" \
    --repo "$REPO" \
    --title "PokeBattleBar v$VERSION" \
    --notes "$NOTES"

echo "==> 완료"
echo "   https://github.com/$REPO/releases/tag/v$VERSION"
echo "   동료들은 앱 우측 상단 업데이트 버튼으로 받게 됩니다."
