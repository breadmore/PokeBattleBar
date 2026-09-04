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
# 도구·특성도 받는다.
#
# "맹독구슬을 들면 다음 턴에 맹독", "내던지기로 그 상태를 상대에게" 같은 규칙은
# PokeAPI 의 짧은 설명으로는 구현할 수 없다. Showdown 은 이걸 구조화해 갖고 있고,
# 무엇보다 **목록 자체**가 있어서 "우리가 뭘 빼먹었는지" 를 셀 수 있다.
curl -sfL --max-time 60 "$BASE/data/items.ts" -o "$TMP/items.ts"
curl -sfL --max-time 60 "$BASE/data/abilities.ts" -o "$TMP/abilities.ts"
# 종족·폼 표. **특수 폼 목록의 원천이다.**
#
# 사람이 "특이한 포켓몬 목록" 을 손으로 관리하면 반드시 빠진다.
# pokedex.ts 는 battleOnly·changesFrom·requiredItem·requiredMove·maxHP 같은
# 필드로 "이 폼은 언제 생기는가" 를 스스로 말해준다. 그걸 뽑아서
# 우리 구현과 대조하면 목록을 기억할 필요가 없다.
curl -sfL --max-time 60 "$BASE/data/pokedex.ts" -o "$TMP/pokedex.ts"
curl -sfL --max-time 60 "$BASE/data/random-battles/gen9/sets.json" -o "$TMP/sets.json"
# PokeAPI 의 기술 이름 목록도 받는다.
# Showdown id 는 하이픈이 없어(thunderwave) 그대로는 PokeAPI 로 조회할 수 없다.
# PokeAPI 이름 목록을 들고 있어야 "Showdown 이 허용하는 기술" 을 실제로 받아올 수 있다.
curl -sfL --max-time 60 "https://pokeapi.co/api/v2/move?limit=2000" -o "$TMP/pokeapi-moves.json"
# 도구·특성도 같은 이유로 이름 목록이 필요하다.
#
# Showdown id 는 하이픈이 없다("serenegrace"). PokeAPI 는 있다("serene-grace").
# 역변환이 불가능하므로 PokeAPI 쪽 이름 목록을 들고 있어야 두 데이터를
# 맞춰볼 수 있다. 이게 없으면 이미 구현한 특성도 "빠졌다" 고 나온다.
curl -sfL --max-time 60 "https://pokeapi.co/api/v2/ability?limit=1000" -o "$TMP/pokeapi-abilities.json"
curl -sfL --max-time 60 "https://pokeapi.co/api/v2/item?limit=3000" -o "$TMP/pokeapi-items.json"
# 폼 이름 전체. **감사의 필터로 쓴다.**
#
# Showdown 의 pokedex.ts 에는 팬메이드 메가(Chesnaught-Mega)나 CAP 종족
# (Ramnarok) 도 섞여 있다. 우리 앱은 PokeTokenBar 도감 + PokeAPI 로만
# 폼을 만들 수 있으므로, PokeAPI 가 모르는 폼은 애초에 나올 수 없다.
curl -sfL --max-time 90 "https://pokeapi.co/api/v2/pokemon?limit=100000" -o "$TMP/pokeapi-forms.json"

echo "==> 추출 (node 네이티브 TS 파싱)"
cat > "$TMP/extract.mjs" <<'JS'
import fs from 'node:fs';
const { Moves } = await import(process.argv[2]);
// charge = 솔라빔처럼 **모으는 턴**이 있는 2턴 기술.
// 이게 빠져 있어서 솔라빔이 한 턴에 나갔다.
const WANT_FLAGS = new Set(['contact','punch','bite','sound','powder','protect','metronome',
                            'heal','reflectable','charge','recharge','slicing','wind','bullet']);
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
  // 파괴광선의 "다음 턴 못 움직임" 은 self.volatileStatus = 'mustrecharge' 로만 있다.
  // 이걸 안 가져오면 반동 없는 위력 150 기술이 되어버린다.
  if (m.self?.volatileStatus) o.sv = m.self.volatileStatus;
  if (m.self?.status) o.ss = m.self.status;
  if (m.target) o.tg = m.target;
  // 모으는 턴에 어디로 숨는지 (공중·땅속·물속 — 그 동안 대부분의 기술이 맞지 않는다)
  // 공중날기·땅속은 함수, 섀도다이브는 `onInvulnerability: false` 라 값이 falsy 다.
  // 존재 여부로 봐야 한다. 스카이드롭만 onAnyInvulnerability 를 쓴다.
  if (m.condition && ('onInvulnerability' in m.condition ||
                      'onAnyInvulnerability' in m.condition)) o.hide = 1;
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

