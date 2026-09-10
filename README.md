# arcade-kart-racer

Mario Kart에서 *시스템과 플레이 감각*만 영감을 받은 **완전 오리지널 3D 아케이드 카트 레이싱 게임** 프로젝트.
엔진: **Godot 4.7 + GDScript**.

## 이 레포의 현재 상태

**Phase 16 — 인터넷 플레이(LAN → 인터넷): UPnP 자동 포트 포워딩, 호스트 코드,
전용 headless 서버, 릴레이(옵션), 연결 품질 HUD, 견고성(레이트 리밋/버전·비밀번호
검사).** 실제 ENet/LAN 검증 및 독립 리뷰는 여전히 대기 중이다. 현재 검증 결과와
네이티브 창 제한은 [DEVLOG](DEVLOG.md), 에셋별 교체/유지 사유는
[placeholder ledger](docs/phase13_asset_ledger.md)를 참조한다.

메인 메뉴에서 **Play → Single Race / Grand Prix / Local Multiplayer**, 또는 **Time Trial**을 고른다.
드라이버 8명·카트 6종·경기 트랙 4개·난이도 3개를 제공한다. Single Race는
아이템 on/off를 선택할 수 있다. Local Multiplayer는 키보드 1명과 패드,
또는 패드 2–4개가 각각 드라이버·카트를 고른 뒤 8대 필드 분할 화면으로 달린다.
Grand Prix는 Ridgeline → Lumen → Glacier →
Ochre의 4경기와 누적 점수·최종 포디움을 제공하고, Time Trial은 AI/아이템 없이
베스트 랩 입력 고스트를 저장·재생한다. 키보드/게임패드·마우스 모두 지원한다.

| 콘텐츠 | 목록 |
|---|---|
| Light | Comet Feather, Zephyr Needle |
| Medium | Apex Pulse, Copper Arc |
| Heavy | Granite Roar, Basalt Crown |
| 경기 트랙 | Ridgeline Circuit, Lumen Underpass, Glacier Crown, Ochre Rift |
| 드라이버 | Aurora Vale, Bramble Knox, Cinder Rook, Echo Meridian, Flint Harbor, Luma Circuit, Nyx Calder, Orin Gale |
| 아이템 | Rocket Dart, Hunter Drone, Spike Mine, Nitro Can, Aegis Bubble, Pulse Blast, Storm Beacon, Triple Dart, Phantom Decoy |

세 테스트 트랙까지 합쳐 validator/sandbox 트랙은 총 7개다. 절차적 카트·드라이버·아이템 아트와 지도 프리뷰를 제공한다.
합성 오디오/voice hook은 ledger에 사유를 명시해 유지한다.

레이스에는 3-2-1-GO/스타트 부스트, 랩·순위·리스폰·카트 충돌,
FINISHING 타임아웃, 최종 HUD(아이템 룰렛/쿨다운, 10 Hz 미니맵,
드리프트 미터, 선택형 속도계, 중앙 경고), 일시정지→설정, 드라이버/카트/
시간/베스트랩 결과표와 재시작/트랙선택/메뉴가 연결된다. 상대 카트 7대는 `ai/`의
Sensors→Navigator→Driver→ItemBrain 파이프라인으로 레이싱라인을 이해하고
코너·추월·회피·지름길·드리프트·아이템 사용을 스스로 판단하는 실제 AI다
(난이도는 선택한 `RaceConfig.ai_difficulty`). 트랙의 아이템박스를
통과하면 순위 기반 룰렛(`items/item_table.gd`)으로 9종 아이템 중 하나가
결정되고, `items/item_manager.gd`가 풀링된 아이템 인스턴스의 생성·틱·회수를
전담한다(발사체/유도/트랩/부스트/실드/범위/리더 견제 7개 카테고리 —
`ARCHITECTURE.md`의 Items pipeline 참고). 아이템 on/off는
난이도 화면의 토글 또는 `RaceConfig.items_enabled`/`tools/run_sim.sh --items on|off`로 전환한다.

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

## 오디오 (Phase 10)

Master / Music / SFX / Engine 볼륨은 설정 화면에서 즉시 적용되며 0은 버스를
완전히 mute한다. 엔진 RPM·드리프트 스퀼·3단계 차임·충돌·피격·부스트·점프·착지·
9종 아이템 발사/명중·획득/룰렛·카운트다운·순위·랩/완주·위협·메뉴 효과음이 연결됐다.
메뉴/레이스/결과 BGM은 크로스페이드하며, 최종 랩 +3% 피치는 Audio 설정에서
끌 수 있다. Pause는 Music을 사용자 볼륨에서 추가로 -8 dB 낮춘다.

