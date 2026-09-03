# 데이터 출처와 저작권

이 저장소를 공개하기 전에 알아둘 것들입니다.

## 코드

MIT (LICENSE 참고).

## 함께 담긴 데이터

`Sources/PokeBattleBar/Generated/` 안의 파일은 **자동 생성물**입니다.
직접 고치지 말고 스크립트를 다시 돌리세요.

| 파일 | 출처 | 라이선스 |
|---|---|---|
| `ShowdownData.swift` | [smogon/pokemon-showdown](https://github.com/smogon/pokemon-showdown) 의 기술 플래그·랜덤배틀 세팅 | MIT |
| `SmogonSets.swift` | [data.pkmn.cc](https://data.pkmn.cc) 가 제공하는 Smogon 분석 세팅 | 원 자료는 Smogon 커뮤니티 |

재생성:

```bash
./scripts/fetch-showdown.sh      # 기술 플래그 (contact, charge, recharge …)
./scripts/fetch-smogon-sets.sh   # 실전 세팅
```

## 실행 중에 받아오는 것

앱에 담지 않고 필요할 때 받아 캐시합니다.

- **[PokéAPI](https://pokeapi.co)** — 종족값·타입·기술·특성·도구·한글 이름과 설명
- **[PokeAPI/sprites](https://github.com/PokeAPI/sprites)** — 포켓몬·도구 이미지
- **PokeTokenBar** — 이미 받아둔 스프라이트를 재활용합니다 (**읽기 전용**, 절대 쓰지 않습니다)

## 포켓몬 관련 저작권

Pokémon 과 포켓몬 이름·이미지는 Nintendo / Creatures Inc. / GAME FREAK inc. 의
상표이며 저작물입니다. 이 프로젝트는 **비공식 팬 프로젝트**이고 위 회사들과
아무 관계가 없습니다.

- 원작 게임의 UI 에셋·글꼴·이펙트 이미지는 **담지 않습니다.** 화면은 코드로 다시 그렸습니다
  (몬스터볼 아이콘, HP 판, 무대 모두 SwiftUI 도형입니다).
- 포켓몬 이미지는 저장소에 담지 않고 실행 중에 PokéAPI 스프라이트 저장소에서 받습니다.
- 판매하거나 광고를 붙이지 마세요.