cat > "$TMP/extract-items.mjs" <<'JS'
import fs from 'node:fs';
const { Items } = await import(process.argv[2]);
const out = {};
for (const [id, it] of Object.entries(Items)) {
  const o = {};
  // 내던지기 — 위력과 부가효과가 도구마다 다르다
  if (it.fling) {
    o.fl = it.fling.basePower ?? 0;
    if (it.fling.status) o.fls = it.fling.status;
    if (it.fling.volatileStatus) o.flv = it.fling.volatileStatus;
  }
  if (it.isBerry) o.berry = 1;
  if (it.naturalGift) o.ng = [it.naturalGift.basePower, it.naturalGift.type];
  if (it.isChoice) o.choice = 1;
  if (it.megaStone) o.mega = it.megaStone;
  if (it.zMove) o.z = typeof it.zMove === 'string' ? it.zMove : 1;
  if (it.zMoveType) o.zt = it.zMoveType;
  if (it.itemUser) o.user = it.itemUser;
  if (it.isNonstandard) o.ns = it.isNonstandard;
  if (it.onPlate) o.plate = it.onPlate;
  if (it.boosts) o.bo = it.boosts;
  // 배틀 중에 **무언가 하는** 도구인가 (여기 하나라도 있으면 로직이 필요하다)
  const hooks = Object.keys(it).filter(k => k.startsWith('on') && typeof it[k] === 'function');
  if (hooks.length) o.hooks = hooks;
  out[id] = o;
}
fs.writeFileSync(process.argv[3], JSON.stringify(out));
console.log('    도구 ' + Object.keys(out).length + '개');
JS
node "$TMP/extract-items.mjs" "$TMP/items.ts" "$TMP/items.json"

cat > "$TMP/extract-abilities.mjs" <<'JS'
import fs from 'node:fs';
const { Abilities } = await import(process.argv[2]);
const out = {};
for (const [id, ab] of Object.entries(Abilities)) {
  const o = {};
  if (ab.isNonstandard) o.ns = ab.isNonstandard;
  if (ab.isBreakable) o.brk = 1;
  if (ab.suppressWeather) o.sw = 1;
  if (ab.flags && Object.keys(ab.flags).length) o.f = Object.keys(ab.flags);
  const hooks = Object.keys(ab).filter(k => k.startsWith('on') && typeof ab[k] === 'function');
  if (hooks.length) o.hooks = hooks;
  out[id] = o;
}
fs.writeFileSync(process.argv[3], JSON.stringify(out));
console.log('    특성 ' + Object.keys(out).length + '개');
JS
node "$TMP/extract-abilities.mjs" "$TMP/abilities.ts" "$TMP/abilities.json"

cat > "$TMP/extract-dex.mjs" <<'JS'
import fs from 'node:fs';
const { Pokedex } = await import(process.argv[2]);
const out = {};
for (const [id, sp] of Object.entries(Pokedex)) {
  const o = {};
  // 특수 폼 판정에 필요한 것만 담는다 (종족값·타입은 PokeAPI 에서 온다)
  if (sp.num !== undefined) o.num = sp.num;
  if (sp.baseSpecies) o.base = sp.baseSpecies;
  if (sp.forme) o.forme = sp.forme;
  if (sp.otherFormes) o.other = sp.otherFormes;
  if (sp.cosmeticFormes) o.cosmetic = sp.cosmeticFormes;
  // **여기가 핵심** — 폼이 어떻게 생기는지
  if (sp.battleOnly) o.battleOnly = sp.battleOnly;      // 전투 중에만 존재
  if (sp.changesFrom) o.changesFrom = sp.changesFrom;   // 무엇에서 바뀌는지
  if (sp.requiredItem) o.reqItem = sp.requiredItem;
  if (sp.requiredItems) o.reqItems = sp.requiredItems;
  if (sp.requiredMove) o.reqMove = sp.requiredMove;
  if (sp.requiredAbility) o.reqAbility = sp.requiredAbility;
  if (sp.requiredTeraType) o.reqTera = sp.requiredTeraType;
  if (sp.maxHP) o.maxHP = sp.maxHP;                     // 껍질몬
  if (sp.isNonstandard) o.ns = sp.isNonstandard;
  if (sp.abilities) o.abilities = Object.values(sp.abilities);
  if (sp.gen) o.gen = sp.gen;
  out[id] = o;
}
fs.writeFileSync(process.argv[3], JSON.stringify(out));
const special = Object.values(out).filter(o =>
  o.battleOnly || o.changesFrom || o.reqItem || o.reqItems || o.reqMove || o.maxHP).length;
