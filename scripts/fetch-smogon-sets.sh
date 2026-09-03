#!/bin/bash
# Smogon 분석 세팅을 받아 Swift 데이터로 만든다.
#
# 왜 필요한가: Showdown 저장소의 랜덤배틀 세팅에는 **도구가 없다** (팀 생성
# 알고리즘이 고르기 때문이다). data.pkmn.cc 는 Smogon 분석 페이지의 세팅을
# JSON 으로 주는데, 여기에는 이름·기술·도구·특성·성격·노력치가 다 들어 있다.
#
# 세대 선택 이유:
#   gen71v1 / gen51v1 / gen91v1 — 우리 배틀이 1대1 이다
#   gen5*  — 5세대는 #649 까지다. PokeTokenBar 로스터 범위와 정확히 겹친다
#   gen2~4, gen9 — 나머지 커버리지
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="Sources/PokeBattleBar/Generated/SmogonSets.swift"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

FORMATS="gen71v1 gen51v1 gen91v1 gen5ou gen5uu gen5ubers gen4ou gen3ou gen2ou gen9ou gen8ou gen7ou gen6ou"

echo "==> 내려받기"
for f in $FORMATS; do
    if curl -sfL -o "$TMP/$f.json" "https://data.pkmn.cc/sets/$f.json"; then
        printf "    %-10s %s\n" "$f" "$(python3 -c "import json;print(len(json.load(open('$TMP/$f.json'))),'종')" 2>/dev/null || echo '?')"
    else
        echo "    $f — 실패 (건너뜀)"
    fi
done

echo "==> 합치기"
python3 - "$TMP" "$OUT" <<'PY'
import json, os, sys, glob

tmp, out = sys.argv[1], sys.argv[2]

# 포맷 이름을 화면에 보여줄 한글 라벨로
LABEL = {
    'gen71v1': '7세대 1대1', 'gen51v1': '5세대 1대1', 'gen91v1': '9세대 1대1',
    'gen5ou': '5세대 OU', 'gen5uu': '5세대 UU', 'gen5ubers': '5세대 Ubers',
    'gen4ou': '4세대 OU', 'gen3ou': '3세대 OU', 'gen2ou': '2세대 OU',
    'gen9ou': '9세대 OU', 'gen8ou': '8세대 OU', 'gen7ou': '7세대 OU',
    'gen6ou': '6세대 OU',
}
# 1대1 포맷을 먼저 보여준다 (우리 배틀이 1대1 이다)
ORDER = ['gen71v1', 'gen51v1', 'gen91v1', 'gen5ou', 'gen5uu', 'gen5ubers',
         'gen4ou', 'gen3ou', 'gen2ou', 'gen9ou', 'gen8ou', 'gen7ou', 'gen6ou']

def slot_options(m):
    """기술 한 칸. 문자열이거나 대안 목록이다."""
    return m if isinstance(m, list) else [m]

merged = {}      # 종 -> [세팅]
for fmt in ORDER:
    p = os.path.join(tmp, fmt + '.json')
    if not os.path.exists(p):
        continue
    data = json.load(open(p))
    for species, sets in data.items():
        for setname, s in sets.items():
            entry = {
                'f': fmt,                       # 포맷
                'n': setname,                   # 세팅 이름
                'm': [slot_options(m) for m in s.get('moves', [])],
                'i': s.get('item'),             # 도구 (없을 수 있다)
                'a': s.get('ability'),
                # 성격·노력치는 **가져오지 않는다.** 성격은 PokeTokenBar 를 따르고
                # 노력치는 전원 0 으로 싸운다. 표시만 해도 혼동을 준다.
            }
            # 도구는 문자열 또는 대안 목록
            if isinstance(entry['i'], list):
                entry['i'] = entry['i'][0] if entry['i'] else None
            if isinstance(entry['a'], list):
                entry['a'] = entry['a'][0] if entry['a'] else None
            entry = {k: v for k, v in entry.items() if v is not None}
            merged.setdefault(species, []).append(entry)

blob = json.dumps(merged, separators=(',', ':'), ensure_ascii=False)
labels = json.dumps(LABEL, separators=(',', ':'), ensure_ascii=False)

total_sets = sum(len(v) for v in merged.values())
with_item = sum(1 for v in merged.values() for s in v if 'i' in s)

def swift_string(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

with open(out, 'w') as f:
    f.write(f'''// 자동 생성 — scripts/fetch-smogon-sets.sh
//
// Smogon 분석 세팅 (data.pkmn.cc). 종 {len(merged)}개 / 세팅 {total_sets}개 /
// 그중 도구가 있는 것 {with_item}개.
//
// Showdown 의 랜덤배틀 세팅과 달리 **도구·성격·노력치까지** 들어 있고,
// 한 종에 이름 붙은 세팅이 여러 개다 (골라 쓸 수 있다).
// 손으로 고치지 말 것 — 스크립트를 다시 돌리면 덮인다.

enum SmogonSetsData {{
    static let json = "{swift_string(blob)}"
    static let formatLabels = "{swift_string(labels)}"
}}
''')

print(f'    종 {len(merged)} / 세팅 {total_sets} / 도구 포함 {with_item}')
PY

echo "==> 완료"
ls -lh "$OUT" | awk '{print "   " $5, $9}'
