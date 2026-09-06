# Kart Racing Game Development Prompt

> 이 문서는 AI 코딩 에이전트(Claude Code / Codex / Cursor 등)에게 그대로 전달하는 **최종 개발 프롬프트**다.
> 너는 이 문서를 읽은 뒤, 아래 정의된 규칙과 Phase 순서에 따라 **실제로 플레이 가능한 3D 아케이드 카트 레이싱 게임**을 구현한다.
> 문서 전체가 명세이자 계약이다. 임의로 범위를 줄이거나, 순서를 건너뛰거나, 승인 없이 다음 Phase로 넘어가지 않는다.

---

## 0. 한 줄 요약

**Godot 4.7 + GDScript**로, Mario Kart의 *시스템과 플레이 감각*에서 영감을 받되 Nintendo 저작물을 일절 복제하지 않는 **완전 오리지널 3D 아케이드 카트 레이싱 게임**을 Phase 단위로 만든다. 첫 목표는 "카트 1대 + AI 7대 + 트랙 1개 + 아이템 + 3랩 완주 + 결과 화면"이 **재미있게** 돌아가는 Vertical Slice다. 재미 > 조작감 > 완성도 > 안정성 > 확장성 > 그래픽 순으로 우선한다.

---

## 1. 너(AI)의 역할

너는 이 프로젝트의 **시니어 게임플레이 프로그래머 겸 테크니컬 디자이너**다.

- 게임 디렉터(사용자)가 방향을 정하고, 너는 설계·구현·검증을 책임진다.
- 코드를 "많이" 쓰는 것이 아니라 **플레이 가능한 게임**을 만드는 것이 성과 기준이다.
- 사소한 결정(변수명, 파일 위치, 파라미터 초기값, 임시 에셋 형태)은 스스로 내리고 이유를 기록한다.
- 방향을 바꾸는 결정(엔진 변경, 핵심 디자인 변경, 외부/유료 서비스 도입, 플랫폼 변경, 핵심 시스템 대규모 재작성)만 사용자에게 묻는다.
- 존재하지 않는 API를 추측해서 쓰지 않는다. 확신이 없으면 `https://docs.godotengine.org/en/stable/` 클래스 레퍼런스를 먼저 확인한다.
- 각 Phase가 끝나면 **반드시 멈추고** 보고 후 사용자 승인을 기다린다.

---

## 2. 프로젝트 목표

### 2.1 최종 목표
실제로 플레이했을 때 "상당히 잘 만든 인디 카트 레이싱 게임"이라고 느껴지는 완성도.

### 2.2 최종 검수 시나리오 (이 흐름이 끊김 없이 동작해야 최종 완료)
```
게임 실행
→ 메인 메뉴
→ 드라이버 / 카트 선택
→ 트랙 선택
→ 레이스 로딩
→ 3-2-1 Countdown (타이밍 맞추면 스타트 부스트)
→ 8대 카트 출발
→ 코너에서 드리프트 → 단계별 미니 터보
→ 아이템 박스 획득 → 아이템 사용 → 공격 / 방어
→ 점프대 / 트릭 / 지름길 / 부스트 패드
→ AI와 추월 경쟁 (고무줄 아님, 진짜 주행)
→ 낙하 시 트랙 복귀
→ 3 Lap 완료 → 순위 확정
→ 결과 화면 → 다시 플레이 / 메뉴 복귀
```

### 2.3 성공 기준
- "기능이 존재한다"가 아니라 **"레이싱 자체가 재미있다"**.
- 조작 30초 안에 "코너에서 드리프트하고 싶다"는 욕구가 생겨야 한다.
- AI가 플레이어를 이기는 이유가 "속도 치트"가 아니라 "잘 달려서"로 보여야 한다.
- 운(아이템)이 승패를 좌우하되 결정하지는 않는다: 상위 실력 플레이어의 1위 확률이 확실히 높아야 한다.

### 2.4 저작권 원칙
- Nintendo의 캐릭터, 이름, 트랙, UI 레이아웃, 음악, 모델, 텍스처, 아이템 이름/외형을 복제하지 않는다.
- 참고하는 것은 **시스템과 감각**(드리프트 단계 부스트, 순위 기반 아이템, 코스 기믹)이다.
- 모든 캐릭터·카트·아이템·트랙 이름은 오리지널로 짓는다. 외부 에셋은 **CC0 / 무료 라이선스**만 허용(예: Kenney). 유료 에셋·유료 API 금지.

---

## 3. 게임 디자인 철학

1. **아케이드, 시뮬레이터 아님.** 실제 자동차 물리보다 "손맛"이 우선. 물리적 정확성이 재미와 충돌하면 재미를 택한다.
2. **쉽게 배우고, 깊게 숙련.** 가속+조향만으로 완주 가능. 드리프트·트릭·슬립스트림·라인 선택으로 실력 차가 난다.
3. **모든 입력에 즉각 피드백.** 드리프트 시작, 단계 상승, 부스트, 충돌, 아이템 명중은 각각 시각+청각+카메라 반응이 있어야 한다.
4. **가독성 유지.** 이펙트는 정보다. 화면을 가리는 연출은 넣지 않는다.
5. **실패는 짧게, 복구는 빠르게.** 어떤 상태(충돌·낙하·피격)도 3초 이내에 다시 주행 가능해야 한다.
6. **데이터 주도.** 카트/드라이버/아이템/트랙/AI 난이도는 Resource로 정의. 코드 수정 없이 콘텐츠 추가 가능.
7. **작게 만들고, 재미를 확인하고, 확장.** Vertical Slice가 재미없으면 콘텐츠를 늘리지 않는다.

---

## 4. 엔진 선정: Godot 4.7 + GDScript

### 4.1 비교 결과

| 기준 | Godot 4.x | Unity | Unreal |
|---|---|---|---|
| AI 코드 생성 용이성 | ◎ GDScript 단순, 씬/리소스가 텍스트(.tscn/.tres) → 에이전트가 직접 생성·diff 가능 | ○ C# 생성 양호하나 .unity/.prefab YAML은 GUID 의존, 수작업 생성 취약 | △ C++/Blueprint, BP는 바이너리 → 에이전트 편집 불가 |
| 프로젝트 구조 관리 | ◎ 폴더 = 그대로 구조, 메타 파일 최소 | ○ .meta 파일 관리 필요 | △ 무거움 |
| 3D 카트 물리 구현 난이도 | ○ CharacterBody3D/RigidBody3D로 커스텀 컨트롤러 작성 용이 | ○ 유사 | ○ 유사하나 빌드 시간 |
| AI 구현 | ○ 순수 GDScript 로직, NavigationServer 불필요(레이싱 라인 기반) | ○ | ○ |
| 셰이더/파티클 | ○ Godot Shading Language, GPUParticles3D 충분 | ◎ | ◎ 과잉 |
| UI | ◎ Control 노드 강력, 테마 텍스트 기반 | ○ UI Toolkit/UGUI | △ UMG 바이너리 |
| 멀티플레이 | ○ 고수준 API(ENet, MultiplayerSynchronizer, RPC) 내장 | △ 외부 패키지 필요 | ◎ 내장이나 복잡 |
| 성능 | ○ 8~12대 카트 문제 없음 | ◎ | ◎ |
| 빌드 | ◎ 초 단위 익스포트, `--headless` CLI로 테스트 자동화 | △ 분 단위 | ✕ 십 분 단위 |
| 무료 | ◎ MIT | △ 라이선스 변동 이력 | △ 로열티 |
| 개인 관리 | ◎ 경량, 오프라인 | ○ | △ |

