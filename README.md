# arcade-kart-racer

Mario Kart에서 *시스템과 플레이 감각*만 영감을 받은 **완전 오리지널 3D 아케이드 카트 레이싱 게임** 프로젝트.
엔진: **Godot 4.7 + GDScript**.

## 이 레포의 현재 상태

아직 게임 코드는 없다. 지금은 AI 코딩 에이전트(Claude Code / Codex / Cursor)에게 그대로 전달할
**최종 개발 프롬프트**가 들어 있다.

- [`KART_RACING_DEV_PROMPT.md`](KART_RACING_DEV_PROMPT.md) — 개발 프롬프트 전체 (아키텍처, 물리, 드리프트, 아이템, AI, Phase 0~15, DoD, 작업 규칙)

## 사용법

1. AI 코딩 에이전트를 이 레포 루트에서 연다.
2. `KART_RACING_DEV_PROMPT.md` 내용을 첫 메시지로 전달한다.
3. 에이전트는 Phase 0부터 시작하고, Phase마다 브랜치 `phase/NN-<name>` → PR → 보고 → 사용자 승인 후 머지.

## 워크플로우

- `main`은 항상 승인된 Phase까지만 포함.
- 모든 변경은 PR로만 머지.
- Phase 완료 보고는 `DEVLOG.md`에 누적 (Phase 0에서 생성).
