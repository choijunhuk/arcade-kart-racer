# Development Log

## Phase 3 보고 — 드리프트 & 부스트

### 구현된 기능

- `DriftController`: NONE→HOP→HOLD→RELEASE 상태 머신. hop은
  `KartPhysics.hop()`을 통한 수직 임펄스, 방향은 hop 종료 시 조향 부호로
  잠금, HOLD 중 저속(0.4초)·HIT·공중(0.5초 초과)·강한 반대 조향(0.3초) 취소,
  종료 후 0.35초 쿨다운을 구현했다. 차지는 `base_charge_rate`,
  `steer_alignment_bonus`, yaw rate 기반 `turn_quality`(< `min_drift_yaw_rate`
  일 때 `low_turn_quality_mult`), `KartData.drift_factor`로 결정되며 절대
  감소하지 않는다. `PhysicsTuning.mini_turbo_tiers`에 1.0s/1.18×/0.8s(cyan),
  2.2s/1.25×/1.4s(amber), 3.6s/1.33×/2.2s(magenta) 3티어를 채웠다.
  공중에서 `trick_min_air_time` 이상 체공 중 드리프트 버튼을 누르면 트릭이
  arm되고, 착지 시 `trick_boost`를 요청한다.
- 드리프트 물리: HOLD 중 yaw rate는
  `dir * (drift_base_turn + steer*dir*drift_steer_influence) * drift_factor`
  로 방향을 절대 뒤집지 않으며, 접지력은 `drift_grip`으로 대체되고 속도는
  `drift_speed_retention`을 `pow(retention, dt)`로 프레임독립적으로 적용한다.
- `BoostController`: 단일 비가산 부스트 슬롯. `request(spec, source)`는
  더 강한 `speed_mult`면 교체, 약하거나 같으면 `max_boost_duration`까지
  잔여시간을 연장한다. `ignores_offroad`는 `TerrainSensor.sample()`로
  전달되어 지형 페널티를 우회한다. Phase 2의 slipstream 이탈 임시
  멀티플라이어를 `BoostController.request()` 경로로 완전히 이관했다
  (slipstream 활성 중 배수는 `SlipstreamSensor` 소유로 유지). 순수 함수
  `evaluate_start_input(frame, countdown_phase)`로 §11 시작 부스트/휠스핀
  판정을 Phase 5가 재사용할 수 있게 분리했다(카운트다운 UI는 미구현).
- `BoostPad`(layer 5 Area3D)는 카트 진입 시
  `boost_controller.request(tuning.boost_pad_boost, &"boost_pad")`를 호출한다.
  `JumpPad`는 `KartPhysics.launch(local_velocity)`로 카트를 AIRBORNE으로
  전환한다. `test_loop`에 부스트 패드 2개, `test_loop_hills`에 점프대 1개와
  착지 구역을 배치했다. 반경 18 m 180도 헤어핀 2개와 고속 S커브를 가진
  신규 그레이박스 트랙 `track/tracks/test_hairpin/`을 추가했다(검증 통과).
- 연출: `DriftEffects`(타이어 스파크 — 티어별 cyan/amber/magenta, 지형색
  타이어 연기), `BoostEffects`(배기 파티클), `SkidMark`(링버퍼 스트립
  메시)를 신호 구독만으로 구현했다(물리 쓰기 없음, 카트당 파티클 노드
  ≤6개). `KartVisuals`는 드리프트 시각 요 오프셋과 트릭 스핀을 적용한다.
  `RaceCamera`는 드리프트 반대 방향 사이드 오프셋과 부스트 FOV 스프링킥을
  추가했다.
- `ui/hud/drift_meter.gd`(+tscn): 차지 바 + 티어 색 Control, 읽기 전용
  `DriftController` API만 구독한다. 샌드박스 HUD CanvasLayer 자식으로 추가.
- 샌드박스: 드리프트/부스트/트릭 상태 디버그 워치 5종을 추가했고, 키 `4`로
  `test_hairpin` 트랙을 선택할 수 있다. `ScriptedInputProvider`에 곡률
  기반 "코너에서 드리프트" 선택 모드를 추가했다(기존 레이스라인 추종
  기본값은 그대로 유지).

### 생성/수정된 파일

- 신규: `kart/drift_controller.gd`, `kart/boost_controller.gd`,
  `effects/drift_effects.{gd,tscn}`, `effects/boost_effects.{gd,tscn}`,
  `effects/skid_mark.gd`, `track/elements/boost_pad.{gd,tscn}`,
  `track/elements/jump_pad.{gd,tscn}`, `track/tracks/test_hairpin/*`,
  `ui/hud/drift_meter.{gd,tscn}`, Phase 3 unit/integration 테스트와 UID.
- 수정: `kart/kart_controller.gd`, `kart/kart_physics.gd`,
  `kart/kart_visuals.gd`, `kart/kart.tscn`, `kart/slipstream_sensor.gd`,
  `camera/race_camera.gd`, `data/schemas/physics_tuning.gd`,
  `data/schemas/feel_tuning.gd`, `data/tuning/physics_default.tres`,
  `data/tuning/feel_default.tres`, `scenes/test/kart_sandbox.{gd,tscn}`,
  `scenes/test/drive_snapshot.gd`, `tests/support/scripted_input_provider.gd`,
  `track/tracks/test_loop/test_loop.tscn`,
  `track/tracks/test_loop_hills/test_loop_hills.tscn`,
  `tools/validate_tracks.sh`, 기존 회귀 테스트, 문서.