총 플레이어는 **3D 16개 + 2D 8개**이며 엔진/스퀼과 BGM 2채널도 이 예산에
포함된다. 플레이어 카트는 거리 감쇠가 없는 2D 엔진을 사용한다. Engine 저역
필터는 플레이어의 오프로드 상태를 기준으로 공용 Engine 버스 전체에 적용된다.

SFX 41개 + BGM 3곡(새 아이템 4개·트랙 3개 ID는 같은 WAV의 별칭)은 외부 다운로드 없는 원본 CC0 합성 플레이스홀더다.
모노 22.05 kHz / PCM16 WAV 총 2,570,360 bytes이며 재생성 명령은 다음과 같다.

```sh
HOME="$PWD/.tmp-home" godot --headless --path . --script tools/gen_placeholder_audio.gd
HOME="$PWD/.tmp-home" godot --headless --path . --import
```

생성기는 `assets/audio/placeholder/*.wav`, 루프 설정을 가진 `*.wav.import`,
`data/audio/{sfx_default,bgm_default}.tres`를 갱신한다. WAV·import·새 GDScript의
uid를 함께 커밋한다. WAV 라이선스는 `assets/audio/placeholder/LICENSE.md`.
실제 에셋 교체와 청음 기반 믹싱은 **TODO(phase-13)** 이다.

Headless에서는 장치 재생을 호출하지 않고 같은 풀·수명·크로스페이드 상태를
진행한다. 테스트는 `AudioManager.sfx_played`/`bgm_changed` 호출 관찰과 버스
설정으로 검증하므로 실제 스피커 출력이나 음질 검증을 대신하지 않는다.

## 실행

```sh
/opt/homebrew/bin/godot --path .
```

메인 메뉴는 방향키/D-pad/좌스틱으로 이동하고 Enter/Space/A로 선택,
Esc/B로 뒤로 간다. Play에서 드라이버·카트·트랙·난이도를 고르면 레이스가
시작된다.
로컬 멀티플레이는 Play → Local Multiplayer에서 각 패드의 A(키보드는
Enter/Space)로 참가한다. 각 참가자는 Up/Down으로 DRIVER/KART 줄을 고르고
Left/Right로 항목을 바꾼 뒤 A/Enter로 READY 한다. B/Esc는 READY 해제 후
퇴장한다. 2명 이상 전원이 READY가 되면 Ridgeline Circuit 3랩이 시작된다.
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
로컬 레이스는 어느 참가자든 전체를 일시정지할 수 있고, Pause 메뉴 입력은
일시정지를 건 장치가 소유한다. 기본 미니맵은 P1만 표시하며 Settings →
Accessibility에서 모든 플레이어 표시로 바꿀 수 있다.

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

# 같은 seed의 items on/off 20쌍, 기본 strict gate
HOME="$PWD/.tmp-home" tools/run_sim.sh --races 20 --difficulty normal

# 12회 혼합 클래스: light/medium/heavy가 각각 최소 1승
HOME="$PWD/.tmp-home" tools/run_sim.sh --races 12 --mixed-karts on

# 10회 크래시/오류 로그 gate (stderr의 오류 한 줄도 실패 처리)
HOME="$PWD/.tmp-home" tools/run_soak.sh

