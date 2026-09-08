# arcade-kart-racer

Mario Kart에서 *시스템과 플레이 감각*만 영감을 받은 **완전 오리지널 3D 아케이드 카트 레이싱 게임** 프로젝트.
엔진: **Godot 4.7 + GDScript**.

## 이 레포의 현재 상태

**Phase 9 — UI 구현 완료 (자동 검증 완료, 패드 수동 플레이 판정 대기).**

현재 메인 씬은 Play / Time Trial(Phase 12) / Settings / Quit 메뉴로 시작한다.
Play는 Single Race → 드라이버 8종 → 카트 3종 → Ridgeline Circuit → AI
난이도 3종 선택을 거쳐 선택된 `RaceConfig`로 3랩/8카트 레이스를 연다.
모든 화면은 하나의 Theme와 명시적 키보드/게임패드 focus 경로를 공유하며,
마우스도 같은 버튼 시그널을 사용한다. Time Trial과 Grand Prix는 Phase 12
범위라 비활성 상태다.

레이스에는 3-2-1-GO/스타트 부스트, 랩·순위·리스폰·카트 충돌,
FINISHING 타임아웃, 최종 HUD(아이템 룰렛/쿨다운, 10 Hz 미니맵,
드리프트 미터, 선택형 속도계, 중앙 경고), 일시정지→설정, 드라이버/카트/
시간/베스트랩 결과표와 재시작/트랙선택/메뉴가 연결된다. 상대 카트 7대는 `ai/`의
Sensors→Navigator→Driver→ItemBrain 파이프라인으로 레이싱라인을 이해하고
코너·추월·회피·지름길·드리프트·아이템 사용을 스스로 판단하는 실제 AI다
(난이도는 선택한 `RaceConfig.ai_difficulty`). 트랙의 아이템박스를
통과하면 순위 기반 룰렛(`items/item_table.gd`)으로 7종 아이템 중 하나가
결정되고, `items/item_manager.gd`가 풀링된 아이템 인스턴스의 생성·틱·회수를
전담한다(발사체/유도/트랩/부스트/실드/범위/리더 견제 7개 카테고리 —
`ARCHITECTURE.md`의 Items pipeline 참고). 아이템 on/off는
`RaceConfig.items_enabled`/`tools/run_sim.sh --items on|off`로 전환한다.

프레젠테이션은 카트 물리와 분리되어 있다. `RaceCamera`는 속도
방향/드리프트 blend, wall clipping, 0.15초 look-back, speed² + boost spring
FOV와 trauma² shake를 적용한다. 카트는 body roll/pitch, suspension bob,
wheel steer/spin/jitter, trick/hit/squash와 shader flash를 표시한다. 연속
ring-buffer skid strip, terrain smoke, tier sparks, boost exhaust, edge-only
speed lines, pooled impact/dust/sparks, optional hit-stop, HUD Tween도
race와 sandbox에 동일하게 연결된다. `SettingsManager`의
`shake_strength`/`fov_effect_strength`는 0–100이며 0에서도 기본 주행과
카메라 추적은 유지된다. 오디오/비디오/조작/접근성/게임플레이 설정과
key/button/axis 리맵은 즉시 적용되고 `settings.cfg`에 저장된다.

- [`KART_RACING_DEV_PROMPT.md`](KART_RACING_DEV_PROMPT.md) — 개발 프롬프트 전체 (아키텍처, 물리, 드리프트, 아이템, AI, Phase 0~15, DoD, 작업 규칙)
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — 실제 경로와 시스템 경계
- [`DEVLOG.md`](DEVLOG.md) — Phase별 구현 및 검증 기록

## 실행

```sh
/opt/homebrew/bin/godot --path .
```

메인 메뉴는 방향키/D-pad/좌스틱으로 이동하고 Enter/Space/A로 선택,
Esc/B로 뒤로 간다. Play에서 드라이버·카트·트랙·난이도를 고르면 레이스가
시작된다.
Phase 1-4 주행 샌드박스는 계속 직접 열 수 있다:

```sh
/opt/homebrew/bin/godot --path . scenes/test/kart_sandbox.tscn
```

## 조작

| 상황 | 키보드 | 게임패드 |
|---|---|---|
| 메뉴 이동 | 방향키 | D-pad / 좌스틱 |
| 선택 | Enter / Space | A |
| 뒤로 | Esc | B |
| 가속 | W | RT / A |
| 브레이크·후진 | S | LT / B |
| 조향 | A / D | 좌스틱 |
| 드리프트·트릭 | Space | RB / X |
| 아이템 사용 | E | LB / Y |
| 뒤돌아보기 | Q | 오른쪽 스틱 아래 |
| 일시정지 | Esc | Start |
| 디버그 오버레이 | F3 | — |