### 핵심 설계 결정과 이유

- `DriftController`/`BoostController`는 `configure(tuning, kart_data)` +
  명시적 `step()`/`request()` API로 씬 트리 없이도 단위 테스트가
  가능하다. `KartController`는 결과 오브젝트(`DriftResult`/`BoostResult`)만
  `KartPhysics.integrate()`에 전달하고 물리 쓰기는 `KartPhysics`가 전담한다.
- 미니 터보 차지율은 `steer=0.0`일 때 정확히 `base_charge_rate`
  (=1.0/초)와 같도록 설계해, §10.4의 1.0s/2.2s/3.6s 티어 표가 "초"라는
  이름 그대로 정렬 없는 순수 유지 시간과 일치하는 것을 단위 테스트로
  고정했다. 이 계약 때문에 정렬 보너스나 기본 차지율은 헤어핀
  자동주행 테스트를 통과시키기 위해 임의로 올리지 않았다.
- `track/tracks/test_hairpin/hairpin_racing_line.gd`의 헤어핀은 단일
  꼭짓점(스파이크)이 아니라 30도 간격 다중 점으로 구성한 진짜 원호다.
  단일 꼭짓점 근사는 3점 유한차분 곡률 추정이 짧은 스파이크만 보고하여
  드리프트에 필요한 지속 곡률 신호를 주지 못했다.
- `ScriptedInputProvider`의 곡률 기반 드리프트 모드는 헤어핀
  진입/유지/탈출에 세 가지 보강이 필요했다: (1) 진입 임계값보다 훨씬 낮은
  이탈 임계값(히스테리시스)으로 코너 중간의 곡률 미세 하강이 조기
  해제를 유발하지 않게 하고, (2) 순수 추적 조향은 `drift_min_steer`에
  거의 도달하지 못하므로 코너가 충분히 날카로울 때 조향 크기를
  최소값까지 "플릭"하며, hop이 끝나기 전에 되돌리면 매 틱 최소 조향
  검사에 걸려 즉시 취소되므로 HOP 전체 구간에서 플릭을 유지하고,
  (3) HOLD 중에는 잠근 방향으로 조향을 클램프(부스트하지 않음)해 자연
  진동이 반대 조향 취소를 유발하지 않게 했다. (2)에 필요한 최소 조향은
  `PhysicsTuning.drift_min_steer`를 테스트 지원 코드에 문서화된 상수로
  미러링한 것이며 게임플레이 튜닝 자체는 건드리지 않았다.
- 곡률이 높은 다가오는 코너에서는 드리프트 모드 여부와 무관하게
  `safe_speed = sqrt(대표_그립 * 반경)`으로 미리 감속한다(순수 추종
  로직만으로는 18 m 반경 코너를 일반 접지력으로 버틸 수 없어 크게
  슬라이드했다). 단, 실제 HOLD 중에는 이 감속을 끄고
  `DriftController`의 자체 `drift_speed_retention`에 맡긴다 — 겹치면
  차지 시간이 굶주리고 저속 취소로 즉시 드리프트가 끊겼다.
- `test_phase3_hairpin.gd`의 한 바퀴 완료 판정은 `Curve3D.get_closest_offset()`
  델타가 아니라 누적 월드 거리 + 시작점 반경 복귀로 측정한다. 이 트랙의
  두 직선은 서로 가깝고 평행해 커브 오프셋이 모호해질 수 있다.

### 실행 방법

```sh
/opt/homebrew/bin/godot --path . scenes/test/kart_sandbox.tscn
```

### 테스트 방법 및 결과 (run_tests / validate_tracks 실제 출력 요약)

- `godot --headless --path . --import` — exit 0, 신규 UID 생성/추적.
- `godot --headless --path . --quit` — exit 0, ERROR/SCRIPT ERROR 없음
  (dummy renderer의 RID 누수 한 줄은 무해함).
- `tools/run_tests.sh` — GUT 9.6.1, 21 scripts, **101 tests / 101 passing**
  (Phase 2 종료 시점 62개 대비 39개 신규), 518 assertions, 0 failures.
- `tools/validate_tracks.sh` — `test_loop`, `test_loop_hills`,
  `test_hairpin` 모두 PASS.
- 최대 production GDScript 395줄(`kart/kart_physics.gd`)로 400줄 제한 이내.

### 현재 문제점 / 알려진 버그

- `test_hairpin`의 접지 지오메트리는 벽이 없는 평탄한 그레이박스라
  일반(비드리프트) 상태로 헤어핀을 고속 진입하면 슬라이드가 크다;
  `ScriptedInputProvider`는 이를 곡률 기반 예측 제동으로 보정하지만
  실제 플레이어 대상 카메라/HUD 경고는 Phase 8/9 범위다.
- 시각 연출(스파크 색, 스키드 마크 폭 등)은 headless 환경에서 사람 눈
  검증이 불가능하다 — 아래 플레이 지시로 창 모드에서 확인이 필요하다.

### TODO / PLACEHOLDER 목록

