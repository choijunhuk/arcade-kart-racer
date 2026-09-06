# Development Log

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