드리프트는 유지 후 놓으면 도달한 티어만큼 미니 터보를 준다. Pause와
Results도 방향키/D-pad/좌스틱 + Enter/A로 완전히 조작할 수 있다.

샌드박스 전용: `R` 리셋, `T` 트랙 순환
(평지→언덕→헤어핀→Track01), `4` 헤어핀 트랙 바로
선택, `5` Track01(Ridgeline Circuit) 바로 선택, `1`/`2`/`3`
light/medium/heavy 전환, `B` 충돌용 더미 카트 3대 생성, `A` 현재 트랙에
normal 난이도 AI 카트 7대(`AiKart1`..`AiKart7`) 생성, `I` 플레이어 카트에
7종 아이템을 순환 지급(룰렛 없이 즉시) — 트랙을 바꾸면 AIController가
들고 있던 이전 트랙의 RacingLine/지름길/아이템박스 참조가 무효화되므로
자동으로 정리된다. F3으로 terrain/slipstream/hit/invulnerable/air_time,
drift_state/drift_charge/drift_tier/boost/trick_armed,
lap/next_checkpoint/progress/wrong_way에 더해 AI 카트 1의
ai_target_speed/ai_rubber_band/ai_lane_offset(§13.7 고무줄 배율이 "보이지
않는 치트"가 되지 않도록 항상 노출)과 `slot_item`/`roulette`/
`active_projectiles`/`shield`를 본다.

## 검증

```sh
# 최초 1회 import와 UID 생성
HOME=$PWD/.tmp-home /opt/homebrew/bin/godot --headless --path . --import

# 파싱 / 부팅 확인
HOME=$PWD/.tmp-home /opt/homebrew/bin/godot --headless --path . --quit

# GUT 전체 테스트
HOME=$PWD/.tmp-home tools/run_tests.sh

# 트랙 구조 검증 (test_loop + test_loop_hills + test_hairpin + track_01, §15.5 전체)
HOME=$PWD/.tmp-home tools/validate_tracks.sh

# Track01, normal 난이도, 3랩, 8카트, 1회 (기본값) — 실제 AI 레이스
HOME=$PWD/.tmp-home tools/run_sim.sh

# §13.8 DoD: 난이도별 3회씩 실행해 평균 랩타임 순서(easy > normal > hard)를 비교
HOME=$PWD/.tmp-home tools/run_sim.sh --races 3 --difficulty easy
HOME=$PWD/.tmp-home tools/run_sim.sh --races 3 --difficulty normal
HOME=$PWD/.tmp-home tools/run_sim.sh --races 3 --difficulty hard

# 다른 트랙/랩수/카트수 조합, 빠른 반복용
HOME=$PWD/.tmp-home tools/run_sim.sh --laps 1 --karts 4 --races 1 --track test_hairpin

# §12.4 아이템 밸런스 게이트: 20레이스, normal, 8카트, 3랩
HOME=$PWD/.tmp-home tools/run_sim.sh --races 20 --difficulty normal --karts 8 --laps 3

# 아이템 없이 비교(레이스 흐름/AI 판단만 검증)
HOME=$PWD/.tmp-home tools/run_sim.sh --races 3 --items off

# Phase 8 실제 렌더 성능: 12-kart, 2초 warm-up 뒤 30초 측정
# (headless는 렌더러 FPS 근거로 사용할 수 없음)
tools/perf_check.sh 12 30
```

Phase 9 headless 기준선은 **349/349 tests, 1,825 assertions**, track validator
**4/4**, script parse error 0이다. 실제 화면 대비/레이아웃과 물리 gamepad
감각은 `DEVLOG.md`의 Phase 9 플레이 지시로 별도 확인한다.

인자: `--races N`(기본 1), `--difficulty easy|normal|hard`(기본 normal,
모든 카트에 동일 적용), `--laps N`(기본 3), `--karts N`(기본 8, 최대 8),
`--track track_01|test_hairpin|test_loop|test_loop_hills`(기본 track_01,
모르는 이름은 track_01로 대체), `--items on|off`(기본 on). 카트 전원이
AI이며(`RaceConfig.player_slot = -1`) 사람 플레이어는 없다. 한 카트라도
미완주, 리스폰 2회 초과, 또는 전체 벽 정면충돌이 `3 * laps`를 넘으면
exit 1; `--races 20 --difficulty normal`(기본 카트/랩 수) 조합은 추가로
아이템 밸런스 게이트(레이스당 평균 랭크1위 피격 ≤3, 랭크8위 카트의 평균
랭크 상승 ≥1.5)도 통과해야 한다. 매 레이스마다 `--races`
반복 시 `RaceConfig.seed`를 레이스 번호로 바꿔 동일 레이스를 반복하지
않는다. 출력 JSON의 `races[].{drifts_started,tier3_releases,
shortcut_takes,wall_head_on_count,respawns,times,items_used,item_hits,
rank_one_hits,rank_eight_gain}`와 `summary.mean_lap_time_seconds`(완주자
전원의 `총시간/laps` 평균)를 확인한다;
`run_sim.sh`는 마지막 줄에 `summary: ...`로도 따로 찍는다.

`HOME=$PWD/.tmp-home`은 제한된 샌드박스에서만 필요하다. 일반 로컬
환경에서는 접두어 없이 같은 명령을 실행할 수 있다.

`perf_check.sh`는 마지막에 `PERF_PROBE` JSON으로 `mean_fps`,
`worst_frame_ms`, `gpu_particles`, `renderer`를 출력한다. Phase 8 구현은
12대에서 GPU particle node 60/60(카트당 5/6)을 정적으로 검증했지만,
현재 자동화 샌드박스는 macOS 렌더 창을 열지 못해 실제 FPS 숫자는 아직
기록하지 못했다. unrestricted 로그인 세션에서 위 명령을 실행해 8-kart
F3 FPS ≥60 게이트와 함께 확정한다.

## 트랙 제작 흐름 (§15.6)

1. `track/track_template.tscn`을 `track/tracks/track_xx_<이름>/`로 복제한다.
   RacingLine 노드는 이미 `track/racing_line.gd`가 연결돼 있다 — 커브가
   비어 있으면 placeholder 타원을 자동으로 채우므로, 자체 커브를 만들
   서브클래스 스크립트(예: `test_hairpin/hairpin_racing_line.gd`,
   `track_01_ridgeline_circuit/track_01_line.gd`처럼 `extends RacingLine`
   하고 `_ready()`에서 `curve = Curve3D.new()`)를 새로 만들어 연결한다.
   커브는 항상 코드로 만든다 — `.tscn`에 `Curve3D`를 직접 직렬화하지 않는다
   (포맷이 문서화되어 있지 않고 실제로 파싱 실패를 낸 적이 있다).
2. 그레이박스: `tools/track_builder.gd`의 `TrackBuilder.build_road_segments()`/
   `add_box_segment()`로 RacingLine을 따라 도로/벽 박스를 절차적으로 생성하거나
   (`track_01_ridgeline_circuit/track_01_track.gd` 참고), CSG/Primitive로 직접
   배치한다. 폭 12~16m, 벽 높이 2m 권장.
3. 체크포인트 자동 배치: `tools/place_checkpoints.gd`를 실행하면 RacingLine을
   N등분한 위치에 `Checkpoint`(RespawnPoint 포함, 진행 방향으로 정렬)를 만들고
   씬을 재저장한다.
   ```sh
   godot --headless --path . -s tools/place_checkpoints.gd -- \
     res://track/tracks/track_xx_<이름>/track_xx_<이름>.tscn 8
   ```
4. StartGrid(Marker3D ≥8), ItemBoxes(≥6, 라인 8m 이내), KillZones(트랙
   바닥 전체를 덮는 평면), BoostPads/JumpPads/OffroadZones/Hazards/
   MovingObstacles/Shortcuts를 배치한다.
5. 검증 후 완주 확인:
   ```sh
   godot --headless --path . -s track/track_validator.gd -- \
     res://track/tracks/track_xx_<이름>/track_xx_<이름>.tscn
   tools/run_sim.sh --laps 1 --karts 4 --races 1
   ```
   `run_sim.sh`는 이제 실제 AI(추월/회피/난이도/지름길 판단 포함)로 전원
   완주를 확인한다. 새 트랙은 `Shortcuts`에 `TrackShortcut`을 아직 두지
   않았다면 지름길 판단은 자연히 skip되고 나머지 항목만 검증된다.
6. 샌드박스에서 직접 확인하려면 `scenes/test/kart_sandbox.gd`의
   `TRACK_SCENES`/`TRACK_NODE_NAMES`에 트랙을 추가하고 숫자 키를 배정한다
   (Track01은 `5`).

## 워크플로우

- `main`은 항상 승인된 Phase까지만 포함.
- 모든 변경은 PR로만 머지.
- Phase 완료 보고는 `DEVLOG.md`에 누적한다.

## 시각 검증 (윈도우 모드)

```bash
godot --path . res://scenes/test/drive_snapshot.tscn -- /tmp/drive 20 4   # 자동 주행 20초, 4초마다 PNG
godot --path . -s tools/snapshot.gd -- res://scenes/test/kart_sandbox.tscn /tmp/shot.png 90
```

> 새로 클론한 뒤에는 먼저 `godot --headless --path . --import`를 한 번 실행해 class_name 캐시를 만들어야 한다.