- TODO(phase-4): authored RacingLine/checkpoints/RespawnPoint 기반 리스폰,
  banked geometry 정렬, item-box 및 kill-zone coverage validator 완성
  (Phase 2 보고에서 이월).
- TODO(phase-5): `BoostController.evaluate_start_input()`을 실제 카운트다운
  UI/입력과 연결.
- TODO(phase-9): `ui/hud/drift_meter`를 실제 레이스 HUD로 교체.

### 다음 Phase 계획

Phase 4에서 체크포인트/랩 진행, 아이템, AI 드라이버를 구현한다. 사용자
승인 전 시작하지 않는다.

### 사용자에게 필요한 결정 (있다면)

없음. 아래 절차로 Phase 3의 드리프트 티어, 반대 조향, 부스트, 트릭 감각을
확인하면 된다.

### 플레이 지시

```text
1. 실행 후 F3으로 디버그 오버레이를 켜서 drift_state/drift_charge/
   drift_tier/boost/trick_armed을 확인할 수 있게 한다.
2. 아무 트랙에서나 코너 진입 직전 Space/RB를 눌러 살짝 hop한 뒤 계속
   눌러 유지한다 — 카트가 사이드로 미끄러지며 도는지, 방향이 조향과
   반대로는 절대 뒤집히지 않는지 확인한다.
3. 드리프트를 1초 이상 유지해 타이어 스파크가 cyan(티어1)으로 바뀌는지,
   더 오래 유지하면 2.2초/3.6초에서 amber/magenta로 바뀌는지 확인한다.
   Space/RB를 떼면 도달한 티어에 비례한 부스트가 걸리는지 본다.
4. 드리프트 중 조향을 반대로 세게 꺾어 0.3초 이상 유지하면 드리프트가
   취소되고(부스트 없이) 짧은 쿨다운 뒤에만 다시 시작할 수 있는지 확인한다.
5. 저속에서 드리프트를 시도해(속도가 `drift_cancel_speed` 아래로
   떨어지도록 감속하며 유지) 자동으로 취소되는지 확인한다.
6. `4`로 test_hairpin을 연다. 첫 번째 18 m 헤어핀에서 드리프트를 걸어
   빠져나가고, 뒤이은 S커브에서는 짧게 좌우로 드리프트를 끊어 스네이킹이
   과도한 차지를 만들지 않는지 확인한다.
7. `T`로 test_loop_hills를 열어 점프대를 넘는다 — 착지 전 체공 중
   Space/RB를 눌러 트릭을 arm하고, 착지 순간 자동으로 트릭 부스트가
   걸리며 짧은 스핀 연출이 나오는지 확인한다.
8. 부스트 패드가 있는 test_loop 뒷직선을 지나 최고속을 순간적으로
   넘어서고, 부스트가 끝난 뒤 `overspeed_decay`로 서서히 정상 최고속으로
   돌아오는지 확인한다.
9. 기대 감각: 드리프트가 느슨하지 않고 의도적인 입력에 반응하며, 티어가
   오를수록 확실한 보상감이 있어야 한다. 반대 조향과 저속 취소는
   즉각적이고 예측 가능해야 한다.
```

---

## Phase 2 보고 — 아케이드 물리 심화

### 구현된 기능

- `TerrainSensor` + `OffroadZone`: Area 우선, collider `terrain` metadata,
  asphalt fallback 순서와 카트별 offroad resistance를 적용했다.
- `SlipstreamSensor`: layer 2 전방 ShapeCast, 동일 방향 판정, 1.5초 차지,
  활성 최고속 1.08배, 이탈 보너스 0.8초를 구현했다.
- `KartCollisionResolver`: BumpArea 쌍당 1회 처리, 질량비 임펄스, 측면
  횡속도 교환/yaw, 후방 추돌 push, 위치 분리를 구현했다. HIT는 발생하지 않는다.
- `HitReactor`: BUMP/SPIN_OUT/TUMBLE/SQUASH 지속시간·속도·조작 규칙,
  1.2초 무적, EventBus 이벤트, wall head-on BUMP, 시각 spin/flip/flatten을 구현했다.
- 공중/착지: 2틱 초과 접지 실패 후 AIRBORNE, air steer, air_time API,
  착지 속도손실 상한 및 큰 진행방향 오차의 lateral 제거를 구현했다.
- `KillZone` + `RespawnSystem`: 0.4초 fade 대기, StartGrid 뒤쪽 지점 이동,
  속도 0/1초 무적/0.6초 freeze, 5초 stuck 감지를 물리 틱으로 구현했다.
- 두 트랙에 kill plane을, 평지 트랙에 grass 2곳을, hills에 dirt·동쪽
  탈출 gap·1.5m ledge를 배치했다.
- 샌드박스에 `T`, `1/2/3`, `B` 조작과 collision/respawn 조립,
  Phase 2 debug watch를 추가했다. 기존 3종 KartData는 §9.11 수치를 이미 만족했다.

### 생성/수정된 파일

- 신규: `kart/terrain_sensor.gd`, `kart/slipstream_sensor.gd`,
  `kart/hit_reactor.gd`, `race/kart_collision_resolver.gd`,
  `race/respawn_system.gd`, `track/elements/offroad_zone.{gd,tscn}`,
  `track/elements/kill_zone.{gd,tscn}`, Phase 2 unit/integration tests와 UID.
