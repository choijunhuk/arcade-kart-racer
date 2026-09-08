# arcade-kart-racer

Mario Kart에서 *시스템과 플레이 감각*만 영감을 받은 **완전 오리지널 3D 아케이드 카트 레이싱 게임** 프로젝트.
엔진: **Godot 4.7 + GDScript**.

## 이 레포의 현재 상태

**Phase 4 — 트랙 시스템 & 체크포인트 완료.**

현재 메인 씬은 실제로 주행 가능한 카트(`kart/kart.tscn`), 전환 가능한
네 테스트 트랙(평지/언덕/헤어핀/Track01 Ridgeline Circuit), 지형 감속,
슬립스트림, 무게 기반 카트 충돌, 피격 반응, 미니 터보 드리프트, 통합
부스트 스택, 부스트 패드/점프대/트릭, 체크포인트 순서·랩 판정
(`LapTracker`), 진행도·순위(`PositionTracker`), 레이싱 라인 기준 리스폰
(`RespawnSystem`), 아이템박스/장애물/지름길 트랙 요소, 스프링 추적
카메라, 드리프트 미터 + "LAP x/3" HUD와 F3 디버그 오버레이가 있는
샌드박스를 연다. 레이스 흐름(카운트다운/결과)·아이템 효과·AI는 이후
범위다.

- [`KART_RACING_DEV_PROMPT.md`](KART_RACING_DEV_PROMPT.md) — 개발 프롬프트 전체 (아키텍처, 물리, 드리프트, 아이템, AI, Phase 0~15, DoD, 작업 규칙)
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — 실제 경로와 시스템 경계
- [`DEVLOG.md`](DEVLOG.md) — Phase별 구현 및 검증 기록

## 실행

```sh
/opt/homebrew/bin/godot --path .
```

메인 씬을 통해 실행하면 `scenes/test/kart_sandbox.tscn`이 자동으로 열린다.
같은 샌드박스를 직접 열 수도 있다:

```sh
/opt/homebrew/bin/godot --path . scenes/test/kart_sandbox.tscn
```

조작: 가속 `W`/RT, 브레이크·후진 `S`/LT, 조향 `A`/`D`/좌스틱,
`Space`/RB 드리프트(유지 후 놓으면 도달한 티어만큼 미니 터보 부스트),
`R` 리셋, `T` 트랙 순환(평지→언덕→헤어핀→Track01), `4` 헤어핀 트랙 바로
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

# Phase 6 전까지 성공 메시지만 출력하는 시뮬레이션 자리표시자
tools/run_sim.sh
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
   tools/run_sim.sh   # AI 완주 확인은 Phase 6부터
   ```
   AI 시뮬레이션이 없는 지금은 `tests/support/scripted_input_provider.gd`
   (`ScriptedInputProvider`)로 레이싱 라인을 따라 자동 주행시켜 랩 완주를
   확인한다 — `tests/integration/test_track01_auto_drive.gd`가 그 예시다.
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
