# arcade-kart-racer

Mario Kart에서 *시스템과 플레이 감각*만 영감을 받은 **완전 오리지널 3D 아케이드 카트 레이싱 게임** 프로젝트.
엔진: **Godot 4.7 + GDScript**.

## 이 레포의 현재 상태

**Phase 3 — 드리프트 & 부스트 완료.**

현재 메인 씬은 실제로 주행 가능한 카트(`kart/kart.tscn`), 전환 가능한
세 테스트 트랙(평지/언덕/헤어핀), 지형 감속, 슬립스트림, 무게 기반 카트
충돌, 피격 반응, 낙하/리스폰, 미니 터보 드리프트, 통합 부스트 스택,
부스트 패드/점프대/트릭, 스프링 추적 카메라(드리프트 오프셋 + 부스트
FOV 킥), 드리프트 미터 HUD와 F3 디버그 오버레이가 있는 샌드박스를 연다.
레이스 흐름(체크포인트/랩)·아이템·AI는 이후 범위다.

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
`R` 리셋, `T` 트랙 순환(평지→언덕→헤어핀), `4` 헤어핀 트랙 바로 선택,
`1`/`2`/`3` light/medium/heavy 전환, `B` 충돌용 더미 카트 3대 생성.
F3으로 terrain/slipstream/hit/invulnerable/air_time과 함께
drift_state/drift_charge/drift_tier/boost/trick_armed을 본다.

## 검증

```sh
# 최초 1회 import와 UID 생성
HOME=$PWD/.tmp-home /opt/homebrew/bin/godot --headless --path . --import

# 파싱 / 부팅 확인
HOME=$PWD/.tmp-home /opt/homebrew/bin/godot --headless --path . --quit

# GUT 전체 테스트
HOME=$PWD/.tmp-home tools/run_tests.sh

# 트랙 구조 검증 (test_loop + test_loop_hills + test_hairpin)
HOME=$PWD/.tmp-home tools/validate_tracks.sh

# Phase 6 전까지 성공 메시지만 출력하는 시뮬레이션 자리표시자
tools/run_sim.sh
```

`HOME=$PWD/.tmp-home`은 제한된 샌드박스에서만 필요하다. 일반 로컬
환경에서는 접두어 없이 같은 명령을 실행할 수 있다.

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