- 수정: `kart/kart_controller.gd`, `kart/kart_physics.gd`,
  `kart/kart_visuals.gd`, `kart/kart.tscn`, `PhysicsTuning`, 양 테스트 트랙,
  샌드박스, `project.godot`, 문서와 기존 회귀 테스트.

### 핵심 설계 결정과 이유

- terrain/slipstream/landing/impulse 계산을 순수 정적 함수로 분리해 장면
  프레임 순서와 무관하게 수학 계약을 검증한다.
- Phase 3 `BoostController`를 앞당기지 않고 slipstream만 기존
  `BoostResult` seam으로 전달한다.
- 벽 입사각은 `move_and_slide()` 전 속도로 계산한다. 이후 속도는 이미 벽
  평행 성분으로 투영되어 정면 충돌 정보를 잃기 때문이다.
- respawn 위치는 callable로 주입해 Kart가 Race/Track을 직접 참조하지 않는다.
  Phase 4까지는 RacingLine offset 기준 뒤쪽 StartGrid를 사용한다.
- hit 회전/뒤집힘/납작해짐은 `KartVisuals` 전용이며 물리 basis는 yaw-only다.

### 실행 방법

```sh
/opt/homebrew/bin/godot --path . scenes/test/kart_sandbox.tscn
```

### 테스트 방법 및 결과 (run_tests / run_sim / validate_tracks 실제 출력 요약)

- `godot --headless --path . --import` — exit 0, 신규 UID 생성/추적.
- `godot --headless --path . --quit` — exit 0, ERROR/SCRIPT ERROR 없음.
- `tools/run_tests.sh` — GUT 9.6.1, 16 scripts, **62 tests / 62 passing**,
  417 assertions, 0 failures.
- `tools/validate_tracks.sh` — `test_loop`, `test_loop_hills` 모두 PASS.
- `tools/run_sim.sh` — Phase 6 전 성공 placeholder, exit 0.
- 최대 production GDScript 332줄로 400줄 제한 이내.

### 현재 문제점 / 알려진 버그

- 자동 테스트는 물리·상태 전이를 검증하지만 주행 감각과 시각 변형은
  headless 환경에서 사람 눈으로 판정할 수 없어 아래 플레이 확인이 필요하다.
- hills의 banked corner는 Phase 1의 fixed-roll placeholder다.

### TODO / PLACEHOLDER 목록

- TODO(phase-3): `DriftController`와 일반 `BoostController`; slipstream exit
  보너스 이관 및 boost의 offroad 무시 훅 연결.
- TODO(phase-4): authored RacingLine/checkpoints/RespawnPoint 기반 리스폰,
  banked geometry 정렬, item-box 및 kill-zone coverage validator 완성.
- PLACEHOLDER: `tools/run_sim.sh` AI 레이스는 Phase 6에서 구현.

### 다음 Phase 계획

Phase 3에서 드리프트 상태 머신, 차지/미니 터보, 통합 BoostController,
BoostPad/JumpPad/트릭과 관련 연출을 구현한다. 사용자 승인 전 시작하지 않는다.

### 사용자에게 필요한 결정 (있다면)

없음. 아래 절차로 Phase 2의 충돌·지형·공중·복귀 감각을 확인하면 된다.

### 플레이 지시

```text
1. 실행 후 W/A/S/D로 주행하고 F3을 켠다.
2. test_loop의 초록 grass patch를 안쪽으로 가로질러 terrain=grass와 감속,
   asphalt 복귀 뒤 자연스러운 재가속을 확인한다.
3. B로 light/medium/heavy 더미 3대를 앞에 세운 뒤 부딪힌다. 1/2/3으로
   플레이어 무게를 바꿔 heavy는 덜 밀리고 light는 더 밀리는지 비교한다.
4. 더미 뒤를 같은 방향으로 1.5초 이상 달려 slipstream=true와 추가 최고속,
   빠져나온 뒤 약 0.8초의 짧은 보너스를 확인한다.
5. 벽을 스치기/정면으로 각각 충돌해 정면만 BUMP/HIT가 잠깐 표시되고,
   카트가 벽에 고정되지 않고 조작을 회복하는지 확인한다.
6. T로 hills로 바꾸고 남쪽 직선의 ramp→1.5m ledge를 넘어 AIRBORNE과
   안정된 착지를 확인한다. 동쪽 벽 중앙 gap으로 이탈해 3초 안에 grid로
   돌아오고 speed=0인지 확인한다.
7. 기대 감각: offroad는 분명하지만 답답하지 않고, heavy/light 몸싸움 차이가
   읽히며, 낙하와 벽 충돌 후 흐름이 빠르게 이어져야 한다.
```

---

## Phase 1 보고 — 기본 카트 컨트롤러

### 구현된 기능

- `KartController` (`kart/kart_controller.gd`): `CharacterBody3D` 루트,
  `KartData`/`PhysicsTuning` export, `set_input_provider()`, §9.3 틱
  순서(1/3/6/8 실구현, 2/4/5/7 중립 스텁), 읽기 전용 API 8종, `state_changed`
  시그널. 카트는 `Input` 싱글턴을 절대 읽지 않는다.
