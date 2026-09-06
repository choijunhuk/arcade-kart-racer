# arcade-kart-racer

Mario Kart에서 *시스템과 플레이 감각*만 영감을 받은 **완전 오리지널 3D 아케이드 카트 레이싱 게임** 프로젝트.
엔진: **Godot 4.7 + GDScript**.

## 이 레포의 현재 상태

**Phase 0 — 프로젝트 셋업 / 아키텍처 / 테스트 하네스 완료.**

현재 메인 씬은 그레이박스 타원 트랙, 정지 상태의 플레이스홀더 카트,
고정 카메라, F3 디버그 오버레이가 있는 샌드박스를 연다. 주행 물리,
드리프트, 레이스, 아이템, AI는 이후 Phase 범위이며 아직 구현하지 않았다.

- [`KART_RACING_DEV_PROMPT.md`](KART_RACING_DEV_PROMPT.md) — 개발 프롬프트 전체 (아키텍처, 물리, 드리프트, 아이템, AI, Phase 0~15, DoD, 작업 규칙)
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — 실제 경로와 시스템 경계
- [`DEVLOG.md`](DEVLOG.md) — Phase별 구현 및 검증 기록

## 실행

```sh
/opt/homebrew/bin/godot --path .
```

샌드박스에서는 F3으로 디버그 오버레이를 켜고 끈다. Phase 0 카트는
의도적으로 움직이지 않는다.

## 검증

```sh
# 최초 1회 import와 UID 생성
HOME=$PWD/.tmp-home /opt/homebrew/bin/godot --headless --path . --import

# 파싱 / 부팅 확인
HOME=$PWD/.tmp-home /opt/homebrew/bin/godot --headless --path . --quit

# GUT 전체 테스트
HOME=$PWD/.tmp-home tools/run_tests.sh

# 트랙 구조 검증
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