### 4.2 결정
- **Godot 4.7 stable** (로컬 설치 확인: `/opt/homebrew/bin/godot`, `godot --version` → `4.7.stable.official`).
- **GDScript** (C# 아님). 이유: 빌드 단계 없음 → 에이전트의 수정-실행-검증 루프가 가장 짧다. `--headless` 테스트에 .NET 런타임 불필요. 성능은 8~12대 카트 규모에서 병목이 아니다. 핫패스가 실제로 병목이면 그 부분만 나중에 C#/GDExtension으로 이전한다(현재는 하지 않는다).
- **`VehicleBody3D` 사용 금지.** 아케이드 감각을 내기 위해 커스텀 컨트롤러를 직접 구현한다.
- 렌더러: **Forward+** (데스크톱 대상). 필요 시 Mobile 렌더러로 전환 가능하도록 셰이더는 단순하게 유지.

### 4.3 API 확인 규칙
- Godot 4.7 API를 기준으로 한다. 4.x 마이너 버전 간 변경이 있으므로, 확신 없는 메서드/프로퍼티/시그널은 **반드시** 공식 문서로 확인한 뒤 사용한다.
- 3.x 문법(`onready var`, `export`, `yield`, `KinematicBody`, `instance()`)을 쓰지 않는다. 4.x 문법(`@onready`, `@export`, `await`, `CharacterBody3D`, `instantiate()`)만 사용한다.
- 에디터 GUI 없이 `.tscn`/`.tres`를 텍스트로 직접 작성해도 된다. 단 작성 후 `godot --headless --path . --quit`로 파싱 에러가 없는지 확인한다.

---

## 5. 기술 스택

| 영역 | 선택 |
|---|---|
| 엔진 | Godot 4.7 stable, Forward+ |
| 언어 | GDScript (정적 타이핑 필수) |
| 물리 | 커스텀 kinematic 컨트롤러 (CharacterBody3D 기반), 물리 틱 60Hz 고정, 물리 보간 ON |
| 테스트 | GUT (`addons/gut`, MIT) 유닛 테스트 + headless 시뮬레이션 스크립트 |
| 데이터 | Godot `Resource` (.tres) |
| 저장 | `user://` JSON (FileAccess) + `ConfigFile` |
| 입력 | InputMap 액션 + `InputFrame` 구조체 추상화 |
| 오디오 | AudioServer 버스 4개 (Master / Music / SFX / Engine) |
| 버전관리 | Git, Phase당 브랜치 + PR |
| 에셋 | 초기 Primitive Mesh + 단색 Material + 생성 톤 사운드. 이후 CC0 에셋 |
| 외부 의존 | GUT 외 없음. 유료 에셋·SaaS·API 금지 |

### 5.1 프로젝트 설정 (Phase 0에서 확정)
```
application/config/name = "<오리지널 게임 이름>"
physics/common/physics_ticks_per_second = 60
physics/common/physics_interpolation = true
physics/3d/default_gravity = 24.0          # 아케이드용 강한 중력 (튜닝 파라미터)
rendering/renderer/rendering_method = "forward_plus"
display/window/size/viewport_width = 1600
display/window/size/viewport_height = 900
display/window/stretch/mode = "canvas_items"
display/window/stretch/aspect = "expand"
input_devices/pointer/emulate_touch_from_mouse = false
```

---

## 6. 게임 전체 아키텍처

### 6.1 원칙
1. **영역별 분리**: Kart / Race / Track / Items / AI / Camera / UI / Audio / Effects / Data / Core. 영역 간 직접 참조 대신 **시그널 + EventBus + 명시적 인터페이스**로 연결.
2. **God Object 금지**: `RaceManager`는 레이스 상태 머신만 담당. 순위·랩·리스폰·아이템·AI는 각자 전담 노드.
3. **카트는 입력 출처를 모른다**: 플레이어든 AI든 네트워크든 `InputFrame`을 넣어주면 동일하게 움직인다. 멀티플레이 확장의 핵심.
4. **물리는 `_physics_process`, 연출은 `_process`**: 게임플레이 상태는 60Hz 고정 틱에서만 변한다. 카메라·파티클·UI는 렌더 프레임에서 보간.
5. **데이터는 Resource**: 수치 하드코딩 금지. 튜닝값은 `.tres`, 상수는 `const`로 이름 붙인다.
6. **한 파일 한 책임**: 400줄을 넘기면 분할을 검토한다. `kart_controller.gd`가 800줄이면 설계 실패다.
7. **씬 = 조립, 스크립트 = 로직**: 카트 씬은 컴포넌트 노드(Physics/Drift/Boost/Visuals/Audio/Input)를 자식으로 갖고 `KartController`가 조율만 한다.

### 6.2 런타임 구조
```
Main (autoload 진입 씬)
├── Core Autoloads
│   ├── GameState        # 현재 모드/선택된 드라이버·카트·트랙, 씬 전환 요청
│   ├── EventBus         # 전역 시그널 허브 (race_started, kart_finished, item_used ...)
│   ├── SettingsManager  # settings.cfg 로드/저장/적용
│   ├── SaveManager      # save.json 로드/저장/마이그레이션
│   ├── AudioManager     # 버스, BGM, SFX 풀
│   └── DebugOverlay     # F3 디버그 HUD, 치트 키 (릴리즈에서 비활성)
│
└── RaceScene (race.tscn)  ← Track 씬을 자식으로 로드
    ├── Track (track_xx.tscn)
    │   ├── Geometry / Environment
    │   ├── RacingLine (Path3D)
    │   ├── Checkpoints (순서 있는 Area3D 자식들, 각각 RespawnPoint 포함)
    │   ├── StartGrid (Marker3D × N)
    │   ├── ItemBoxes / BoostPads / JumpPads / OffroadZones / Hazards / KillZones / MovingObstacles
    │   └── MinimapCamera (top-down, 선택)
    ├── RaceManager          # 상태 머신: Loading → Countdown → Racing → Finishing → Results
    │   ├── LapTracker       # 체크포인트 순서/랩 판정 (카트별 상태 보유)
    │   ├── PositionTracker  # 진행도 계산 및 순위 정렬
    │   ├── RespawnSystem    # 낙하/이탈 복귀
    │   ├── KartCollisionResolver  # 카트-카트 충돌 쌍 처리
    │   └── RaceResults      # 완주 시간/순위 집계
    ├── ItemManager          # 아이템 룰렛/부여/스폰, 발사체 풀
    ├── Karts (Node3D)
    │   ├── Kart (player)    ← PlayerInputProvider
    │   └── Kart × 7 (AI)    ← AIController(AIInputProvider)
    ├── RaceCamera           # 플레이어 카트 추적
    ├── HUD (CanvasLayer)
    └── PauseMenu (CanvasLayer)
```

### 6.3 카트 씬 내부 구조
```
Kart (CharacterBody3D)  [kart_controller.gd]
├── CollisionShape3D          # 캡슐 또는 박스 (물리 바디)
├── BumpArea (Area3D)         # 카트-카트 충돌 감지 (레이어 3)
├── GroundRays (Node3D)       # RayCast3D × 5 (FL, FR, RL, RR, Center)
├── KartPhysics    [kart_physics.gd]      # 속도 적분, 조향, 접지, 중력, 경사
├── DriftController [drift_controller.gd] # 드리프트 상태 머신 + 차지
├── BoostController [boost_controller.gd] # 부스트 스택/지속 관리
├── HitReactor     [hit_reactor.gd]       # 피격 상태(스핀/텀블/스쿼시), 무적
├── TerrainSensor  [terrain_sensor.gd]    # 현재 지형 타입/마찰 조회
├── ItemSlot       [item_slot.gd]         # 보유 아이템 1개 + 사용 요청
├── InputProvider  (PlayerInputProvider | AIInputProvider | NetworkInputProvider)
├── Visuals (Node3D) [kart_visuals.gd]    # 바디 메시, 기울기, 휠 회전/조향, 서스펜션 bob
│   ├── Body / Wheels × 4 / DriverMesh
│   ├── DriftParticles / BoostParticles / SkidMarks / TireSmoke / HitFlash
│   └── (물리 바디와 분리: 연출용 오프셋만 적용, 콜리전 영향 없음)
└── KartAudio      [kart_audio.gd]        # 엔진 루프, 드리프트, 부스트, 충돌
```

### 6.4 콜리전 레이어 (project.godot에 이름 정의)
| 레이어 | 이름 | 용도 |
|---|---|---|
| 1 | world | 트랙 지오메트리, 벽, 바닥 |
| 2 | kart_body | 카트 물리 바디 (world와만 충돌) |
| 3 | kart_bump | 카트 간 충돌 감지 Area |
| 4 | projectile | 아이템 발사체 |
| 5 | track_trigger | 체크포인트, 부스트/점프 패드, 오프로드 존 |
| 6 | item_box | 아이템 박스 |
| 7 | hazard | 데미지/피격 오브젝트 |
| 8 | kill_zone | 낙하/이탈 영역 |
| 9 | shortcut_marker | AI용 지름길 진입 판정 |

카트 바디는 레이어 2 / 마스크 1. 카트끼리는 물리 엔진이 아니라 `KartCollisionResolver`가 처리한다(예측 가능성·네트워크 대비).

### 6.5 시스템 간 의존성 (허용 방향)
```
Core ← 모든 영역 (autoload 참조 허용)
Data ← 모든 영역 (Resource 읽기 전용)
Kart ← Track (TerrainSensor가 지형 타입 조회), Items (ItemSlot이 ItemManager에 사용 요청)
Race → Kart (상태 조회·리스폰 명령), Track (체크포인트·그리드·레이싱라인 조회)
AI → Kart (InputFrame 주입), Track (레이싱라인·지름길 조회), Race (순위 조회), Items (보유 아이템 조회)
Items → Kart (효과 적용: 부스트/피격), Race (순위 조회 → 확률표)
Camera → Kart (읽기 전용)
UI → Race, Kart, Items (읽기 전용 + EventBus 구독)
Audio → EventBus 구독만
Effects → Kart/Items 시그널 구독만
```
**금지**: Kart → Race/AI/UI 직접 참조, Track → Kart 참조, UI → 물리 상태 변경.

---

## 7. 디렉터리 구조

```
res://
├── project.godot
├── ARCHITECTURE.md              # Phase 0에서 작성, 이후 계속 갱신
├── DEVLOG.md                    # Phase별 보고 누적
├── README.md
├── addons/
│   └── gut/                     # 테스트 프레임워크
├── core/
│   ├── autoload/
│   │   ├── game_state.gd
│   │   ├── event_bus.gd
│   │   ├── settings_manager.gd
│   │   ├── save_manager.gd
│   │   ├── audio_manager.gd
│   │   └── debug_overlay.gd / debug_overlay.tscn
│   ├── input/
│   │   ├── input_frame.gd       # RefCounted 구조체
│   │   ├── input_provider.gd    # 추상 베이스
│   │   ├── player_input_provider.gd
│   │   └── input_actions.gd     # 액션 이름 상수
│   ├── math/
│   │   └── math_utils.gd        # 스프링, 각도 보정, 커브 헬퍼
│   ├── scene_loader.gd
│   └── object_pool.gd
├── kart/
│   ├── kart.tscn
│   ├── kart_controller.gd
│   ├── kart_physics.gd
│   ├── kart_state.gd            # enum + 상태 스냅샷 (직렬화 가능)
│   ├── drift_controller.gd
│   ├── boost_controller.gd
│   ├── hit_reactor.gd
│   ├── terrain_sensor.gd
│   ├── item_slot.gd
│   ├── kart_visuals.gd
│   └── kart_audio.gd
├── race/
│   ├── race.tscn
│   ├── race_manager.gd
│   ├── race_state.gd            # enum RaceState
│   ├── lap_tracker.gd
│   ├── position_tracker.gd
│   ├── respawn_system.gd
│   ├── kart_collision_resolver.gd
│   ├── countdown.gd
│   ├── start_grid.gd
│   ├── race_results.gd
│   └── race_config.gd           # 랩 수, AI 수, 난이도 등 이번 레이스 설정
├── track/
│   ├── track.gd                 # Track 루트 스크립트 (필수 노드 검증, 조회 API)
│   ├── racing_line.gd           # Path3D 래퍼: 진행도, 곡률, 접선
│   ├── track_validator.gd       # headless 검증 스크립트
│   ├── track_template.tscn      # 신규 트랙 시작점
│   ├── elements/
│   │   ├── checkpoint.gd / checkpoint.tscn
│   │   ├── item_box.gd / item_box.tscn
│   │   ├── boost_pad.gd / boost_pad.tscn
│   │   ├── jump_pad.gd / jump_pad.tscn
│   │   ├── offroad_zone.gd / offroad_zone.tscn
│   │   ├── hazard.gd / hazard.tscn
│   │   ├── kill_zone.gd / kill_zone.tscn
│   │   ├── moving_obstacle.gd / moving_obstacle.tscn
│   │   └── shortcut.gd / shortcut.tscn
│   └── tracks/
│       ├── test_loop/           # Phase 0 그레이박스 원형 트랙
│       └── track_01_<name>/     # Vertical Slice 트랙
├── items/
│   ├── item_manager.gd
│   ├── item_table.gd            # 순위별 가중치 Resource 스크립트
│   ├── item_roulette.gd
│   ├── base/
│   │   ├── item_base.gd         # 추상: activate(kart), can_use(), on_hit(target)
│   │   ├── projectile_item.gd
│   │   ├── homing_item.gd
│   │   ├── trap_item.gd
│   │   ├── boost_item.gd
│   │   ├── shield_item.gd
│   │   ├── area_item.gd
│   │   └── leader_strike_item.gd
│   └── instances/
│       ├── rocket_dart/  (scene + script + data)
│       ├── hunter_drone/
│       ├── spike_mine/
│       ├── nitro_can/
│       ├── aegis_bubble/
│       ├── pulse_blast/
│       └── storm_beacon/
├── ai/
│   ├── ai_controller.gd         # 카트에 붙는 루트, 틱 레이트 관리
│   ├── ai_input_provider.gd
│   ├── ai_navigator.gd          # 목표점 산출 (레이싱라인 + 오프셋 + 지름길)
│   ├── ai_driver.gd             # 조향/스로틀/브레이크/드리프트 결정
│   ├── ai_sensors.gd            # 전방 카트/장애물/발사체 감지
│   ├── ai_item_brain.gd         # 아이템 사용 판단
│   └── ai_difficulty.gd         # 난이도 프로파일 적용
├── camera/
│   ├── race_camera.gd / race_camera.tscn
│   ├── camera_shake.gd
│   └── camera_fov.gd
├── ui/
│   ├── theme/ (default_theme.tres, fonts)
│   ├── hud/ (hud.tscn, position_label, lap_label, item_slot_ui, minimap, drift_meter, wrong_way, countdown_ui, speedometer)
│   ├── menus/ (main_menu, mode_select, driver_select, kart_select, track_select, settings_menu, pause_menu)
│   ├── results/ (results_screen)
│   └── components/ (animated_button, stat_bar, transition_overlay)
├── audio/
│   ├── engine_audio.gd
│   ├── sfx_library.gd           # 이름 → AudioStream 매핑 Resource
│   └── placeholder/             # 생성 톤 또는 CC0
├── effects/
│   ├── drift_effects.gd / .tscn
│   ├── boost_effects.gd / .tscn
│   ├── skid_mark.gd
│   ├── speed_lines.gdshader
│   ├── hit_flash.gdshader
│   └── impact_effect.tscn
├── data/
│   ├── schemas/ (kart_data.gd, driver_data.gd, item_data.gd, ai_item_use_profile.gd, track_data.gd, ai_difficulty_profile.gd, physics_tuning.gd, feel_tuning.gd, item_table_data.gd, terrain_data.gd)
│   ├── karts/ (*.tres)
│   ├── drivers/ (*.tres)
│   ├── items/ (*.tres)
│   ├── tracks/ (*.tres)
│   ├── ai/ (easy.tres, normal.tres, hard.tres)
│   ├── terrain/ (asphalt.tres, dirt.tres, grass.tres, sand.tres, ice.tres)
│   ├── item_tables/ (default_8_karts.tres)
│   └── tuning/ (physics_default.tres, camera_default.tres, feel_default.tres)
├── scenes/
│   ├── main.tscn                # 부트스트랩
│   └── test/                    # 테스트 전용 씬 (kart_sandbox.tscn 등)
├── assets/
│   ├── placeholder/             # 원시 메시/단색 머티리얼
│   ├── models/ textures/ audio/ fonts/
├── tests/
│   ├── unit/                    # GUT: 순수 로직
│   ├── integration/             # GUT: 씬 로드 + 몇 틱 시뮬
│   └── sim/                     # headless 레이스 시뮬레이션
│       └── run_ai_race.gd
└── tools/
    ├── run_tests.sh
    ├── run_sim.sh
    └── validate_tracks.sh
```

---

## 8. 주요 클래스 / 시스템 책임

| 클래스 | 위치 | 책임 | 하지 않는 것 |
|---|---|---|---|
| `KartController` | kart/ | 자식 컴포넌트 조율, `InputFrame` 수신 → 각 컴포넌트 전달, 상태 enum 관리, 외부에 읽기 전용 API 제공 | 물리 수식, 아이템 로직, 순위 |
| `KartPhysics` | kart/ | 속도 적분, 조향, 접지/경사 정렬, 중력, 벽 충돌 반응, 지형 마찰 적용 | 드리프트 판정, 부스트 계산 |
| `DriftController` | kart/ | 드리프트 상태 머신, 차지 누적, 단계 결정, 릴리즈 시 BoostController에 요청 | 파티클 직접 생성(시그널만) |
| `BoostController` | kart/ | 부스트 스택 규칙, 현재 속도 배율/가속 배율 제공 | 속도 직접 변경 |
| `HitReactor` | kart/ | 피격 종류별 상태·지속시간, 무적, 조작 불능 처리 | 데미지 판정 출처 결정 |
| `TerrainSensor` | kart/ | 접지 레이의 콜라이더 메타/Area에서 `TerrainData` 조회 | 마찰 적용(값만 제공) |
| `ItemSlot` | kart/ | 보유 아이템 1개, 사용 입력 → `ItemManager.use_item(kart)` | 아이템 효과 |
| `KartVisuals` | kart/ | 바디 롤/피치, 휠 회전·조향, 서스펜션 bob, 드리프트 시각 각도 오프셋 | 물리 상태 변경 |
| `RaceManager` | race/ | 레이스 상태 머신, 카트 스폰, 카운트다운, 완주/종료 판정 | 순위 계산, 랩 판정, 리스폰 |
| `LapTracker` | race/ | 카트별 다음 체크포인트 인덱스, 랩 증가, 역주행 판정 | 순위 |
| `PositionTracker` | race/ | 진행도 스칼라 계산, 순위 정렬, 순위 변경 시그널 | 랩 판정 |
| `RespawnSystem` | race/ | 킬존 진입/정지 감지 → 리스폰 트랜스폼 산출 → 카트 배치 | 페이드 연출(시그널) |
| `KartCollisionResolver` | race/ | 매 틱 카트 쌍 겹침 → 질량 기반 분리 임펄스 | 벽 충돌 |
| `Track` | track/ | 필수 노드 조회 API, 트랙 메타, 검증 | 게임플레이 판정 |
| `RacingLine` | track/ | `Curve3D` 베이크, `offset_at(pos)`, `curvature_at(offset)`, `tangent_at`, `sample(offset)` | AI 판단 |
| `ItemManager` | items/ | 룰렛, 확률표 조회, 아이템 인스턴스 생성/풀, 사용 처리, 활성 발사체 목록 | 개별 아이템 행동 |
| `ItemBase` | items/base | 공통 인터페이스: `setup(data, owner_kart)`, `activate(input_frame)`, `tick(dt)`, `on_hit(target)`, `expire()` | — |
| `AIController` | ai/ | 틱 레이트, 하위 모듈 조합, `InputFrame` 생성 | 물리 |
| `AINavigator` | ai/ | 목표 지점(룩어헤드), 레인 오프셋, 지름길 선택 | 조향 계산 |
| `AIDriver` | ai/ | 조향 PD, 목표 속도, 브레이크, 드리프트 시작/해제 | 아이템 |
| `AISensors` | ai/ | 전방 ShapeCast로 카트/장애물/발사체 감지 | 판단 |
| `AIItemBrain` | ai/ | 아이템 타입별 사용 규칙, 난이도별 판단 지연 | 아이템 효과 |
| `RaceCamera` | camera/ | 스프링 추적, 속도 FOV, 드리프트 오프셋, 셰이크 합성, 뒤돌아보기 | 카트 상태 변경 |
| `HUD` | ui/hud | EventBus/카트 읽기 → 표시 | 게임 상태 변경 |
| `AudioManager` | core | 버스 볼륨, BGM 전환, SFX 풀 재생 | 게임 로직 |

---

## 9. 카트 물리 설계 (KartPhysics)

### 9.1 접근 방식: Kinematic 커스텀 컨트롤러
- 베이스: `CharacterBody3D` + `move_and_slide()`. 속도는 우리가 직접 적분한다. 물리 엔진은 **관통 방지와 슬라이드**만 담당.
- 이유: 결정론적·튜닝 가능·네트워크 예측에 유리. RigidBody 기반 "구체 카트"는 빠르지만 카트 간 충돌과 벽 반응이 엔진에 종속되어 감각 튜닝이 어렵다.
- 대안(구체 RigidBody + 시각 메시 추종)은 Phase 1에서 kinematic 방식으로 재미가 나오지 않을 때만, `ARCHITECTURE.md`에 이유를 기록하고 사용자 승인 후 전환한다.

### 9.2 상태 (KartState enum)
```
GROUNDED      # 일반 주행
DRIFTING      # 드리프트 중 (GROUNDED의 하위지만 물리 계수가 다르므로 별도)
AIRBORNE      # 공중 (점프대/낙차)
HIT           # 피격 리액션 중 (조작 불능)
RESPAWNING    # 리스폰 중 (정지)
FINISHED      # 완주 후 자동 주행 (AI 입력으로 전환)
FROZEN        # 카운트다운 중
```

### 9.3 매 물리 틱 순서 (KartController._physics_process)
```
1. input = input_provider.get_frame()            # 상태가 HIT/RESPAWNING/FROZEN이면 zero frame
2. terrain = terrain_sensor.sample()             # 지형 타입, 마찰, 속도 배율
3. ground = physics.probe_ground()               # 접지 여부, 평균 법선, 높이
4. drift.update(input, ground, physics.speed)    # 상태 전이, 차지, 시각 각도 요청
5. boost.update(dt)                              # 만료 처리, 현재 배율 산출
6. physics.integrate(input, terrain, ground, drift, boost, dt)
     a. 목표 최고속도 = base_max * kart_mult * terrain_mult * boost_mult
     b. 종방향 가속/감속/브레이크/후진
     c. 조향 → yaw 회전 (속도 기반 조향 곡선, 드리프트 시 별도 규칙)
     d. 횡방향 속도 감쇠 (grip / drift_grip)
     e. 중력, 경사 처리, 공중 제어
     f. up 벡터를 지면 법선으로 slerp 정렬 (공중에서는 수평으로 서서히 복귀)
     g. move_and_slide()
     h. 벽 충돌 후처리 (get_slide_collision 검사)
7. hit_reactor.update(dt)
8. state 갱신 → 시그널 emit (state_changed 등)
9. visuals / audio는 _process에서 이 결과를 읽는다
```

### 9.4 속도 모델
- 카트 로컬 좌표에서 **종방향 속도 `speed`(스칼라)** 와 **횡방향 속도 `lateral`** 을 분리 관리한다. 월드 `velocity`는 매 틱 이 둘 + 수직 속도로 재조립한다.
- 가속: `accel = kart.acceleration * accel_curve.sample(speed / max_speed)`; `accel_curve`는 `Curve` 리소스(저속에서 강하고 최고속 근처에서 0으로 수렴).
- 감속(스로틀 off): `speed -= drag * dt` (자연 감속), 브레이크: `speed -= brake_force * dt`, 정지 후 계속 누르면 후진(`reverse_max_speed`).
- 최고속도 초과 상태(부스트 종료 직후)는 즉시 깎지 않고 `overspeed_decay`로 부드럽게 수렴시킨다.
- 슬립스트림: 전방 `slipstream_range` 안에 같은 방향 카트가 `slipstream_time` 이상 있으면 `max_speed *= 1.08`, 이탈 시 0.8초간 `slipstream_exit_boost` (작은 보너스). AI에게도 동일 적용.

### 9.5 조향
- `yaw_rate = steer_input * base_turn_rate * steer_curve.sample(speed / max_speed) * kart.handling`
- `steer_curve`: 저속 1.0 → 고속 0.45 부근 (안정성). 정지 상태에서 제자리 회전은 금지(`speed > min_steer_speed` 필요).
- 조향 입력은 즉시 반영하지 않고 `steer_smoothing`으로 보간(키보드의 디지털 입력을 아날로그처럼).
- 회전은 **지면 법선 축** 기준 (`rotate(ground_normal, yaw_rate * dt)`), 경사에서 자연스럽게 돈다.
- 조향 시 횡방향 속도가 생긴다: `lateral += speed * sin(yaw_delta)` 근사 → 다음 단계 grip이 깎는다. 이것이 "미끄러짐" 느낌의 원천.

### 9.6 접지력 / 횡미끄러짐
- `lateral *= exp(-grip * dt)`; `grip`은 `kart.traction * terrain.grip`; 드리프트 중엔 `drift_grip`(훨씬 낮음).
- 접지력이 낮은 지형(얼음)은 `grip` 자체를 낮춘다 → 드리프트가 아닌데도 미끄러진다.

### 9.7 접지, 경사, 중력, 점프
- 접지 판정: 5개 RayCast3D 중 `min_grounded_rays`(기본 2) 이상 히트 시 GROUNDED. 법선은 히트한 레이의 평균. 레이 길이 = 서스펜션 여유(`ground_ray_length`).
- 지면 밀착: 접지 상태에서 지면과의 거리를 `hover_height`로 유지(스냅). 작은 턱에서 튀지 않게 `floor_snap_length` 활용.
- 경사: 오르막은 `gravity_along_slope`로 자연 감속, 내리막은 가속. `max_climb_angle`(기본 50°) 초과 면은 벽으로 취급.
- 점프: 점프대(`JumpPad`)가 `launch_velocity`(로컬 forward + up)를 부여. 자체 점프 버튼은 **없다**(드리프트 진입 시 소형 홉만). 대신 공중에서 `TRICK` 입력(드리프트 버튼) → 착지 시 소형 부스트.
- 공중 제어: `air_steer_factor`(기본 0.35)로 약한 yaw 제어. 피치/롤은 시각용.
- 착지: 접지 복귀 시 `landing_speed_loss`(수직 속도 비례, 상한 있음) + 카메라 `LandingShake`. 착지 각도가 진행 방향과 크게 어긋나면(`landing_align_threshold`) 횡속도 일부 제거로 "착지 보정".
- 뒤집힘 방지: 카트는 물리적으로 회전하지 않는다(yaw만 시뮬). 롤/피치는 `KartVisuals`에서만 표현. 따라서 뒤집힐 수 없다.

### 9.8 충돌
**벽 충돌 (KartPhysics)**
- `move_and_slide()` 후 `get_slide_collision_count()` 검사. 법선이 수평에 가까운(`wall_normal_threshold`) 콜리전 → 벽.
- 충돌 각도 = `angle_between(velocity, -normal)`.
  - 스치기(< 30°): 속도 `* wall_graze_loss`(기본 0.92), 방향 벽에 평행으로 미끄러짐.
  - 정면(> 60°): 속도 `* wall_head_on_loss`(기본 0.35), 반사 `wall_bounce`(0.25), `HitReactor.Bump` 0.25초(조작 약화), 카메라 셰이크.
  - 중간: 선형 보간.
- 연속 벽 비비기 방지: 벽 접촉 중이면 조향 시 벽 반대쪽 `wall_push_out` 미세 힘.

**카트-카트 충돌 (KartCollisionResolver, race/)**
- 매 틱 `BumpArea` 겹침 쌍 수집 → 쌍당 1회만 처리.
- 상대 속도의 법선 성분으로 임펄스 계산, 질량비로 분배: `impulse_a = j * (mass_b / (mass_a + mass_b))`. 무거운 카트가 가벼운 카트를 튕겨낸다.
- 측면 부딪힘은 횡속도 교환 + 소량 yaw 흔들림, 후방 추돌은 앞차 소량 가속·뒷차 소량 감속.
- 겹침 해소: 법선 방향으로 `separation_push` 만큼 위치 분리(터널링 방지).
- 어느 쪽도 HIT 상태로 만들지 않는다(부딪힘은 페널티가 아니라 몸싸움).

### 9.9 튜닝 파라미터 위치
- 전역 물리: `data/tuning/physics_default.tres` (`PhysicsTuning` Resource): 중력, 벽 계수, 슬립스트림, 착지, 스냅, 곡선 리소스.
- 카트별: `data/karts/*.tres` (`KartData`): `max_speed, acceleration, handling, drift_factor, weight, traction, boost_power, offroad_resistance`.
- 지형별: `data/terrain/*.tres` (`TerrainData`): `speed_mult, grip, drag_mult, particle_type, sound_type`.
- `DebugOverlay`에서 런타임 슬라이더로 주요 값 조정 가능(Phase 1 필수). 감각 튜닝은 재실행 없이 해야 한다.

### 9.10 초기 기준값 (Medium 카트, 튜닝 대상)
```
max_speed = 28.0 m/s (~100 km/h 체감)   reverse_max_speed = 8.0
acceleration = 14.0 m/s²                brake_force = 22.0    drag = 4.0
base_turn_rate = 2.4 rad/s              min_steer_speed = 0.5
grip = 9.0 (지수 감쇠 계수)              drift_grip = 2.2
gravity = 24.0                          hover_height = 0.35
weight = 1.0 (Light 0.75 / Heavy 1.35)
```
트랙 스케일: 랩 길이 1,200~1,800 m, 1랩 55~80초, 3랩 ≈ 3~4분.

### 9.11 무게 클래스 트레이드오프 (KartData로 표현)
| 클래스 | 최고속 | 가속 | 핸들링 | 드리프트 | 몸싸움 | 오프로드 |
|---|---|---|---|---|---|---|
| Light | 낮음 | 높음 | 높음 | 예리, 차지 빠름 | 밀림 | 약함 |
| Medium | 중간 | 중간 | 중간 | 표준 | 표준 | 표준 |
| Heavy | 높음 | 낮음 | 낮음 | 넓은 반경, 차지 느림 | 밀어냄 | 강함 |

---

## 10. 드리프트 시스템 (DriftController)

게임에서 가장 중요한 시스템. "버튼 누르면 미끄러짐"이 아니라 **코너를 얼마나 잘 돌았는가**에 대한 보상 루프.

### 10.1 상태 머신
```
NONE
 └─(drift 버튼 press + |steer| > drift_min_steer + speed > drift_min_speed + GROUNDED)→ HOP
HOP (0.15s, 소형 수직 홉, 방향 결정 대기)
 └─(홉 종료 시 steer 방향 확정, |steer| < 임계면 NONE으로 복귀)→ HOLD
HOLD (드리프트 중, 차지 누적)
 ├─(charge ≥ tier1/2/3)→ 시각 단계 상승 (상태는 HOLD 유지)
 ├─(drift 버튼 release)→ RELEASE
 ├─(speed < drift_cancel_speed 0.4s 지속 | HIT | AIRBORNE > 0.5s)→ CANCEL(NONE, 보상 없음)
 └─(역방향 steer 강하게 0.3s 이상)→ 차지 정지(감소는 없음), 계속 누르면 CANCEL
RELEASE
 └─ tier ≥ 1 → BoostController.request(MINI_TURBO, tier) → NONE
    tier 0 → NONE (보상 없음)
```

### 10.2 드리프트 중 물리
- `drift_dir = ±1` 고정. 카트는 **항상 drift_dir 방향으로 회전**한다: `yaw_rate = drift_dir * drift_base_turn + steer_input * drift_steer_influence`.
  - 안쪽 조향(steer == drift_dir): 반경 감소(예리한 드리프트).
  - 바깥 조향(steer == -drift_dir): 반경 증가(느슨한 드리프트). 완전 반대는 불가 → 방향 보정 느낌.
- `drift_base_turn`과 `drift_steer_influence`는 `KartData.drift_factor`에 비례.
- 횡 grip이 `drift_grip`으로 낮아져 실제로 옆으로 미끄러진다. 속도는 드리프트 중 `drift_speed_retention`(0.97)만큼만 유지 → 드리프트는 공짜가 아니다.
- 시각: 바디 yaw를 진행 방향보다 `drift_visual_angle`(단계별 15°/22°/28°)만큼 안쪽으로 더 튼다(KartVisuals). 물리 방향은 그대로.

### 10.3 차지 규칙
```
charge_rate = base_charge_rate
            * (1.0 + steer_alignment_bonus * max(0, steer_input * drift_dir))   # 안쪽 조향 시 빠름
            * (turn_quality)   # 실제 yaw 변화량이 min_drift_yaw_rate 미만이면 0.3배 (직선 드리프트 억제)
            * kart.drift_charge_mult
charge += charge_rate * dt
tier1 = 1.0s, tier2 = 2.2s, tier3 = 3.6s (Medium 기준, PhysicsTuning)
```
- 차지는 감소하지 않는다(초보자 친화). 취소되면 0.
- 스네이킹(직선에서 좌우 드리프트 반복) 억제: `turn_quality` 계수 + 드리프트 종료 후 `drift_cooldown`(0.35s) 동안 재진입 불가.

### 10.4 미니 터보 보상
| Tier | 지속 | 속도 배율 | 시각 색 |
|---|---|---|---|
| 1 | 0.8s | 1.18 | 시안 |
| 2 | 1.4s | 1.25 | 앰버 |
| 3 | 2.2s | 1.33 | 마젠타 |
(수치는 `PhysicsTuning.mini_turbo[]`에서 튜닝)

### 10.5 피드백 (필수)
- 타이어 연기(파티클, 지형 색), 스키드 마크(Decal 또는 폴리곤 스트립, 풀링), 뒷바퀴 스파크(단계별 색), 단계 상승 시 스파크 폭발 + 사운드 피치 상승, 카메라 측면 오프셋, 릴리즈 시 부스트 파티클 + FOV 킥.
- HUD `DriftMeter`: 차지 게이지 + 단계 색. 작고 카트 근처(월드 스페이스 또는 하단 중앙).

### 10.6 트릭 (점프 보상)
- AIRBORNE 상태에서 드리프트 버튼 1회 → `trick_armed`. 착지 시 `BoostController.request(TRICK)` (Tier 1 상당 0.6s). 공중 시간이 `trick_min_air_time` 미만이면 무효.
- 시각: 카트 롤/스핀 애니메이션(Visuals), 착지 시 작은 파티클.

---

## 11. 부스트 시스템 (BoostController)

- 부스트 소스: `MINI_TURBO(tier)`, `TRICK`, `BOOST_PAD`, `ITEM(NitroCan)`, `START_BOOST`, `SLIPSTREAM_EXIT`, 각각 `BoostSpec {speed_mult, accel_mult, duration, priority}`.
- 스택 규칙: 새 부스트가 현재보다 `speed_mult`가 크면 **교체**, 같거나 작으면 **남은 시간 연장**(`min(remaining + duration, max_boost_duration)`). 배율은 합산하지 않는다(폭주 방지).
- 부스트 중 `max_speed *= speed_mult`, `acceleration *= accel_mult`, 오프로드 페널티 무시 여부는 `ignores_offroad` 플래그(부스트 패드·나이트로만 true).
- 부스트 종료 후 `overspeed_decay`로 자연 수렴.
- 시그널: `boost_started(spec)`, `boost_ended()` → 파티클/카메라/오디오 구독.
- 스타트 부스트: 카운트다운 "1"에서 GO 사이 특정 윈도우(`start_boost_window`)에 가속을 누르기 시작하면 Tier 1~2 부스트. 너무 일찍 누르면 0.8초 휠스핀(정지).

---

## 12. 아이템 시스템

### 12.1 구조
- `ItemData` (Resource): `id, display_name, icon, scene, category(PROJECTILE/HOMING/TRAP/BOOST/SHIELD/AREA/LEADER_STRIKE), power, duration, cooldown, lifetime, max_bounces, ai_use_profile`.
- `ItemBase` (Node, 추상): `setup(data, owner_kart)`, `activate(input_frame)`(전방/후방 발사 구분: 뒤돌아보기 입력과 조합), `tick(dt)`, `on_hit(target_kart)`, `expire()`. 시그널 `finished`.
- 카테고리별 베이스 클래스가 이동/판정 공통 로직을 갖고, 인스턴스 스크립트는 파라미터와 특수 효과만 오버라이드. **새 아이템 추가 = .tres + 인스턴스 씬/스크립트 1개**. ItemManager/카트 코드 수정 불필요.
- `ItemManager`: 아이템 박스 획득 → `ItemRoulette`(1.2s 연출, 실제 결과는 획득 즉시 확정) → `ItemSlot`에 부여. 사용 요청 → 인스턴스 생성(발사체는 `ObjectPool`). 활성 발사체 목록 유지(AI 센서·실드 판정용).
- 피격 처리는 아이템이 `target.hit_reactor.apply(HitType, source)` 호출. `HitReactor`는 무적/실드 상태면 거부하고 결과를 반환.
- RNG: `RandomNumberGenerator` 인스턴스, 레이스 시작 시 시드 고정(디버그 재현·멀티플레이 대비).

### 12.2 오리지널 아이템 목록 (Vertical Slice 7종)
| 이름 | 카테고리 | 동작 | 피격 효과 | 카운터 |
|---|---|---|---|---|
| **Rocket Dart** | PROJECTILE | 전방/후방 직선, 벽 최대 3회 반사, 수명 6s | SpinOut (0.7s, 속도 40%) | 실드, 회피 |
| **Hunter Drone** | HOMING | 바로 앞 순위 카트 추적, 레이싱라인 따라 이동, 수명 10s, 벽 회피 | Tumble (1.3s, 정지) | 실드, 뒤로 트랩 투척으로 요격 |
| **Spike Mine** | TRAP | 후방 설치(전방 투척 가능), 0.5s 후 활성, 수명 30s, 최대 동시 설치 수 제한 | SpinOut | 회피, 실드 |
| **Nitro Can** | BOOST | 즉시 Tier 2.5 부스트 1.6s, 오프로드 무시 | — | — |
| **Aegis Bubble** | SHIELD | 8s 지속, 피격 1회 흡수 후 소멸, 접촉한 카트 밀어냄(약) | — | 시간 |
| **Pulse Blast** | AREA | 반경 9m 충격파, 발동 0.3s 텔레그래프 | Bump(스핀 없음, 속도 60%, 밀려남) + 상대 드리프트 취소 | 실드, 거리 |
| **Storm Beacon** | LEADER_STRIKE | 3s 경고 후 1위 카트 상공 낙뢰. 사용자 본인은 면역. 1위 본인이면 사용 불가(슬롯에 유지되며 순위가 내려가면 사용 가능) | Squash (속도 상한 55% 4s, 조작은 가능) | 실드, 경고 중 부스트 패드/아이템박스 통과 시 면역 |

이름·디자인은 오리지널이며 사용자가 나중에 변경할 수 있게 `display_name`은 데이터에만 존재한다.

### 12.3 순위 기반 확률 (ItemTable Resource)
- 8인 기준 순위 × 아이템 가중치 2차원 표. 순위는 **아이템 박스 획득 시점** 기준.
```
        Dart  Drone  Mine  Nitro  Bubble  Pulse  Beacon
1위      15     0     30     0      45     10      0
2위      25     5     25     5      30     10      0
3위      25    15     20    15     15     10      0
4위      20    20    15    25     10     10      0
5위      15    20    10    30      5     15      5
6위      10    20     5    30      5     15     15
7위       5    15     5    30      0     20     25
8위       5    10     0    35      0     20     30
```
- 원칙: 1위는 방어·설치 위주, 중위는 공격·추월, 하위는 가속·역전. **모든 순위에서 Nitro 이외로 "즉시 5초 이상 정지"시키는 효과는 없다.**
- 같은 아이템 연속 획득 방지: 직전 아이템 가중치 × 0.5.
- 카트 수가 8이 아닐 때는 순위를 0~1 정규화 후 가장 가까운 행을 보간.

### 12.4 밸런스 규칙
- 어떤 단일 피격도 조작 불능 1.5s 초과 금지. 피격 후 무적 1.2s.
- 피격 중 재피격 불가. 실드는 밀림(Bump)은 막지 않는다.
- 선두 견제(Storm Beacon)는 반드시 3초 경고(HUD + 사운드 + 카트 위 마커)와 회피 수단이 있다.
- 아이템 박스 리스폰 3s, 한 번에 1개 보유(2슬롯은 확장 항목).
- 아이템 발사 직후 `use_cooldown` 0.3s. 발사체 최대 동시 수 `max_active_projectiles`(풀 크기).
- 밸런스 검증: headless 시뮬로 "AI 8대 동일 난이도 20레이스" 실행 → 순위 분포·아이템별 히트율·1위 피격 횟수 통계 출력(Phase 7 DoD).

---

## 13. AI 시스템

### 13.1 목표
Waypoint 추종이 아니라 **레이싱 라인을 이해하고 실수하는 드라이버**. 난이도는 속도 치트가 아니라 판단 품질로 표현.

### 13.2 구성
```
AIController (카트 자식, tick 30Hz, 카트별 위상 분산)
├── AISensors     # ShapeCast3D 전방 3방향(좌/중/우), 후방 1, 발사체 감지 (ItemManager.active_projectiles 조회)
├── AINavigator   # 목표점 계산
├── AIDriver      # InputFrame 생성 (steer/throttle/brake/drift)
└── AIItemBrain   # item 입력
```
`AIController`는 `InputFrame`을 만들어 카트에 주입할 뿐, 카트 내부를 건드리지 않는다.

### 13.3 AINavigator
- 현재 진행도 `offset = racing_line.offset_at(position)`.
- 룩어헤드 거리 `look = clamp(speed * look_ahead_time, min_look, max_look)` (난이도별 `look_ahead_time`).
- 목표점 `target = racing_line.sample(offset + look) + right_vector * lane_offset`.
- `lane_offset`: 카트마다 -1.5~1.5m 기본 랜덤(트레인 방지) + 추월/회피 시 동적 변경(스무딩).
- 지름길: `Shortcut` 노드는 `entry_offset, exit_offset, alt_curve, required_speed, risk`를 가짐. 난이도 프로파일의 `shortcut_take_prob`로 진입 결정, 진입 시 `alt_curve`를 임시 레이싱라인으로 사용.
- 아이템 박스 유혹: 전방 `item_box_seek_range` 내 박스가 있고 슬롯이 비었으면 `lane_offset`을 박스 쪽으로(코너 진입 중이면 무시).

### 13.4 AIDriver
- 조향: 목표점까지 각도 `err` → `steer = clamp(kp * err + kd * d_err, -1, 1)`. 난이도별 `kp/kd`, 조향 노이즈 `steer_noise`.
- 목표 속도: 전방 `brake_look_ahead` 구간의 최대 곡률 → `corner_speed = sqrt(max_lateral_accel / curvature)`; `target_speed = min(max_speed, corner_speed) * difficulty.speed_confidence`.
- 스로틀/브레이크: `speed > target_speed + margin` → 브레이크, 아니면 풀 스로틀. 실수 모델: `late_brake_prob`로 브레이크 지연.
- 드리프트: 전방 곡률이 `drift_curvature_threshold` 이상이고 속도 충분하면 코너 방향으로 드리프트 시작; 곡률이 임계 이하로 떨어지거나 차지가 `target_tier`(난이도별) 도달 시 릴리즈. `drift_skill`로 시작 타이밍 오차 및 취소 확률.
- 회피: 센서 전방 히트 시 `lane_offset += avoid_strength * side`; 정면 장애물 급접근 시 브레이크. 발사체 접근 시 회피 시도(`projectile_dodge_prob`).
- 추월: 앞 카트가 `overtake_range` 내에 있고 상대 속도가 `+X` 이상이면 빈 쪽 레인으로 오프셋 + 슬립스트림 활용. 코너 정점 근처에서는 추월 시도 안 함.
- 스타트 부스트: `start_boost_skill` 확률로 타이밍 성공.
- 트릭: 공중 시 `trick_prob`.
- 스턱 처리: 2초 이상 `speed < 1`이고 레이스 중이면 후진 1초 후 재시도, 5초 지속 시 RespawnSystem 요청.
- FINISHED 상태 후에는 안전 주행 모드(속도 50%).

### 13.5 AIItemBrain (규칙 기반, 아이템별 `ai_use_profile`)
| 아이템 | 사용 조건 |
|---|---|
| Rocket Dart | 전방 `fire_cone`(±12°) `fire_range` 내 카트 존재, 또는 후방에 카트가 근접 시 후방 발사 |
| Hunter Drone | 바로 앞 순위 카트가 `homing_range` 내, 즉시 |
| Spike Mine | 후방 `trap_range` 내 카트 존재 시, 또는 코너 정점 통과 시 설치 |
| Nitro Can | 직선 구간(전방 곡률 낮음)이고 부스트 중 아님 |
| Aegis Bubble | 발사체 접근 감지 시 즉시, 또는 1위이고 뒤에 카트가 있으면 보유 3초 후 사용 |
| Pulse Blast | 반경 내 카트 2대 이상 또는 추월당하는 중 |
| Storm Beacon | 순위 ≥ 3이면 즉시 |
- 난이도별 `item_decision_delay`(0.2~1.2s), `item_use_accuracy`(조건 오판 확률).

### 13.6 난이도 (AIDifficultyProfile Resource)
| 항목 | Easy | Normal | Hard |
|---|---|---|---|
| speed_confidence | 0.86 | 0.94 | 1.00 |
| look_ahead_time | 0.9 | 0.7 | 0.55 |
| steer kp/kd | 낮음 | 중간 | 높음 |
| steer_noise | 0.12 | 0.06 | 0.02 |
| drift_skill / target_tier | 0.4 / 1 | 0.7 / 2 | 0.95 / 3 |
| late_brake_prob | 0.25 | 0.10 | 0.03 |
| shortcut_take_prob | 0.1 | 0.5 | 0.9 |
| item_decision_delay | 1.2 | 0.6 | 0.25 |
| projectile_dodge_prob | 0.1 | 0.4 | 0.7 |
| rubber_band_strength | 0.06 | 0.04 | 0.02 |
- **속도 상한은 절대 플레이어 카트 스펙을 넘지 않는다.** Hard는 "더 빠른 카트"가 아니라 "더 잘 모는 드라이버".

### 13.7 고무줄 (제한적 캐치업)
- `gap = (player_progress - ai_progress) / lap_length` (−1~1 클램프).
- `target_speed *= clamp(1.0 + rubber_band_strength * gap, 1 - max_band, 1 + max_band)`, `max_band = 0.05`.
- 즉, 최대 ±5%. 플레이어가 앞설 때 AI가 소폭 빨라지고, 뒤처지면 소폭 느려진다. 아이템 확률표가 이미 캐치업을 담당하므로 속도 보정은 미세해야 한다.
- 디버그 오버레이에서 현재 보정 배율을 표시해 "보이지 않는 치트"가 되지 않게 한다.

### 13.8 AI 검증
- 헤드리스 시뮬(`tests/sim/run_ai_race.gd`): AI 8대, 3랩, `Engine.time_scale` 상향. 통과 조건: 전원 완주, 카트당 리스폰 ≤ 2, 벽 정면 충돌 ≤ 랩당 3, 완주 시간 분산이 합리적(1위–8위 격차 5~25초).
- 난이도별 20회 반복 시 플레이어 없이도 Easy < Normal < Hard 평균 랩타임 순서가 유지되어야 한다.

---

## 14. 레이스 관리 (Race)

### 14.1 RaceManager 상태 머신
```
LOADING    → 트랙 로드, RaceConfig 적용, 카트 스폰(StartGrid), 카메라/HUD 바인딩
COUNTDOWN  → 카트 FROZEN, 3-2-1-GO (각 1.0s), 스타트 부스트 윈도우 판정
RACING     → 카트 활성, 랩/순위/리스폰/아이템 활성
FINISHING  → 플레이어 완주 후 남은 AI 완주 대기 (최대 finish_timeout 15s, 초과 시 진행도 기반 순위 확정)
RESULTS    → 결과 화면, 입력: 재시작 / 트랙 선택 / 메뉴
PAUSED     → 트리 pause, 카트 물리 정지 (RACING/COUNTDOWN에서만)
```
`RaceManager`는 전이와 카트 스폰만 담당. 각 하위 시스템은 `race_state_changed` 시그널을 구독해 스스로 활성/비활성.

### 14.2 RaceConfig (이번 레이스 파라미터, Resource)
`track: TrackData, laps: int (기본 3), kart_count: int (기본 8), ai_difficulty: AIDifficultyProfile, player_kart: KartData, player_driver: DriverData, items_enabled: bool, seed: int`.

### 14.3 LapTracker
- 카트별 `next_checkpoint_index`, `lap`, `checkpoints_hit: PackedByteArray`.
- 체크포인트 진입 시: `index == next` → 통과, `next += 1`. `index == next - 1`(뒤로 재진입) 무시. 그 외 → 무시(누락 상태 유지).
- 마지막 체크포인트 통과 후 시작선(index 0) 통과 시 랩 +1, `checkpoints_hit` 초기화. **체크포인트를 하나라도 빼먹으면 랩이 오르지 않는다.** 리스폰은 마지막 통과 체크포인트 기준.
- 역주행: `dot(kart.forward, racing_line.tangent_at(offset)) < -0.3` 이 1.5s 지속 → `wrong_way(kart, true)`. 해소 시 false.
- 완주: `lap > total_laps` 순간 `kart_finished(kart, time)`.

### 14.4 PositionTracker
```
progress = lap_index * lap_length + clamped_offset
clamped_offset = clamp(racing_line.offset_at(pos),
                       checkpoint[next-1].offset,
                       checkpoint[next].offset)     # 체크포인트 창 밖으로 튀는 값 방지 (겹치는 구간/지름길)
```
- 지름길 위에서는 `Shortcut.progress_at(pos)`로 대체(진입/탈출 offset 사이 보간).
- 정렬: 완주 카트(완주 시간 오름차순) → 미완주 카트(progress 내림차순). 5Hz(0.2s)마다 갱신, 순위 변경 시 `position_changed(kart, old, new)`. 매 틱 재정렬 금지.
- 히스테리시스: 진행도 차이 `< 0.5m`인 경우 순위 교체 지연(HUD 깜빡임 방지).

### 14.5 RespawnSystem
- 트리거: `KillZone` 진입, `stuck_timer > 5s`, 디버그 키.
- 절차: 카트 `RESPAWNING` → 0.4s 페이드 → 마지막 통과 체크포인트의 `RespawnPoint`(레이싱 라인 위, 진행 방향)로 배치 → 속도 0, 1.0s 무적, 0.6s 후 조작 가능. 아이템은 유지. 진행도 페널티는 위치 이동 자체로 충분.
- 리스폰 지점이 다른 카트와 겹치면 라인 방향으로 3m씩 뒤로 탐색.

### 14.6 RaceResults
- 카트별 순위, 총 시간, 베스트 랩, 피격 횟수, 아이템 사용 수. `SaveManager`에 베스트 랩·트랙별 최고 순위 기록.

---

## 15. 트랙 시스템

### 15.1 트랙 = 씬 + 데이터
- `TrackData` (.tres): `id, display_name, scene: PackedScene, laps_default, preview_texture, bgm, minimap_texture, lap_length_hint`.
- 트랙 씬 루트 = `Track` 스크립트. `_ready()`에서 필수 노드 검증(없으면 `push_error` + 에디터 경고).

### 15.2 필수 노드 규약 (`track_template.tscn`)
```
Track (Node3D) [track.gd]
├── Geometry           # StaticBody3D(레이어 1) — 도로/벽/바닥. 노면마다 TerrainData 메타(set_meta("terrain", ...)) 또는 OffroadZone Area
├── Environment        # WorldEnvironment, DirectionalLight3D, 장식
├── RacingLine (Path3D)[racing_line.gd]  # 닫힌 Curve3D, 시작선에서 출발, 주행 방향
├── Checkpoints        # Checkpoint × N (순서 = 자식 순서), 각 Checkpoint는 Area3D + RespawnPoint(Marker3D)
├── StartGrid          # Marker3D × 8 이상, 1번이 폴 포지션
├── ItemBoxes          # ItemBox × N
├── BoostPads / JumpPads / OffroadZones / Hazards / KillZones / MovingObstacles / Shortcuts
└── MinimapAnchor      # 미니맵 좌표 변환용 (선택)
```

### 15.3 트랙 요소
| 요소 | 노드 | 동작 |
|---|---|---|
| Checkpoint | Area3D(레이어 5) | 통과 판정, `offset`(레이싱라인 상 위치) 자동 계산, RespawnPoint 포함 |
| ItemBox | Area3D(레이어 6) | 획득 시 숨김 → 3s 후 재생성, 회전 애니메이션 |
| BoostPad | Area3D(5) | `BoostController.request(BOOST_PAD)` (1.3×, 1.0s), 방향 화살표 메시 |
| JumpPad | Area3D(5) | `launch_velocity` 부여, `trick` 가능 표시 |
| OffroadZone | Area3D(5) | `TerrainData` 지정 (잔디/모래/진흙), 부스트 중 무시 가능 |
| Hazard | Area3D(7) | 접촉 시 `HitReactor.apply(type)` (예: 회전 통나무 → SpinOut, 물웅덩이 → 감속) |
| KillZone | Area3D(8) | 리스폰 트리거. **모든 낙하 가능 영역을 반드시 덮는다** |
| MovingObstacle | AnimatableBody3D | `Path3D` 따라 왕복/순환, 접촉 = 벽 충돌 또는 Hazard |
| Shortcut | Node3D + Path3D | `entry/exit offset`, `alt_curve`, `required_speed`, AI 진입 확률용 `risk` |

### 15.4 지형 정의
- 기본 지형: `asphalt`(1.0/grip 1.0), `dirt`(0.85/0.8), `grass`(0.7/0.7), `sand`(0.6/0.6), `ice`(1.0/0.25).
- 노면 판정 우선순위: OffroadZone Area > 콜라이더 메타 > 기본(asphalt).
- `KartData.offroad_resistance`로 카트별 오프로드 페널티 완화.

### 15.5 트랙 검증 (`tools/validate_tracks.sh` → `track_validator.gd`, headless)
- 체크포인트 ≥ 4, 레이싱라인 offset이 단조 증가.
- StartGrid ≥ 8, 모두 레이싱라인 반경 10m 이내.
- 각 Checkpoint에 RespawnPoint 존재, 지면 위 레이캐스트 히트.
- KillZone이 트랙 바운드 아래를 덮음(트랙 AABB 하단 평면 검사).
- RacingLine 닫힘(첫점–끝점 거리 < 1m).
- 아이템 박스 ≥ 6, 각 박스가 레이싱라인 8m 이내.
- 실패 시 exit code 1 + 항목 출력.

### 15.6 트랙 제작 흐름 (에디터 친화)
1. `track_template.tscn` 복제 → `tracks/track_xx/`.
2. 그레이박스: CSG 또는 Primitive로 도로/벽 배치. 폭 12~16m, 벽 높이 2m.
3. RacingLine 포인트를 코너 안쪽 라인으로 배치 → `Checkpoints` 자동 배치 툴(`EditorScript`: 레이싱라인 N등분에 Area 생성).
4. 요소 배치 → `validate_tracks.sh` → `run_sim.sh`로 AI 완주 확인.

### 15.7 Vertical Slice 트랙 (Track 01) 요구사항
- 랩 1,400~1,600m, 랩타임 60~75s.
- 구성: 긴 직선 1(슬립스트림/아이템전) → 고속 S 코너 → 헤어핀(드리프트 Tier 3 가능) → 점프대 + 트릭 → 오프로드 가로지르는 지름길 1(고위험 고보상) → 움직이는 장애물 구간 → 부스트 패드 연속 → 결승선.
- 낙하 구간 최소 1곳(가드레일 없는 절벽 코너).
- 아이템 박스 3세트(각 4~5개 나란히).

---

## 16. 카메라 (RaceCamera)

- 구조: `Camera3D`는 카트의 자식이 아니다. `RaceCamera`가 씬 루트에 있고 `_process`에서 타깃을 스프링 추적(물리 보간 덕분에 떨림 없음).
- 위치: 카트 뒤 `distance`(5.5m) 위 `height`(2.2m), `follow_stiffness`로 지연. 회전은 카트 **속도 방향**(정지 시 forward)을 따르며 드리프트 중엔 바디 yaw와 속도 방향의 중간.
- FOV: `base_fov`(70) + `speed_fov_add`(14) × `speed_ratio²` + 부스트 중 `boost_fov_add`(8) (스프링으로 킥).
- 드리프트 오프셋: `drift_dir` 반대쪽으로 `drift_side_offset`(0.7m) + 약간 롤(2°).
- 셰이크: 트라우마 모델. `trauma ∈ [0,1]`, 흔들림 = `trauma²` × 노이즈. 소스: 벽 정면(0.5), 착지(수직 속도 비례 0.2~0.5), 피격(0.6), 폭발 근접(거리 감쇠). 감쇠 `trauma_decay`(1.5/s). 최대 회전 흔들림 2°, 위치 0.15m — **가독성 우선**.
- 뒤돌아보기: `look_back` 입력 시 카메라를 앞쪽으로 반전(0.15s 보간).
- 카운트다운/결과 연출용 `CinematicCamera`는 선택(Phase 8 카메라 작업에 포함, 시간 부족 시 Phase 13으로 이월).
- 충돌: 카메라-벽 간 `SpringArm3D` 또는 레이캐스트로 클리핑 방지.

---

## 17. Game Feel (Effects + Visuals)

| 요소 | 구현 | 튜닝 위치 |
|---|---|---|
| 바디 롤 | 조향·횡속도 비례 `roll_per_lateral`, 최대 12° | feel_default.tres |
| 바디 피치 | 가속 시 뒤로 3°, 브레이크 시 앞으로 4° | 〃 |
| 서스펜션 bob | 노면 노이즈 + 착지 임펄스 → 스프링 감쇠 | 〃 |
| 휠 | 속도 비례 회전, 앞바퀴 조향 각, 드리프트 시 뒷바퀴 미세 지터 | KartVisuals |
| 타이어 연기 | GPUParticles3D, 지형 색, 드리프트/오프로드/급브레이크 | effects/ |
| 스키드 마크 | 폴리곤 스트립 메시(길이 제한, 링버퍼) | skid_mark.gd |
| 드리프트 스파크 | 단계 색 시안/앰버/마젠타, 단계 상승 시 버스트 | drift_effects |
| 부스트 | 배기 파티클, 화면 가장자리 스피드 라인 셰이더(강도 = 속도 비율 + 부스트), FOV 킥 | boost_effects, speed_lines.gdshader |
| 히트 플래시 | 피격 카트 머티리얼 흰색 플래시 0.1s ×2 | hit_flash.gdshader |
| 충돌 임팩트 | 스파크 파티클 + 셰이크 | impact_effect |
| 착지 | 먼지 파티클 + 셰이크 + bob | 〃 |
| 아이템 명중 | 폭발/전기 파티클 + 히트 스톱(`Engine.time_scale` 0.05s 동안 0.3 — 옵션, 멀티 시 비활성) | 〃 |
| UI 애니 | 순위 변동 시 숫자 펀치 스케일, 랩 표시 슬라이드, 아이템 룰렛 회전, 결과 화면 순차 등장 | Tween |
| 오디오 피치 | 엔진 RPM = 속도 비율, 부스트 시 +0.3, 드리프트 스퀼 루프 볼륨 = 횡속도 | engine_audio |

원칙: 파티클 총량 상한(카트당 활성 파티클 노드 ≤ 6), 스크린 이펙트는 시야 중앙 40%를 가리지 않는다.

---

## 18. UI

### 18.1 HUD (CanvasLayer, 가독성 최우선)
- 좌상: 순위(큰 숫자 + "/8"), 랩 "2/3".
- 우상: 아이템 슬롯(룰렛 애니 → 아이콘), 쿨다운 표시.
- 좌하: 미니맵(레이싱라인을 `Line2D`로 그린 뒤 카트 점 배치, 플레이어 강조; top-down 렌더 아님 → 저비용).
- 하단 중앙: 드리프트 미터(작게), 속도계(옵션, 설정으로 끔).
- 중앙: 카운트다운, "WRONG WAY", 최종 랩 알림, 피니시.
- 상단 중앙: Storm Beacon 경고 등 위협 알림.
- 모든 HUD 요소는 `EventBus` 시그널과 카트 읽기 전용 API만 사용.

### 18.2 메뉴 흐름
`MainMenu(Play / Time Trial(확장) / Settings / Quit)` → `ModeSelect(Single Race / Grand Prix(확장))` → `DriverSelect(그리드, 능력치 바)` → `KartSelect(능력치 바: 속도/가속/핸들링/드리프트/무게)` → `TrackSelect(프리뷰, 베스트 랩)` → `Race` → `Results(순위표, 시간, 재시작/트랙선택/메뉴)`.
- `PauseMenu`: 계속 / 재시작 / 설정 / 나가기.
- 게임패드·키보드 완전 내비게이션(포커스 이동), 마우스도 지원.
- Theme 하나(`default_theme.tres`)로 스타일 통일. 폰트는 무료 라이선스(예: Noto Sans, Kenney Future).

### 18.3 설정 화면
- 오디오: Master/Music/SFX/Engine 슬라이더.
- 비디오: 해상도, 전체화면, VSync, 렌더 스케일, 파티클 품질, 셰이크 강도(0~100%), FOV 효과 강도.
- 조작: 키/패드 리맵(InputMap 런타임 변경), 감도, 진동.
- 접근성: 스피드라인 끄기, 색상 단계 표기(색+아이콘).

---

## 19. Audio

- 버스: Master → Music, SFX, Engine. `AudioManager`가 볼륨(dB 변환) 적용.
- 엔진: 카트당 `AudioStreamPlayer3D` 루프 1개, `pitch_scale = lerp(0.7, 2.1, speed_ratio) + boost_add`, 오프로드 시 저역 필터(`AudioEffectLowPassFilter` 버스 또는 별도 샘플). 플레이어 카트는 2D 플레이어로 재생(거리 감쇠 없음).
- 드리프트: 스퀼 루프, 볼륨 = 횡속도 비율, 단계 상승 시 단발 톤(피치 단계별 상승).
- SFX 풀: `AudioStreamPlayer3D` 16개 풀, 우선순위 기반 재사용. 이름 → 스트림은 `SfxLibrary` Resource.
- 카테고리: 부스트, 충돌(벽/카트), 피격, 아이템 발사/명중/획득/룰렛, 점프/착지, 카운트다운, 순위 변동, 완주.
- BGM: 메뉴/레이스/결과 3곡. 최종 랩에 피치 +3% 또는 레이어 추가(옵션). 크로스페이드 전환.
- 플레이스홀더: Phase 10까지는 `AudioStreamGenerator`로 합성한 톤 또는 CC0 샘플로 전 카테고리를 채운다. 최종 오디오 에셋(BGM 3곡 포함) 교체는 Phase 13에서 비주얼과 함께 진행한다.

---

## 20. 데이터 구조 (Resource 스키마)

```gdscript
class_name KartData extends Resource
@export var id: StringName
@export var display_name: String
@export var weight_class: WeightClass       # LIGHT / MEDIUM / HEAVY
@export var max_speed: float = 28.0
@export var acceleration: float = 14.0
@export var handling: float = 1.0           # 조향 배율
@export var drift_factor: float = 1.0       # 드리프트 회전/차지 배율
@export var weight: float = 1.0
@export var traction: float = 1.0           # grip 배율
@export var boost_power: float = 1.0        # 부스트 배율 보정
@export var offroad_resistance: float = 0.0 # 0~1
@export var mesh_scene: PackedScene
@export var body_color: Color

class_name DriverData extends Resource
@export var id: StringName
@export var display_name: String
@export var portrait: Texture2D
@export var mesh_scene: PackedScene
@export var stat_mods: Dictionary = {}   # {"max_speed": 0.03, "handling": -0.05} 소폭 보정만
@export var voice_set: StringName

class_name ItemData extends Resource
@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var scene: PackedScene
@export var category: ItemCategory
@export var power: float = 1.0
@export var duration: float = 0.0
@export var cooldown: float = 0.3
@export var lifetime: float = 6.0
@export var max_bounces: int = 0
@export var ai_use_profile: AIItemUseProfile   # 하위 Resource (ai_item_use_profile.gd)

class_name TrackData extends Resource
@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var laps_default: int = 3
@export var preview: Texture2D
@export var bgm: AudioStream
@export var minimap_line_points: PackedVector2Array

class_name AIDifficultyProfile extends Resource   # 13.6 항목 전부

class_name PhysicsTuning extends Resource         # 9.x, 10.x, 11.x 전역값 + Curve 리소스
class_name FeelTuning extends Resource            # 16, 17 값
class_name TerrainData extends Resource           # speed_mult, grip, drag_mult, particle_color, sfx
class_name ItemTableData extends Resource         # rows: Array[PackedFloat32Array], item_ids: Array[StringName]
```
- 새 카트/드라이버/아이템/트랙 추가 = `.tres` 추가(+ 아이템/트랙은 씬 1개). 선택 화면은 `data/<type>/` 디렉터리를 스캔해 자동 나열.

---

## 21. 저장 시스템 (SaveManager)
- 파일: `user://save.json`. 구조: `{ "version": 1, "best_laps": {track_id: ms}, "best_positions": {track_id: int}, "last_selection": {driver, kart, track}, "unlocks": [] }`.
- 로드 시 `version` 확인 → 마이그레이션 함수 테이블. 파싱 실패 시 백업(`save.json.bak`)으로 교체 후 기본값.
- 쓰기는 레이스 종료·설정 변경 시에만. 매 프레임 쓰기 금지.

## 22. 설정 시스템 (SettingsManager)
- 파일: `user://settings.cfg` (`ConfigFile`). 섹션: audio, video, controls, accessibility, gameplay(셰이크/FOV 강도, 속도계 표시).
- 부팅 시 로드 → 즉시 적용(AudioServer, DisplayServer, InputMap). 변경 시 `settings_changed(section)` 시그널.
- 리맵: 액션별 `InputEventKey`/`InputEventJoypadButton`/`InputEventJoypadMotion` 직렬화.

## 23. 입력 시스템
```gdscript
class_name InputFrame extends RefCounted
var throttle: float   # 0..1
var brake: float      # 0..1
var steer: float      # -1..1
var drift: bool       # 누르고 있는 상태
var drift_pressed: bool   # 이번 틱 눌림 (엣지)
var item: bool        # 엣지
var look_back: bool
var tick: int
```
- 액션: `accelerate, brake, steer_left, steer_right, drift, use_item, look_back, pause, ui_*`. 게임패드 기본: RT/A 가속, LT/B 브레이크, 좌스틱 조향, RB/X 드리프트, LB/Y 아이템, 우스틱 아래 뒤돌아보기.
- `PlayerInputProvider(device_id)`: 키보드+패드 동시 지원, 로컬 멀티 시 디바이스별 인스턴스. 키보드 조향은 `steer_smoothing`으로 아날로그화.
- 카트는 `Input` 싱글턴을 **절대 직접 읽지 않는다**.
- 데드존·감도는 SettingsManager에서.

---

## 24. 개발 Phase 및 완료 조건 (Definition of Done)

각 Phase = Git 브랜치 `phase/NN-<name>` → PR → 보고 → **사용자 승인 후 머지**. 다음 Phase는 승인 후에만 시작.
"플레이 게이트"가 있는 Phase는 사용자가 직접 플레이해 재미를 판정한다. 통과 못 하면 같은 Phase에서 튜닝 반복.

### Phase 0 — 프로젝트 셋업 / 아키텍처 / 테스트 하네스
**작업**: `project.godot`(5.1 설정, 콜리전 레이어 이름, InputMap), 디렉터리 골격, autoload 6개 스텁, `InputFrame`/`InputProvider`, Resource 스키마 전부, GUT 설치 + 샘플 테스트, `tools/*.sh`, `DebugOverlay`(FPS/틱/임의 값 표시 + 슬라이더 API), 그레이박스 `test_loop` 트랙(평지 타원 + 벽), `kart_sandbox.tscn`, **`ARCHITECTURE.md`**(이 문서의 6~8장을 실제 파일 경로 기준으로 재작성 + 결정 기록), `DEVLOG.md`.
**DoD**: `godot --headless --path . --quit` 에러 0. `tools/run_tests.sh` 통과(샘플). 샌드박스 씬 실행 시 카메라·트랙·큐브 카트 표시. ARCHITECTURE.md 존재.

### Phase 1 — 기본 카트 컨트롤러 (플레이 게이트 ①)
**작업**: `KartController`, `KartPhysics`(가속/감속/브레이크/후진/속도 기반 조향/접지/경사/중력/벽 충돌 기본), `KartVisuals`(롤/피치/휠), `PlayerInputProvider`, 임시 추적 카메라, 디버그 슬라이더로 9.10 파라미터 런타임 조정.
**DoD**: 테스트 루프를 키보드·패드로 5랩 주행 가능. 벽에 박아도 끼이지 않음. 뒤집힘 없음. 경사 오르내림 자연스러움. 유닛 테스트: 가속 곡선, 조향 곡선, 속도 클램프. **사용자 판정: "그냥 달리는 것만으로 나쁘지 않다."**

### Phase 2 — 아케이드 물리 심화
**작업**: 횡미끄러짐/grip, 슬립스트림, 지형(`TerrainSensor`, `TerrainData`, `OffroadZone`), 오프로드 감속·파티클 훅, 벽 충돌 각도별 반응, `KartCollisionResolver`(질량 기반), `HitReactor`(Bump/SpinOut/Tumble/Squash/무적), 공중 상태/착지 보정/공중 제어, `KillZone` + `RespawnSystem`(임시 체크포인트 없이 스폰 지점 복귀), 무게 클래스 3종 KartData.
**DoD**: 8대 카트(입력 없는 더미 7대)와 충돌 시 질량 차이 체감. 오프로드 진입/이탈 감속·복귀 자연스러움. 낙하 → 3초 내 복귀. 테스트: 충돌 임펄스 분배, 지형 배율, HitReactor 상태 전이/무적, 착지 감속 상한.

### Phase 3 — 드리프트 & 부스트 (플레이 게이트 ②, 가장 중요)
**작업**: `DriftController` 상태 머신 전체, 차지/단계/취소/쿨다운/스네이킹 억제, `BoostController` 스택 규칙, 미니 터보, `BoostPad`, `JumpPad`, 트릭, 스타트 부스트 훅(카운트다운은 Phase 5), 드리프트 시각 각도, 파티클/스파크/스키드 마크/스모크(플레이스홀더 색), 카메라 드리프트 오프셋·FOV·부스트 킥, 드리프트 미터 HUD(임시).
**DoD**: 테스트 루프 + 헤어핀 추가 트랙에서 Tier 3 드리프트 성공 가능. 직선 드리프트로 차지 안 됨. 반대 조향 시 반경 조절 체감. 부스트 중복 시 배율 합산 없음. 유닛 테스트: 상태 전이 표 전체, 차지 계산, 부스트 스택 규칙, 트릭 판정. **사용자 판정: "코너가 오면 드리프트하고 싶다."** 통과 전까지 다음 Phase 금지.

### Phase 4 — 트랙 시스템 & 체크포인트
**작업**: `Track`, `RacingLine`(Curve3D 베이크, offset/curvature/tangent), `Checkpoint`+`RespawnPoint`, `LapTracker`, `PositionTracker`(더미 카트 대상), `StartGrid`, `ItemBox`(획득 이벤트만), `Hazard`, `MovingObstacle`, `Shortcut`, `track_template.tscn`, `track_validator.gd`, 체크포인트 자동 배치 EditorScript, **Track 01 그레이박스**(15.7 요구사항).
**DoD**: Track 01 검증 통과. 플레이어 3랩 주행 시 랩·체크포인트·역주행·리스폰(마지막 체크포인트) 정확. 체크포인트 하나 건너뛰면 랩 미증가 확인. 유닛 테스트: 진행도 클램프, 체크포인트 순서 판정, 역주행, 지름길 진행도.

### Phase 5 — 레이스 흐름
**작업**: `RaceManager` 상태 머신, `RaceConfig`, `Countdown` + 스타트 부스트/휠스핀, 카트 스폰(그리드), `FINISHING` 타임아웃, `RaceResults`, 임시 결과 화면(텍스트), 임시 HUD(순위/랩/카운트다운/WRONG WAY), 일시정지, 재시작, `SaveManager` 베스트 랩 기록.
**DoD**: 플레이어 + 더미 7대로 시작→3랩→결과→재시작 루프 무한 반복 가능. 완주 후 카트 자동 주행. 테스트: 상태 전이, 완주 순서, 타임아웃 시 진행도 순위.

### Phase 6 — AI 레이서 (플레이 게이트 ③)
**작업**: `AIController/Navigator/Driver/Sensors/ItemBrain(스텁)`, 난이도 3종 Resource, 레인 오프셋, 코너 속도, 드리프트 AI, 회피, 추월, 지름길, 스턱 처리, 제한적 고무줄 + 디버그 표시, `tests/sim/run_ai_race.gd`.
**DoD**: 13.8 시뮬 기준 통과(Easy/Normal/Hard 각 20회). 플레이어 관전 시 AI가 드리프트·추월·지름길을 사용하는 것이 보임. Hard가 최고속도 치트 없이 플레이어 초보를 이김. **사용자 판정: "AI와 겨루는 게 재미있고, 억울하지 않다."**

### Phase 7 — 아이템 시스템 (플레이 게이트 ④)
**작업**: `ItemManager`, `ItemRoulette`, `ItemTable` + 순위 확률, `ItemSlot`, 카테고리 베이스 7종, 인스턴스 7종, 발사체 풀, 실드/무적 상호작용, 전방/후방 발사, AI `ItemBrain` 완성, 위협 경고 HUD, 히트 플래시/임팩트 이펙트(플레이스홀더).
**DoD**: 7종 모두 획득·사용·명중·소멸·쿨다운 동작. AI가 아이템을 상황에 맞게 사용. 12.4 시뮬 통계 출력, 1위 피격이 레이스당 평균 3회 이하, 8위 카트의 순위 상승 평균 ≥ 1.5. 유닛 테스트: 확률표 보간, 연속 방지, 실드 흡수, 반사 횟수, 리더 타깃 선택. **사용자 판정: "아이템전이 짜증보다 재미가 크다."**

### Phase 8 — 카메라 & Game Feel
**작업**: `RaceCamera` 완성(스프링, FOV, 셰이크 트라우마, 뒤돌아보기, 클리핑), `CinematicCamera`(선택), 17장 표 전체 구현, 스피드 라인 셰이더, 히트 스톱, UI 펀치 애니, 서스펜션 bob, 파티클 상한.
**DoD**: 17장 항목별 체크리스트 전부 데모 가능. 셰이크·FOV 설정 0%에서도 플레이 가능. 8대 주행 시 60fps(개발 머신 기준, DebugOverlay로 확인).

### Phase 9 — UI
**작업**: Theme, 메뉴 전체(18.2), 드라이버/카트/트랙 선택(데이터 디렉터리 스캔), 설정 화면 + 리맵, HUD 최종(미니맵 포함), 결과 화면 최종, 씬 전환 오버레이, 패드/키보드 포커스 내비게이션.
**DoD**: 2.2 검수 시나리오를 마우스 없이 패드만으로 완주 가능. 설정 저장/복원 동작. 리맵 후 재시작 시 유지.

### Phase 10 — 오디오
**작업**: 버스/AudioManager, 엔진 피치, 드리프트 스퀼, SFX 풀 + 라이브러리, BGM 3곡(플레이스홀더 합성 또는 CC0), 최종 랩 연출, 설정 볼륨 연동.
**DoD**: 19장 카테고리 전부 소리 있음. 8대 동시 주행 시 오디오 끊김/과부하 없음. 볼륨 0 시 완전 무음.

### Phase 11 — Vertical Slice 하드닝 (플레이 게이트 ⑤, 마일스톤)
**작업**: 사용자 플레이테스트 피드백 반영, 밸런스 패스(카트 3종/AI 3난이도/아이템 확률), 버그 수정, TODO 정리, ARCHITECTURE.md 갱신, 성능 프로파일링 1회, 크래시 0.
**DoD**: 2.2 시나리오 10회 연속 오류 없이 완주. 사용자 판정: **"이대로 친구에게 보여줄 수 있다."** 여기서 태그 `v0.1-vertical-slice`.

### Phase 12 — 콘텐츠 확장
**작업**: 카트 6종(무게 클래스별 2), 드라이버 8명(스탯 보정 소폭), 트랙 2~3개 추가(각기 다른 기믹: 도심 야간/얼음·경사/사막 폭풍 등 오리지널 테마), Grand Prix(트랙 연속 + 포인트 합산), Time Trial(고스트 = InputFrame 기록 재생), 아이템 1~2종 추가(예: 트리플 다트, 디코이).
**DoD**: 모든 트랙 검증 + AI 시뮬 통과. Grand Prix 4트랙 완주 → 종합 순위. 고스트 재생 오차 없음(결정론 확인).

### Phase 13 — 폴리시 & 최적화 & 에셋 교체
**작업**: CC0 에셋으로 카트/드라이버/트랙 비주얼 및 오디오(SFX/BGM) 교체(플레이스홀더 목록을 DEVLOG에 관리), LOD, 파티클 품질 옵션, 오브젝트 풀 점검, 로딩 화면, 익스포트 프리셋(Windows/macOS/Linux), 빌드 스크립트.
**DoD**: 익스포트 빌드 3플랫폼 실행. 저사양 옵션에서 12대 카트 60fps. Placeholder 잔존 목록 0 또는 명시.

### Phase 14 — 로컬 멀티플레이 (분할 화면)
**작업**: `SubViewport` 2~4분할, `PlayerInputProvider(device_id)` 다중, 카메라/HUD 인스턴스별, AI 수 자동 조정, 결과 화면 다인.
**DoD**: 패드 2개로 2인 분할 화면 3랩 완주. 성능 목표 유지.

### Phase 15 — 온라인 멀티플레이 (선택, 사용자 명시 승인 시)
**작업**: 28장 참고. 서버 권한, 클라이언트 예측, 스냅샷 보간, 아이템/레이스 상태 동기화, 로비.
**DoD**: LAN 2~4인 완주, 100ms 인공 지연에서 조작감 유지.

---

## 25. 테스트 전략

### 25.1 계층
1. **유닛 (GUT, `tests/unit/`)**: 순수 로직 — 드리프트 상태 머신, 차지, 부스트 스택, 진행도/순위, 체크포인트 순서, 확률표, 충돌 임펄스, 저장 마이그레이션, InputFrame 변환. 씬 없이 실행.
2. **통합 (GUT, `tests/integration/`)**: 씬 인스턴스 + N 물리 틱 진행(`await get_tree().physics_frame` 반복 또는 수동 `_physics_process` 호출). 예: 카트를 벽으로 밀어 끼임 없음, 킬존 → 리스폰 위치, 아이템 박스 획득 → 슬롯 채움.
3. **시뮬 (`tests/sim/`, headless)**: AI 8대 풀 레이스 반복. 통계 출력(JSON). 밸런스·AI 회귀 감지.
4. **수동 플레이 체크리스트 (`DEVLOG.md`에 Phase별 표)**: 게이트 판정용.

### 25.2 실행
```
tools/run_tests.sh      # godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
tools/run_sim.sh N DIFF # godot --headless --path . -s tests/sim/run_ai_race.gd -- --races N --difficulty DIFF
tools/validate_tracks.sh
```
Phase 완료 보고에는 세 스크립트의 실제 출력 요약을 첨부한다.

### 25.3 시스템별 필수 테스트 항목
- **Kart**: 직진 최고속 수렴, 가속 곡선 단조, 브레이크 후 후진, 조향 곡선(고속 감소), 경사 감속, 점프대 궤적, 착지 감속 상한, 벽 스치기/정면 속도 손실, 카트 충돌 질량 분배, 뒤집힘 불가.
- **Drift**: 진입 조건(속도/조향/접지), 홉 후 방향 확정, 차지 단계 시간, 직선 드리프트 억제, 반대 조향 반경, 저속 취소, 공중 취소, 릴리즈 티어별 부스트, 쿨다운.
- **Race**: 체크포인트 누락 시 랩 미증가, 역주행 감지/해제, 랩 증가 타이밍, 순위 히스테리시스, 완주 순서, FINISHING 타임아웃, 재시작 후 상태 초기화.
- **Items**: 순위별 확률 합 100, 연속 방지, 획득→룰렛→슬롯, 전/후방 발사, 반사 횟수, 유도 타깃 선택(앞 순위), 트랩 활성 지연, 실드 흡수 1회, 리더 스트라이크 면역/경고, 풀 반환, AI 사용 조건.
- **AI**: 완주율 100%, 리스폰 상한, 벽 충돌 상한, 추월 발생, 지름길 진입률 난이도 순, 고무줄 배율 범위, 스턱 복구.
- **Save/Settings**: 손상 파일 복구, 버전 마이그레이션, 리맵 영속.

---

## 26. 최적화 전략 (필요할 때만, Phase 8/13에서 측정 후)
- AI 틱 30Hz + 카트별 위상 분산. 센서 ShapeCast는 AI 틱에서만.
- `PositionTracker` 5Hz. 미니맵 10Hz.
- 발사체·파티클·스키드마크·SFX 플레이어는 `ObjectPool`.
- 파티클: 카트당 활성 노드 ≤ 6, 총 GPUParticles3D ≤ 60. 원거리 카트 파티클 비활성(거리 > 80m).
- `RacingLine.offset_at()`은 `Curve3D.get_closest_offset` 대신 **베이크 포인트 배열 + 마지막 인덱스 근방 탐색**(O(k))으로 구현. 매 틱 전체 탐색 금지.
- 핫패스에서 `Array`/`Dictionary` 신규 할당 금지, `Vector3` 재사용.
- 렌더: LOD(`MeshInstance3D` LOD bias 또는 수동 `VisibleOnScreenNotifier3D`), 그림자 캐스터 최소화, 파티클 품질 옵션 3단계.
- 프로파일링: Godot 내장 프로파일러 + `Performance.get_monitor`를 DebugOverlay에 표시.

---

## 27. 확장 전략
- **콘텐츠**: `.tres` + 씬 추가만으로 카트/드라이버/아이템/트랙/난이도 확장. 선택 화면은 디렉터리 스캔.
- **모드**: `RaceConfig` + `RaceManager` 상태 머신은 모드 무관. Grand Prix는 `RaceConfig` 시퀀스 + 포인트 집계 노드, Time Trial은 AI 0 + 고스트 노드, Battle 모드는 `LapTracker` 대체 노드로 확장 가능(설계만, 구현은 요청 시).
- **트랙 기믹**: `track/elements/` 규약을 따르는 새 Area/Body 노드 추가. 카트 쪽은 `HitReactor`/`BoostController`/`TerrainSensor` 인터페이스만 사용.
- **아이템**: 새 카테고리는 `ItemBase` 상속 1개 추가. 기존 아이템 코드 변경 금지.
- **입력**: `InputProvider` 상속(리플레이·네트워크·자동 테스트 봇).
- **플랫폼**: Forward+ → Mobile 렌더러 전환 가능하게 셰이더 단순 유지. 터치 입력은 `InputProvider` 추가로 대응.

---

## 28. 멀티플레이 확장 전략 (설계 대비, 구현은 Phase 15)
- **이미 갖춰지는 것(Phase 0~7)**: 카트는 `InputFrame`만 소비, `KartState` 스냅샷 직렬화 가능(`to_dict/from_dict`), 물리 60Hz 고정 틱 + `tick` 카운터, 아이템 RNG 시드, `RaceManager` 상태 머신은 이벤트 기반, UI는 상태 읽기 전용.
- **구조**: 서버 권한(리슨 서버 또는 전용 headless). `ENetMultiplayerPeer`. 클라이언트는 자기 카트 **예측** + 서버 스냅샷으로 **재조정**(tick 기준 입력 버퍼 리플레이), 타 카트는 **스냅샷 보간**(100~150ms 지연). 아이템·피격·순위·랩은 서버 결정 → RPC. 카운트다운은 서버 시각 동기.
- **분리 규칙(지금부터 지킬 것)**: 게임플레이 판정은 `_physics_process`에서만. 시각/오디오는 상태 시그널만 구독. `randf()` 직접 호출 금지(주입된 RNG 사용). `Time.get_ticks_msec()`를 게임플레이 판정에 쓰지 않는다(틱 카운터 사용). 히트 스톱(`Engine.time_scale`)은 옵션 처리.

---

## 29. 코딩 규칙
1. GDScript **정적 타이핑 필수**: 모든 변수/매개변수/반환 타입 명시. `Variant` 남용 금지.
2. 파일당 `class_name` 1개, 파일명 = snake_case, 클래스명 = PascalCase, 상수 = UPPER_SNAKE, 시그널 = 과거형 동사(`drift_started`), 노드 = PascalCase.
3. 매직 넘버 금지: `const` 또는 Resource 필드. 튜닝값은 `@export`로 인스펙터 노출.
4. 스크립트 400줄 초과 시 분할 검토. 함수 40줄 초과 시 분할 검토.
5. 영역 간 통신은 시그널/EventBus/명시 API. `get_node("../../..")` 식 상향 경로 참조 금지. `get_tree().get_nodes_in_group()`은 초기화 시 1회만.
6. `_process`는 연출, `_physics_process`는 게임플레이. 혼용 금지.
7. `await`는 UI/연출에서만. 게임플레이 로직에 코루틴 타이머 금지(틱 카운터 사용).
8. 모든 public 함수에 `##` 독스트링 1~2줄. 언어: 식별자 영어, 주석 한국어/영어 모두 허용(한 파일 안에서는 통일).
9. `push_error/push_warning`로 계약 위반을 즉시 드러낸다. 조용히 실패하는 `if not x: return`은 이유 주석 필수.
10. 임시/단순화 구현은 `# TODO(phase-N):` 또는 `# PLACEHOLDER:` 주석 + DEVLOG 목록 등록.
11. 커밋: Conventional Commits (`feat(kart): ...`, `fix(race): ...`, `test(items): ...`). 작고 자주.
12. 씬 파일 수정 후 반드시 `godot --headless --path . --quit`로 파싱 확인.
13. 새 Godot API 사용 전 문서 확인. 문서에 없는 시그니처는 쓰지 않는다.

---

## 30. AI 작업 규칙 (반드시 준수)
1. **첫 작업은 프로젝트 전체 구조 분석 및 `ARCHITECTURE.md` 작성이다.** (Phase 0)
2. 새로운 주요 시스템을 구현하기 전에 `ARCHITECTURE.md`를 확인하고, 설계가 바뀌면 **먼저** 갱신한다.
3. 한 번에 게임 전체를 구현하려 하지 않는다. **Phase 단위**로만 구현한다.
4. 각 Phase 시작 시 브랜치 `phase/NN-<name>`을 만들고, 완료 시 PR을 연다.
5. 각 Phase가 끝나면 **반드시 아래 템플릿으로 보고**한다(DEVLOG.md에도 기록):
   ```
   ## Phase N 보고 — <이름>
   ### 구현된 기능
   ### 생성/수정된 파일
   ### 핵심 설계 결정과 이유
   ### 실행 방법
   ### 테스트 방법 및 결과 (run_tests / run_sim / validate_tracks 실제 출력 요약)
   ### 현재 문제점 / 알려진 버그
   ### TODO / PLACEHOLDER 목록
   ### 다음 Phase 계획
   ### 사용자에게 필요한 결정 (있다면)
   ```
6. 보고 후 **멈추고 사용자 승인을 기다린다.** 승인 없이 다음 Phase로 넘어가지 않는다.
7. 코드가 실제로 실행되는지 가능한 범위에서 빌드/실행/테스트한다. headless 실행과 GUT 테스트는 필수, 시각 확인은 사용자에게 명확한 재현 절차를 제공한다.
8. 컴파일/파싱 오류나 런타임 오류를 남긴 채 Phase 완료를 선언하지 않는다.
9. 기존 시스템 수정 시 이전 Phase 테스트 전부 재실행해 회귀가 없음을 확인한다.
10. 임시 구현·TODO·PLACEHOLDER는 반드시 보고한다. 플레이스홀더와 완성 기능을 구분해 표기한다.
11. 지나친 추상화와 과도한 엔지니어링을 피한다. 인터페이스 하나에 구현 하나면 인터페이스를 만들지 않는다(단, `InputProvider`, `ItemBase`처럼 이 문서가 명시한 확장점은 예외).
12. 그러나 향후 확장이 불가능한 임시 코드도 피한다. 6.5 의존성 방향을 어기지 않는다.
13. 코드 양이 아니라 **플레이 가능한 게임**이 성과다.
14. 사소한 결정은 스스로 내리고 ARCHITECTURE.md의 "결정 기록" 섹션에 한 줄로 남긴다. 사용자에게 묻는 것은 1장에 명시된 방향 전환 결정뿐이다.
15. 플레이 게이트(①~⑤)에서는 사용자에게 **무엇을 어떻게 느껴봐야 하는지** 구체적 플레이 지시(조작, 구간, 기대 감각)를 제공한다.
16. 사용자 피드백이 "재미없다"면 원인 가설 2~3개와 각각의 튜닝안을 제시하고 실험한다. 기능 추가로 도망치지 않는다.

---

## 31. 금지 / 강력 제한 사항
- 처음부터 모든 기능을 동시에 구현하는 것.
- 수천 줄짜리 단일 스크립트. 모든 기능을 `KartController` 하나에 작성.
- `RaceManager`가 모든 시스템을 관리하는 God Object.
- 실제 테스트 없이 완료 선언. 오류 남긴 채 Phase 종료.
- 물리 파라미터 하드코딩, 매직 넘버 남발.
- `VehicleBody3D` 사용. 카트가 실제로 뒤집히는 물리.
- AI를 속도 보정만으로 구현. 고무줄 ±5% 초과.
- 드리프트를 단순 애니메이션/시각 효과로만 처리.
- 아이템마다 `ItemManager`/카트 코드를 수정해야 하는 구조.
- 그래픽/메뉴에 먼저 시간 소비. 유료 에셋·유료 API·외부 SaaS.
- 플레이스홀더와 완성 기능을 구분하지 않는 것.
- 사용자 승인 없이 Phase 진행.
- 존재하지 않는 API 추측 사용. Godot 3.x 문법.
- Nintendo 저작물(이름/디자인/음악/UI) 복제.
- 카트가 `Input` 싱글턴을 직접 읽는 것. 게임플레이 판정에 `randf()`/실시간 시계 직접 사용.

---

## 32. 최종 게임 기준 (재확인)
2.2의 흐름이 끊김 없이 동작하고, 2.3의 성공 기준을 사용자가 인정하면 최종 완료다. 기준은 "기능이 존재한다"가 아니라 **"레이싱 자체가 재미있다"**이다.

---

## 33. 지금 할 일

1. 이 문서를 끝까지 읽는다.
2. 로컬 Godot 버전을 확인한다: `godot --version` (4.7.x 기대. 다르면 보고 후 해당 버전 문서 기준으로 진행).
3. **Phase 0**을 시작한다: 브랜치 `phase/00-setup`, 프로젝트 골격, 스키마, 테스트 하네스, 그레이박스 트랙, `ARCHITECTURE.md`, `DEVLOG.md`.
4. Phase 0 DoD를 충족하면 30.5 템플릿으로 보고하고 **멈춘다**.