- `KartPhysics` (`kart/kart_physics.gd`): 종/횡 스칼라 속도 모델, 가속
  곡선 샘플링, 브레이크/후진/드래그/오버스피드 감쇠, 속도 기반 조향
  곡선(지면 법선 축 회전), 요(yaw) 기반 횡미끄러짐 + grip 지수 감쇠, 5-ray
  접지 판정(경사 각 초과 히트는 벽으로 취급해 제외), hover snap, up 벡터
  slerp 정렬(접지 시 지면 법선, 공중 시 월드 업으로 서서히), 경사 중력
  성분, 착지 감속(상한 有), `move_and_slide()` 후 벽 충돌 후처리
  (`get_slide_collision`), 그리고 씬 상태 없이 테스트 가능한 순수 정적
  함수 `KartPhysics.compute_wall_response()`. 카트는 요만 회전하며 물리적
  으로 절대 뒤집히지 않는다.
- `KartVisuals` (`kart/kart_visuals.gd`): 컨트롤러 공개 API만 읽는
  `_process` 전용 바디 롤/피치, 휠 회전/조향, 착지 서스펜션 bob(스프링
  감쇠). 물리 상태를 절대 바꾸지 않는다.
- `camera/race_camera.gd` + `.tscn`: 카트 뒤 스프링 추적, 속도 방향
  바라보기(저속 시 forward), 속도² 기반 FOV.
- `kart/kart.tscn`: §6.3 Phase 1 노드 구성(CollisionShape3D, GroundRays ×
  5 RayCast3D, KartPhysics, Visuals). Drift/Boost/HitReactor/TerrainSensor/
  ItemSlot/KartAudio 슬롯은 아직 없으며 컨트롤러가 이를 전제하지 않는다.
- `scenes/test/kart_sandbox.gd` + 갱신된 `.tscn`: `PlaceholderKart`를
  `kart.tscn`으로 교체(StartGrid Grid01 스폰), `PlayerInputProvider` 연결,
  `RaceCamera` 타깃팅, `DebugOverlay` watch 5종(speed/speed_ratio/state/
  grounded/lateral) + 슬라이더 8종(9.10 파라미터), `R` 리셋 키.
- `track/tracks/test_loop_hills/test_loop_hills.tscn`: 같은 타원에 램프
  (15°업→15°다운, 정점 높이 ≈3.6m)와 근사 배킹 코너를 추가한 2번째
  그레이박스 트랙.
- `DebugOverlayService.remove_slider()` 추가: 슬라이더 getter/setter가
  해제된 씬을 참조한 채 남는 문제를 해결(아래 설계 결정 참고).
- `PhysicsTuning`에 `hover_snap_speed`, `up_align_speed_grounded`,
  `up_align_speed_airborne` 3개 필드 추가(9.9절 슬라이더 대상은 아님).

### 생성/수정된 파일

- 신규: `kart/kart.tscn`, `kart/kart_controller.gd`, `kart/kart_physics.gd`,
  `kart/kart_visuals.gd`, `camera/race_camera.gd`, `camera/race_camera.tscn`,
  `scenes/test/kart_sandbox.gd`,
  `track/tracks/test_loop_hills/test_loop_hills.tscn`,
  `tests/support/scripted_input_provider.gd`,
  `tests/unit/test_kart_physics.gd`, `tests/integration/test_kart_lap.gd`,
  `tests/integration/test_kart_wall_collision.gd`,
  `tests/integration/test_kart_hills.gd`, 대응 `*.uid` 파일들.
- 수정: `data/schemas/physics_tuning.gd` (3개 필드 추가),
  `core/autoload/debug_overlay.gd` (`remove_slider()`),
  `scenes/test/kart_sandbox.tscn` (카트/카메라/스크립트 교체),
  `tests/integration/test_kart_sandbox.gd` (새 노드 이름 반영 + 리셋 키
  테스트 추가), `tools/run_tests.sh` (`--fixed-fps 240`),
  `tools/validate_tracks.sh` (두 트랙 모두 검증), `ARCHITECTURE.md`,
  `README.md`.

### 핵심 설계 결정과 이유

- 카트는 노드 트리 순서상 자식(`Visuals`)의 `_ready()`가 부모
  (`KartController`)의 `_ready()`보다 먼저 실행되는 Godot 규칙 때문에,
  `KartVisuals._ready()`에서 컨트롤러 API를 호출하지 않는다(첫 프레임에
  자연히 자체 보정).
- `CharacterBody3D`가 이미 네이티브 `get_velocity()`를 제공해 §8 API 이름과
  충돌한다(오버라이드 시 파싱 에러). 상속 메서드가 동일한 `velocity`
  프로퍼티를 반환하므로 그대로 사용하고 별도 오버라이드를 만들지 않았다.
- `Vector3.slerp()`는 두 업 벡터가 평행/역평행에 가까우면(평평한 지면은
  매 틱 같은 법선을 반복한다) 내부적으로 축 정규화 단언에 실패한다. 이를
  피하기 위해 `KartPhysics._slerp_up_vector()`를 직접 구현했다(일반적인
  경우 결과는 동일).
