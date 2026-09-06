# Development Log

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
