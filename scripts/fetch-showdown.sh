#!/bin/bash
# Pokémon Showdown 의 배틀 데이터를 받아 앱에 넣을 형태로 변환한다.
#
# PokeAPI 는 한글명·스프라이트·종족값을 주지만 **배틀 로직 플래그를 주지 않는다**
# (접촉 여부, 자기 교체, 손가락흔들기 대상, 방어 관통, G-Max 기술 등).
# Showdown(MIT) 이 그걸 전부 구조화해서 가지고 있으므로 여기서 가져온다.
#
#   ./scripts/fetch-showdown.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="Sources/PokeBattleBar/Generated"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v node >/dev/null || { echo "node 가 필요합니다" >&2; exit 1; }
mkdir -p "$OUT"

BASE="https://raw.githubusercontent.com/smogon/pokemon-showdown/master"
echo "==> 내려받기"
curl -sfL --max-time 60 "$BASE/data/moves.ts" -o "$TMP/moves.ts"
curl -sfL --max-time 60 "$BASE/data/random-battles/gen9/sets.json" -o "$TMP/sets.json"
# PokeAPI 의 기술 이름 목록도 받는다.
# Showdown id 는 하이픈이 없어(thunderwave) 그대로는 PokeAPI 로 조회할 수 없다.
# PokeAPI 이름 목록을 들고 있어야 "Showdown 이 허용하는 기술" 을 실제로 받아올 수 있다.
curl -sfL --max-time 60 "https://pokeapi.co/api/v2/move?limit=2000" -o "$TMP/pokeapi-moves.json"

echo "==> 추출 (node 네이티브 TS 파싱)"
cat > "$TMP/extract.mjs" <<'JS'
import fs from 'node:fs';
const { Moves } = await import(process.argv[2]);
const WANT_FLAGS = new Set(['contact','punch','bite','sound','powder','protect','metronome','heal','reflectable']);
const out = {};
for (const [id, m] of Object.entries(Moves)) {
  const o = {};
  if (m.flags) {
    const fl = Object.keys(m.flags).filter(k => m.flags[k] && WANT_FLAGS.has(k));
    if (fl.length) o.f = fl;
  }
  const map = {basePower:'bp', type:'ty', category:'cat', accuracy:'ac', priority:'pr',
               selfSwitch:'sw', selfdestruct:'sd', isMax:'mx', multihit:'mh', drain:'dr',
               recoil:'rc', heal:'hl', critRatio:'cr', ohko:'ko', forceSwitch:'fs',
               volatileStatus:'vs', status:'st', isZ:'z', isNonstandard:'ns'};
  for (const [src, dst] of Object.entries(map)) if (m[src] !== undefined) o[dst] = m[src];
  if (m.boosts) o.bo = m.boosts;
  if (m.self?.boosts) o.sb = m.self.boosts;
  const secs = m.secondaries || (m.secondary ? [m.secondary] : null);
  if (secs) o.sec = secs.filter(Boolean).map(s => {
    const x = {};
    if (s.chance !== undefined) x.chance = s.chance;
    if (s.status) x.status = s.status;
    if (s.volatileStatus) x.volatileStatus = s.volatileStatus;
    if (s.boosts) x.boosts = s.boosts;
    return x;
  });
  if (['onHit','onTry','onModifyMove','onBasePower','onEffectiveness','onMoveFail',
       'onPrepareHit','onTryHit','damageCallback','basePowerCallback','onModifyType']
      .some(k => typeof m[k] === 'function')) o.cc = 1;
  out[id] = o;
}
fs.writeFileSync(process.argv[3], JSON.stringify(out));
console.log('    기술 ' + Object.keys(out).length + '개');
JS
node "$TMP/extract.mjs" "$TMP/moves.ts" "$TMP/moves.json"

python3 - "$TMP/sets.json" "$TMP/sets-slim.json" <<'PY'
import json, sys
sets = json.load(open(sys.argv[1]))
slim = {}
for name, v in sets.items():
    s = (v.get('sets') or [])
    if not s: continue
    e = {}
    pool, items, abils = [], [], []
    for st in s:
        pool += st.get('movepool', [])
        if st.get('item'): items.append(st['item'])
        abils += st.get('abilities', [])
    if pool:  e['m'] = list(dict.fromkeys(pool))[:16]
    if items: e['i'] = items[0]
    if abils: e['a'] = list(dict.fromkeys(abils))
    if e: slim[name] = e
json.dump(slim, open(sys.argv[2],'w'), ensure_ascii=False, separators=(',',':'))
print(f"    추천 세팅 {len(slim)}종")
PY

echo "==> Swift 파일 생성"
python3 - "$TMP/moves.json" "$TMP/sets-slim.json" "$TMP/pokeapi-moves.json" "$OUT/ShowdownData.swift" <<'PY'
import json, sys
moves = open(sys.argv[1], encoding='utf-8').read()
sets  = open(sys.argv[2], encoding='utf-8').read()

# PokeAPI 이름 -> Showdown id 로 이어지도록, PokeAPI 쪽 이름 목록을 함께 담는다
api = json.load(open(sys.argv[3], encoding='utf-8'))
api_names = sorted(m['name'] for m in api['results'])
names_json = json.dumps(api_names, separators=(',',':'))
def lit(s):
    # 스위프트 원시 문자열로 감싼다 (JSON 안의 따옴표를 그대로 둘 수 있다)
    return '#"""\n' + s + '\n"""#'
out = f'''// 이 파일은 scripts/fetch-showdown.sh 가 생성합니다. 직접 고치지 마세요.
//
// 출처: Pokémon Showdown (smogon/pokemon-showdown, MIT)
// PokeAPI 가 주지 않는 배틀 로직 데이터입니다 —
// 접촉·펀치·물기·소리·가루 플래그, 자기 교체, 자폭, 방어 관통,
// 손가락흔들기 대상 여부, G-Max 기술, 부가효과 확률까지 구조화되어 있습니다.

enum ShowdownData {{
    /// 기술 데이터 (Showdown id -> 축약 필드)
    static let movesJSON = {lit(moves)}

    /// 실전에서 많이 쓰이는 세팅 (종 -> 기술 풀 / 도구 / 특성)
    static let setsJSON = {lit(sets)}

    /// PokeAPI 의 기술 이름 전체.
    /// Showdown id 는 하이픈이 없어 역변환이 안 되므로, 실제로 받아올 수 있는
    /// 이름은 이 목록에서 골라야 한다.
    static let pokeAPIMoveNamesJSON = {lit(names_json)}
}}
'''
open(sys.argv[4], 'w', encoding='utf-8').write(out)
print(f"    {sys.argv[4]}")
PY

echo "==> 완료"
wc -c "$OUT/ShowdownData.swift" | awk '{printf "   %.0fKB\n", $1/1024}'