- 접지 판정에서 `max_climb_angle_degrees`를 초과하는 히트는 평균 법선
  계산에서 제외해 가파른 면을 벽으로 취급한다(§9.7). 법선 합이 0에 가까울
  때(예: 겹치는 오버레이 지오메트리) 정규화 결과를 버리고 이전 프레임의
  법선을 유지해 정규화 에러를 방지한다.
- `DebugOverlayService`에 Phase 0에는 없던 `remove_slider()`를 추가했다.
  샌드박스가 여러 번 인스턴스화·해제되는 통합 테스트에서 슬라이더의
  getter/setter 클로저가 해제된 노드를 참조한 채 `_process()`에서 계속
  호출되어 매 프레임 에러가 발생했기 때문이다.
- 스크립트 드라이버(`ScriptedInputProvider`)는 조향량에 비례해 스로틀을
  줄인다. 코너에서 항상 풀스로틀로 라인을 추종하면 실제 드라이버라면
  피할 벽을 스치며 10m 이탈 허용치를 넘겼다 — 이는 물리 수치가 아니라
  테스트용 드라이버 AI의 현실성 문제였다.
- `test_loop_hills.tscn`의 램프/배킹 코너는 기존 평평한 바닥 콜리전과
  커브 조각을 수정하지 않고 그 위에 겹쳐 추가한다. 레이캐스트와
  `move_and_slide()`는 항상 더 가깝고 높은 표면을 우선하므로 베이스 메시를
  잘라낼 필요가 없다. 각 램프 조각은 보이는 구간보다 길게 만들고 낮은
  쪽 끝을 y=0 아래로 파묻어, 박스 끝면이 벽처럼 노출되어 카트가 걸리는
  것을 방지했다. 배킹 코너는 커브 접선에 정렬되지 않은 고정 롤 오버레이로,
  `# PLACEHOLDER`로 표시했다(Phase 4에서 authored 커브 데이터로 교체).
- `tools/run_tests.sh`에 `--fixed-fps 240`을 추가했다. 새 통합 테스트가
  `wait_physics_frames()`로 최대 90 시뮬레이션 초를 기다리는데, 이 플래그
  없이는 실제 시간과 동기화되어 테스트가 그만큼 오래 걸린다. 물리 틱
  레이트 자체(60Hz, `physics_ticks_per_second`)는 바뀌지 않는다.

### 실행 방법

```sh
/opt/homebrew/bin/godot --path .
# 또는 샌드박스만
/opt/homebrew/bin/godot --path . scenes/test/kart_sandbox.tscn
```

### 테스트 방법 및 결과 (run_tests / run_sim / validate_tracks 실제 출력 요약)

- `/opt/homebrew/bin/godot --headless --path . --import` — exit 0.
- `/opt/homebrew/bin/godot --headless --path . --quit` — exit 0, 에러 없음.
- `tools/run_tests.sh` — GUT 9.6.1, 11 scripts, **32 tests / 32 passing**
  (기존 18 + 신규 14: 유닛 10 + 통합 4), 319 assertions, 0 failures,
  ~2.3–2.9초(연속 5회 재실행으로 재현성 확인).
- `tools/validate_tracks.sh` — `test_loop`, `test_loop_hills` 모두
  `TRACK VALIDATION PASSED`(Phase 4 대상 경고 2개는 그대로 skip), exit 0.
- `tools/run_sim.sh` — `sim not implemented until Phase 6`, exit 0.
- `find . -name '*.gd' -not -path './addons/*' | xargs wc -l | sort -rn | head -5`
  — 최대 260줄(`kart/kart_physics.gd`), 400줄 초과 파일 없음.
- 신규 통합 테스트가 실제로 검증한 것: (1) `kart.tscn`을 `test_loop.tscn`에
  스폰해 `ScriptedInputProvider`(레이싱라인 12m→8m 룩어헤드 순추종)로 90초
  시뮬레이션 — 레이싱라인에서 10m 이내, y ≥ -1, 직선에서 speed_ratio ≥
  0.9, 언랩 진행도 ≥ 트랙 둘레(1랩 이상 완주); (2) 벽에 풀스로틀로
  정면 충돌 후 2초 뒤 조향 이탈 시 속도 > 3 m/s 회복, up 벡터가 월드 업
  10° 이내 유지(뒤집힘 없음); (3) `test_loop_hills`에서 램프를 올라
  y ≥ 1.0m 도달, 실제 착지(공중→접지 전이) 시 속도 손실이
  `landing_speed_loss_cap` 이내.

### 현재 문제점 / 알려진 버그

- `test_loop_hills.tscn`의 배킹 코너는 시각/충돌 모두 근사치이며 커브
  접선에 정확히 정렬되지 않았다(위 결정 로그 참고). 기능적으로는 통과
  가능하지만 시각적으로 어색할 수 있다.
- `KartVisuals`의 조향각/횡슬립 표시는 실제 `steer` 입력이 아니라 월드
  속도에서 역산한 근사치다(§8 공개 API에 lateral 게터가 없기 때문). 실제
  느낌에는 문제없지만 정밀도는 근사다.
- 헤드리스 더미 렌더러에서는 여전히 사람이 보는 렌더 스크린샷을 만들 수
  없다(Phase 0부터 알려진 환경 제약). 시각 확인은 사용자의 수동 플레이
  테스트가 필요하다.

### TODO / PLACEHOLDER 목록

