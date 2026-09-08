# arcade-kart-racer

Mario Kart에서 *시스템과 플레이 감각*만 영감을 받은 **완전 오리지널 3D 아케이드 카트 레이싱 게임** 프로젝트.
엔진: **Godot 4.7 + GDScript**.

## 이 레포의 현재 상태

**Phase 5 — 레이스 흐름 완료.**

현재 메인 씬은 "Press Enter / Start to race" 플레이스홀더 메뉴다. 시작하면
Track01 Ridgeline Circuit, 3랩, 8카트, medium 카트의 실제 레이스가 열리며
3-2-1-GO/스타트 부스트, 랩·순위·리스폰·카트 충돌, FINISHING 타임아웃,
결과/재시작/메뉴, 일시정지, 임시 HUD(순위/랩/WRONG WAY/FINAL LAP/FINISH/
기존 드리프트 미터)가 연결된다. 상대 카트는 Phase 5 완주 검증용 단순
레이싱라인 추종기이며, 판단형 AI와 아이템 효과는 Phase 6/7 범위다.

- [`KART_RACING_DEV_PROMPT.md`](KART_RACING_DEV_PROMPT.md) — 개발 프롬프트 전체 (아키텍처, 물리, 드리프트, 아이템, AI, Phase 0~15, DoD, 작업 규칙)
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — 실제 경로와 시스템 경계
- [`DEVLOG.md`](DEVLOG.md) — Phase별 구현 및 검증 기록

## 실행

```sh
/opt/homebrew/bin/godot --path .
```

메인 씬에서 Enter/Space 또는 게임패드 A/Start를 눌러 기본 레이스를 시작한다.
Phase 1-4 주행 샌드박스는 계속 직접 열 수 있다:

```sh
/opt/homebrew/bin/godot --path . scenes/test/kart_sandbox.tscn
```

레이스 조작: 가속 `W`/RT/A, 브레이크·후진 `S`/LT/B, 조향
`A`/`D`/좌스틱,
`Space`/RB 드리프트(유지 후 놓으면 도달한 티어만큼 미니 터보 부스트),
`Esc`/게임패드 Start 일시정지. pause/results 버튼은 방향키·D-pad/좌스틱과
Enter/A로 이동·선택한다. 샌드박스 전용: `R` 리셋, `T` 트랙 순환
(평지→언덕→헤어핀→Track01), `4` 헤어핀 트랙 바로
선택, `5` Track01(Ridgeline Circuit) 바로 선택, `1`/`2`/`3`
light/medium/heavy 전환, `B` 충돌용 더미 카트 3대 생성.
F3으로 terrain/slipstream/hit/invulnerable/air_time,
drift_state/drift_charge/drift_tier/boost/trick_armed에 더해
lap/next_checkpoint/progress/wrong_way를 본다.

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

# Track 01 실제 scripted race (기본 3랩, 8카트, 1회)
HOME=$PWD/.tmp-home tools/run_sim.sh

# 빠른 DoD 예시: 1랩, 4카트, 1회; JSON 출력, DNF가 있으면 exit 1
HOME=$PWD/.tmp-home tools/run_sim.sh --laps 1 --karts 4 --races 1
```

`HOME=$PWD/.tmp-home`은 제한된 샌드박스에서만 필요하다. 일반 로컬
환경에서는 접두어 없이 같은 명령을 실행할 수 있다.

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
   Phase 5의 `ScriptedRaceInputProvider`로 실제 레이스 흐름과 전원 완주를
   확인한다. 추월/회피/난이도 판단을 포함한 AI 시뮬레이션은 Phase 6에서
   같은 JSON/exit-code 계약을 이어받는다.
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