# 특정 실패 seed 재현
HOME="$PWD/.tmp-home" tools/run_sim.sh --races 1 --seed 13
```

현재 테스트 총수, 파싱·트랙·soak·balance 판정은 `DEVLOG.md`의 Phase 11
검증표를 기준으로 한다. 실제 화면과 조작감은 같은 보고서의 플레이 지시로 확인한다.

인자: `--races N`, `--difficulty easy|normal|hard`, `--karts 1..8`, `--laps N`,
`--track track_01|track_02|track_03|track_04|test_loop|test_loop_hills|test_hairpin`, `--items on|off`,
`--mixed-karts on|off`, `--seed N`, `--strict-balance on|off`.
8배속에서도 실제 게임과 같은 1/60초 물리 step을 유지한다. 전원 완주,
카트당 리스폰 ≤2, 카트당 정면 충돌 ≤랩당 3을 넘으면 exit 1이다.
20회 이상은 strict가 기본이고 같은 seed의 items-off 대조군도 검증한다.
JSON은 각 레이스의 결과·DNF 진단·사용/피격·클래스 승수와 summary를 담으며,
`SIM_SUMMARY` 줄에 전체 요약을 별도로 출력한다. `.tmp-home`과 임시 로그는
Git에서 제외하며 게임 프로젝트의 network/TLS 설정은 변경하지 않는다.

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


## Vertical Slice — v0.1

1. 실행 후 **Play → Single Race → Driver → Kart → Ridgeline Circuit → Normal**을 선택한다.
2. W/RT로 가속하고 A/D 또는 좌스틱으로 조향한다. 코너에서 Space/RB를 유지한 뒤
   놓아 미니 터보를 사용하고, 공중에서는 같은 버튼으로 트릭을 시도한다.
3. 아이템 박스를 지나 룰렛이 끝나면 E/LB로 사용한다. 3랩을 완주하면 결과에서
   Restart, Track Select, Main Menu 중 선택할 수 있다.
4. Esc/Start로 일시정지한다. 다른 창으로 전환해도 로컬 레이스가 일시정지되며,
   돌아온 뒤 Continue를 눌러 재개한다. 설정에서 셰이크/FOV/스피드라인을 조절한다.

자동 full-flow 테스트는 실제 메뉴 전환부터 3랩, 결과, 재시작, 다시 결과와 메뉴
복귀까지 세 번 반복한다. 상세 결과/밸런스 표/검증 로그는 DEVLOG를 확인한다.
`--races 20` 이상은 strict balance가 기본이며, 8카트·3랩·items on일 때 같은 seed의
items-off 레이스도 실행한다. catch-up 조건은 **lap1 최하위의 순위 상승 on−off ≥0.4**,
선두 피격은 **레이스당 ≤3**이다. `--strict-balance off`는 명시적인 진단용 advisory다.

알려진 제한: 최종 모델/폰트/오디오/트랙 아트, haptics는 Phase 13 대상이다.
아이템 on/off 메뉴 토글과 Time Trial/Grand Prix는 Phase 12 대상이다. 로컬 분할
화면과 네트워크 플레이는 구현하지 않았다. Headless 결과는 실제 화면/청음/조작감,
GPU FPS 또는 native 전체화면 전환 검증을 대신하지 않는다. 제한된 macOS 환경에서
출력되는 certificate/Dummy shader 오류는 `run_soak.sh`를 실패시키며 숨기지 않는다.

창 실행이 가능한 환경의 시각/성능 검증 명령:

```sh
# 각 명령은 백그라운드 실행 후 로그/PNG를 확인한다.
godot --path . res://scenes/test/drive_snapshot.tscn -- /tmp/drive-track0 20 5 drift 0 > /tmp/drive-track0.log 2>&1 &
# 마지막 인자를 1, 2, 3으로 바꿔 나머지 트랙도 확인한다.
godot --path . res://scenes/test/scene_snapshot.tscn -- res://race/race.tscn /tmp/race 20 5 > /tmp/race.log 2>&1 &
tools/perf_check.sh 8 30 > /tmp/perf8.log 2>&1 &
tools/perf_check.sh 12 30 > /tmp/perf12.log 2>&1 &
```


## Phase 12 플레이 지시

```text
1. godot --path . 로 실행. Play → Single Race에서 여섯 카트 카드와 네 트랙을 확인한다.
2. Lumen: 터널의 이동 문을 피하고, 부스트를 가진 상태로 두 골목을 시도한다.
3. Glacier: 얼음 위 조향을 줄이고, 내리막 끝 주황 패드로 협곡을 건넌다.
4. Ochre: 모래 갓길·폭풍을 피하고, 서쪽 안쪽 점프 패드로 Sunbridge에 오른다.
5. Play → Grand Prix: 난이도 선택 후 4경기를 진행한다. 결과의 NEXT RACE로
   넘어가 동일 참가자와 점수 합계를 확인하고 마지막 GP PODIUM을 본다.
6. Time Trial: 3랩을 달린 뒤 다시 시도한다. 반투명 고스트·TIME/BEST/GHOST를
   비교한다. 고스트는 user://ghosts/<track_id>.json에 저장된다.