- `kart/kart_controller.gd`: `_sample_terrain()`(phase-2 TerrainSensor),
  `_update_drift()`/`_update_boost()`(phase-3 Drift/BoostController),
  `_update_hit_reactor()`(phase-2 HitReactor) — 전부 중립 스텁.
- `kart/kart_physics.gd`: `TerrainSample`/`DriftResult`/`BoostResult`
  내부 클래스는 phase-2/3에서 실제 컴포넌트 출력으로 교체된다.
- `track/tracks/test_loop_hills/test_loop_hills.tscn`: 배킹 코너
  `# PLACEHOLDER` — phase-4에서 커브 정렬 지오메트리로 교체.
- Phase 0에서 이월된 항목(레이싱라인 authored 데이터, 아이템 박스/킬존
  검증, SFX 라이브러리 등)은 여전히 해당 Phase 범위.

### 다음 Phase 계획

Phase 2에서 횡미끄러짐 심화(현재 grip 모델의 지형 배율), `TerrainSensor`/
`TerrainData`/`OffroadZone`, 벽 충돌 각도별 반응 튜닝, `KartCollisionResolver`
(질량 기반 카트-카트 충돌), `HitReactor`(Bump/SpinOut/Tumble/Squash/무적),
공중 상태·착지 보정 심화, `KillZone` + `RespawnSystem`, 무게 클래스 3종
`KartData` 튜닝을 구현한다. 사용자 승인 전에는 시작하지 않는다.

### 사용자에게 필요한 결정 (있다면)

없음. 아래 플레이 지시대로 감각을 확인한 뒤 Phase 1 승인 여부만 필요하다.

### 플레이 지시 (사용자 감각 확인용)

```
1. 실행: /opt/homebrew/bin/godot --path . scenes/test/kart_sandbox.tscn
2. 조작: 가속 W(또는 패드 RT), 브레이크/후진 S(LT), 조향 A/D(좌스틱),
   R = 그리드 1번으로 리셋. Space/드리프트 버튼은 Phase 3까지 효과 없음
   (눌러도 아무 일도 일어나지 않는 것이 정상).
3. 시도해볼 것:
   a. 직선에서 W를 꾹 눌러 최고 속도까지 가속 — 초반에 힘있게 밀리다가
      최고속 근처에서 가속감이 줄어드는 게 느껴져야 한다(가속 곡선).
   b. 코너를 저속/고속으로 각각 돌아본다 — 고속에서는 조향이 더 둔하게
      반응해야 한다(조향 곡선). 정지 상태에서 제자리 회전이 안 되는지도
      확인(min_steer_speed).
   c. 급브레이크 후 계속 S를 누르고 있으면 잠시 후 후진으로 전환되는지
      확인.
   d. 내부 벽(InnerNorth/South/East/West)에 다양한 각도로 부딪혀본다 —
      스치듯 부딪히면 속도가 조금만 깎이고, 정면으로 박으면 크게 깎이며
      살짝 튕겨나가야 한다. 벽에 낀 채로 멈추지 않아야 한다(R로 언제든
      리셋 가능).
   e. F3으로 디버그 오버레이를 켜고 speed/speed_ratio/state/grounded/
      lateral 값이 조작에 따라 그럴듯하게 바뀌는지 확인한 뒤, 슬라이더로
      max_speed·acceleration·grip 등을 실시간으로 바꿔가며 감각 차이를
      느껴본다(재실행 없이 즉시 반영되어야 한다).
   f. (선택) `track/tracks/test_loop_hills/test_loop_hills.tscn`을 직접
      열어서 같은 카트로 램프를 넘어본다 — 오르막에서 자연스럽게 감속,
      내리막에서 가속되고, 착지 시 크게 튀거나 멈추지 않아야 한다.
4. 기대하는 감각: "그냥 달리는 것만으로 나쁘지 않다" — 가속/조향/브레이크/
   충돌 회복이 부자연스럽거나 답답하지 않으면 통과.
```

---

## Phase 0 보고 — 프로젝트 셋업 / 아키텍처 / 테스트 하네스

### 구현된 기능

- Godot 4.7 Forward+ 프로젝트 설정, 60 Hz 물리, 보간, 1600×900 캔버스
  스트레치, 24 m/s² 중력, 9개 명명 충돌 레이어를 설정했다.
- 키보드와 게임패드 기본값을 포함한 InputMap과 `InputFrame` 기반 입력
  추상화를 구현했다.
- `GameState`, `EventBus`, `SettingsManager`, `SaveManager`, `AudioManager`,
  `DebugOverlay` autoload를 작동 가능한 최소 범위로 구현했다.
- 모든 Phase 0 Resource 스키마와 물리/감각/카메라, 카트 3종, 지형 5종,
  AI 난이도 3종, 아이템 7종, 8인 아이템 확률표 기본 리소스를 만들었다.
- 14 m 폭 도로와 2 m 벽을 가진 평지 타원 그레이박스, 폐곡선
  `RacingLine`, 체크포인트 4개, 그리드 8개, 환경/조명, 샌드박스 카트와
  카메라를 구성했다.
- GUT 9.6.1 테스트 하네스와 테스트/시뮬레이션/트랙 검증 스크립트를
  구성했다.

### 생성/수정된 파일