console.log('    종족·폼 ' + Object.keys(out).length + '개 (특수 폼 ' + special + '개)');
JS
node "$TMP/extract-dex.mjs" "$TMP/pokedex.ts" "$TMP/dex.json"

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
python3 - "$TMP/moves.json" "$TMP/sets-slim.json" "$TMP/pokeapi-moves.json" "$OUT/ShowdownData.swift" "$TMP/items.json" "$TMP/abilities.json" "$TMP/pokeapi-abilities.json" "$TMP/pokeapi-items.json" "$TMP/dex.json" "$TMP/pokeapi-forms.json" <<'PY'
import json, sys
moves = open(sys.argv[1], encoding='utf-8').read()
sets  = open(sys.argv[2], encoding='utf-8').read()
items = open(sys.argv[5], encoding='utf-8').read()
abils = open(sys.argv[6], encoding='utf-8').read()

# PokeAPI 이름 -> Showdown id 로 이어지도록, PokeAPI 쪽 이름 목록을 함께 담는다
api = json.load(open(sys.argv[3], encoding='utf-8'))
api_names = sorted(m['name'] for m in api['results'])
names_json = json.dumps(api_names, separators=(',',':'))

ab_names = sorted(a['name'] for a in json.load(open(sys.argv[7], encoding='utf-8'))['results'])
it_names = sorted(i['name'] for i in json.load(open(sys.argv[8], encoding='utf-8'))['results'])
dex = open(sys.argv[9], encoding='utf-8').read()
form_names = sorted(f['name'] for f in json.load(open(sys.argv[10], encoding='utf-8'))['results'])
form_names_json = json.dumps(form_names, separators=(',',':'))
ab_names_json = json.dumps(ab_names, separators=(',',':'))
it_names_json = json.dumps(it_names, separators=(',',':'))
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

    /// 도구 데이터 (Showdown id -> 축약 필드).
    /// `hooks` 는 배틀 중 무언가 하는 도구를 뜻한다 — 우리 구현 목록과
    /// 맞춰보면 빼먹은 것을 셀 수 있다.
    static let itemsJSON = {lit(items)}

    /// 특성 데이터 (Showdown id -> 축약 필드)
    static let abilitiesJSON = {lit(abils)}

    /// PokeAPI 의 특성 이름 전체. Showdown id 와 맞춰보는 데 쓴다.
    static let pokeAPIAbilityNamesJSON = {lit(ab_names_json)}

    /// PokeAPI 의 도구 이름 전체
    static let pokeAPIItemNamesJSON = {lit(it_names_json)}

    /// 종족·폼 표. **특수 폼 목록의 원천이다.**
    ///
    /// battleOnly·changesFrom·requiredItem·requiredMove·maxHP 로
    /// "이 폼은 언제 생기는가" 를 알 수 있다. 손으로 목록을 관리하면
    /// 반드시 빠지므로 여기서 뽑아 우리 구현과 대조한다.
    static let dexJSON = {lit(dex)}

    /// PokeAPI 가 아는 폼 이름 전체 ("aegislash-blade", "venusaur-mega").
    /// 감사가 팬메이드·CAP 폼을 걸러내는 데 쓴다.
    static let pokeAPIFormNamesJSON = {lit(form_names_json)}
}}
'''
open(sys.argv[4], 'w', encoding='utf-8').write(out)
print(f"    {sys.argv[4]}")
PY

echo "==> 완료"
wc -c "$OUT/ShowdownData.swift" | awk '{printf "   %.0fKB\n", $1/1024}'