7. 샌드박스의 T는 7트랙을 순환하고 I는 9아이템을 순환 지급한다.
```

샌드박스 캐시 권한 오류가 있으면 `HOME="$PWD/.tmp-home"`를 접두어로 사용한다.
물리 게임패드·청음·창 모드 시각 품질은 headless 테스트와 별개다.


## Phase 13 build / assets

```sh
HOME="$PWD/.tmp-home" tools/build.sh
```

Godot 4.7 matching templates are required. Missing templates produce exit 2 and
an exact command to install a locally obtained official TPZ. No downloads happen.
The Phase 13 finish check on this machine returned exit 2: matching export
templates are absent from the project-local HOME. Install them into the printed
directory and rerun the same command.
Installed templates produce `build/windows/TurboCircuit.exe`,
`build/macos/TurboCircuit.zip`, and `build/linux/TurboCircuit.x86_64`.
The macOS export is unsigned. Cross-platform runtime testing is not implied by an
export command succeeding.

Original art is generated offline:

```sh
HOME="$PWD/.tmp-home" godot --headless --path . -s tools/generate_ui_art.gd
# Native session: actual top-down SubViewport renders. Headless: schematic fallback.
godot --path . -s tools/generate_previews.gd
```

Credits/licenses: original procedural art [CC0](assets/art/LICENSE.md), original
synthesized audio [CC0](assets/audio/placeholder/LICENSE.md), Godot default font
retained under upstream licensing. No macOS fonts or downloaded assets are bundled.
For performance, `tools/perf_check.sh 12 30` selects low quality at 1600×900;
headless results cannot establish the 60 FPS GPU acceptance gate.

## LAN 온라인 플레이 (Phase 15)

같은 빌드의 게임을 같은 LAN에 있는 2–4대에서 실행한다.

1. 호스트: 메인 메뉴 **ONLINE → HOST**. 기본 포트는 **24565/UDP**.
2. 참가자: **ONLINE**에서 호스트의 LAN IP와 같은 포트를 입력하고 **JOIN**.
3. 각자 드라이버·카트를 고르고 **READY**, 호스트가 **START**.
4. Ridgeline에서 기존 가속·조향·드리프트·아이템 조작으로 완주한다. 각 기기는 자기 카메라/HUD만 표시한다.
5. 호스트 종료 또는 경기 중 참가자 이탈 시 메뉴로 돌아가 연결 종료 메시지를 표시한다. 온라인 중 전체 경기 일시정지는 지원하지 않는다. 결과의 재시작/트랙 선택은 메뉴로 돌아가 새 로비를 만든다.

자동 검증은 두 개의 실제 headless 프로세스를 사용한다:

```sh
NET_TEST_LABEL=zero tools/run_net_test.sh
NET_TEST_LABEL=latency tools/run_net_test.sh --net-latency 100 --net-loss 0.02
```

`--net-latency`는 **각 방향 편도 지연(ms)**이다. 따라서 100이면 약 200ms RTT이고,
손실은 입력/스냅샷에 적용한다. 신뢰 전송은 지연만 적용한다. 로그는 `.omc/phase15-logs/`.
같은 입력 tick의 보정 전 로컬 예측 위치와 서버 위치를 비교해 평균 <0.5m, 최대 <3m를 검사한다.
리모트 카트는 보간 대상이며 로컬 예측 통계로 보고하지 않는다.
현재 실행 샌드박스는 UDP bind 자체를 거부하여 두 조건 모두 호스트 생성에서 차단되었다.
LAN 완주·지연 오차 수치·창 모드 조작감은 아직 검증되지 않았다.

## 인터넷 플레이 (Phase 16)

같은 LAN이 아니어도, 같은 버전의 빌드를 실행하는 두 사람이 인터넷으로 만날 수 있다.

1. 호스트: **ONLINE → HOST**. 라우터가 UPnP를 지원하면 포트가 자동으로 열리고
   **HOST CODE**(10자 코드, 예 `4F7QK2M9XR`)가 표시된다. UPnP가 없으면
   "UPnP unavailable — forward UDP port N manually" 안내와 함께 해당 UDP 포트를
   라우터에서 수동으로 포워딩해야 한다.
2. 참가자: **ONLINE → JOIN** 입력란에 호스트 코드 또는 `ip[:port]`를 입력한다.
   호스트가 비밀번호를 설정했다면 같은 비밀번호를 입력한다.
3. 이중 NAT 등으로 포트 포워딩이 불가능하면, 공인 IP를 가진 아무 VPS/PC에서
   `tools/run_server.sh` 대신 릴레이 프로세스를 띄우고(아래) 로비의
   "Use relay ip:port"와 방 코드를 양쪽에 동일하게 입력한다.
4. 전용 서버로도 플레이할 수 있다: `tools/run_server.sh --port 24565 --track track_01 --laps 2 --ai 2 --max-players 8`.
   서버는 사람이 아니라 카트 슬롯이 없는 순수 진행자다. 1명 이상이 READY되고
   전원 READY 또는 20초가 지나면 자동 시작하며, 결과 화면 이후 자동으로
   빈 로비로 돌아가 접속을 유지한 채 다음 경기를 받는다.

레이스 중 HUD 우상단에 PING/LOSS가 표시되고, 스냅샷이 2초 이상 끊기면
"RECONNECTING…" 오버레이가 뜬다. 버전이 다른 클라이언트, 틀린 비밀번호,
정원 초과 접속은 접속 직후 사유 메시지와 함께 거부된다.

자동 검증(전용 서버 + 자동 조종 클라이언트 2명, 1랩 완주 후 서버가 로비로 복귀):

```sh
tools/run_server_test.sh
```

릴레이는 순수 UDP 포워더로, 어떤 무료 VPS나 항상 켜진 PC에서도 돌릴 수 있다:

```sh
tools/run_relay.sh --port 24565
```