- 프로젝트/문서: `project.godot`, `README.md`, `ARCHITECTURE.md`,
  `DEVLOG.md`
- 코어: `core/autoload/*`, `core/input/*`
- 데이터: `data/schemas/*`, `data/tuning/*`, `data/karts/*`,
  `data/terrain/*`, `data/ai/*`, `data/items/*`,
  `data/item_tables/default_8_karts.tres`
- 상태 계약: `kart/kart_state.gd`, `race/race_state.gd`
- 트랙/씬: `track/track.gd`, `track/racing_line.gd`,
  `track/track_validator.gd`, `track/track_template.tscn`,
  `track/tracks/test_loop/test_loop.tscn`, `scenes/main.tscn`,
  `scenes/test/kart_sandbox.tscn`
- 검증: `tests/unit/*`, `tests/integration/test_kart_sandbox.gd`,
  `tools/run_tests.sh`, `tools/run_sim.sh`, `tools/validate_tracks.sh`
- 미래 Phase 디렉터리: 내용이 없는 곳만 `.gitkeep`으로 추적했다.

### 핵심 설계 결정과 이유

- 게임 이름은 오리지널 명칭인 **Turbo Circuit**으로 정했다.
- autoload 스크립트는 singleton 이름과 충돌하지 않도록 `*Service`
  `class_name`을 사용해 테스트에서도 직접 인스턴스화할 수 있게 했다.
- 저장/설정 경로를 생성자에서 주입할 수 있게 해 실제 `user://` 데이터를
  건드리지 않는 복구/왕복 테스트를 만들었다.
- 부스트 사양과 미니 터보 티어를 별도 typed Resource로 만들어 물리
  튜닝에서 의미 없는 숫자 배열을 제거했다.
- Phase 0 레이싱라인은 `Curve3D.add_point()`로 구성한다. Godot 내부
  직렬화 포맷을 직접 작성하지 않아 엔진 마이너 버전 의존성을 줄였다.
- macOS headless 샌드박스의 키체인 제한은 macOS 전용
  `/etc/ssl/cert.pem` 설정으로 우회했다. 다른 플랫폼 설정은 바꾸지 않는다.

### 실행 방법

```sh
/opt/homebrew/bin/godot --path .
```

실행하면 `scenes/main.tscn`이 `kart_sandbox.tscn`을 로드한다. F3으로
DebugOverlay를 토글할 수 있다.

### 테스트 방법 및 결과 (run_tests / run_sim / validate_tracks 실제 출력 요약)

- `HOME=$PWD/.tmp-home /opt/homebrew/bin/godot --headless --path . --import`
  — exit 0, GDScript 클래스/리소스 import 완료, 생성된 `*.uid` 추적.
- `HOME=$PWD/.tmp-home /opt/homebrew/bin/godot --headless --path . --quit`
  — exit 0, `ERROR`/`SCRIPT ERROR` 없음.
- `HOME=$PWD/.tmp-home tools/run_tests.sh` — GUT 9.6.1, 7 scripts,
  **18 tests / 18 passing**, 290 assertions, 0 failures.
- `tools/run_sim.sh` — `sim not implemented until Phase 6`, exit 0.
- `HOME=$PWD/.tmp-home tools/validate_tracks.sh` — test loop validation passed;
  Phase 4 대상 검사 2개는 명시적 warning으로 skip, exit 0.
- 샌드박스 integration test — 실제 scene instantiate 후 RacingLine,
  플레이스홀더 kart mesh, collision layer/mask, active camera, visible
  DebugOverlay를 확인했다.

### 현재 문제점 / 알려진 버그

- 이 실행 환경의 dummy headless renderer는 Movie Maker texture capture에서
  엔진 크래시가 발생해 사람 눈으로 보는 렌더 스크린샷을 만들지 못했다.
  씬 구성은 integration test로 검증했으며 일반 창 실행 확인은 수동 항목이다.
- Phase 0 범위상 주행 가능한 카트나 실제 레이스 루프는 아직 없다.

### TODO / PLACEHOLDER 목록

- `track/racing_line.gd`: Phase 4에서 authored/baked 레이싱라인과 offset
  메타데이터로 교체한다.
- `track/track_validator.gd`: Phase 4에서 아이템 박스와 KillZone 검사를
  활성화한다.
- `scenes/test/kart_sandbox.tscn`: 카트는 Phase 1까지 정지 플레이스홀더다.
- `core/autoload/audio_manager.gd`: SFX 풀만 있으며 라이브러리/사운드는
  Phase 10 범위다.
- `data/items/*.tres`: item scene 필드는 Phase 7까지 비어 있다.
- `tools/run_sim.sh`: AI 레이스 시뮬레이션은 Phase 6에서 구현한다.
- `.gitkeep` 디렉터리: 해당 시스템 Phase에서 실제 파일로 대체한다.

### 다음 Phase 계획

Phase 1에서 `KartController`, `KartPhysics`, `KartVisuals`, 플레이어 입력
연결, 임시 추적 카메라, 런타임 물리 튜닝 슬라이더를 구현하고 기본 주행
감각 플레이 게이트를 검증한다. 사용자 승인 전에는 시작하지 않는다.

### 사용자에게 필요한 결정 (있다면)

없음. Phase 0 승인 여부만 필요하다.
