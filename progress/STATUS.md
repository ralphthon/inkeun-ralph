# Ralphton 진행상황

> 마지막 업데이트: 2026-02-28 20:57 KST (CCD Watchdog 자동 갱신)

## 현재 상태

- **Phase**: Phase 1 (시뮬레이터 → 데이터 생성)
- **Loop**: Loop 2 진행 중 (Developer 배치 생성 시작 대기)
- **전체 VM**: 5/5 RUNNING ✅
- **전체 openclaw**: 5/5 실행 중 ✅

## 에이전트 현황

- **Watcher**: 활성 (11분 전) - Loop 2 지시 완료, Developer 응답 대기
- **Developer**: ⚠️ 침묵 (18분 전) - Watchdog 트리거 전송됨 (20:57)
- **DomainExpert**: 활성 (15분 전) - batch_v2_action_rich 시나리오 13개 완료
- **Training**: 활성 (11분 전) - GPU idle, 배치 데이터 대기 중 (정상)
- **Evaluation**: 활성 (17분 전) - Loop 1 검증 완료, Loop 2 대기

## Loop 1 결과

- 수거 성공률: 70% (에피소드 10개 중 7개)
- 데이터셋: gs://ralphton-handoff/dataset/lerobot_data.hdf5 업로드 완료
- 평가 완료: 에피소드 ep000, ep001 검증 통과
- 이슈: bucket 76% zero, lift 84% zero (액션 편향)

## Loop 2 진행 상황

- DomainExpert: "조작(action-rich)" 시나리오 13개 생성 완료 ✅
  - 경로: `/home/inkeun/scenarios/batch_v2_action_rich/`
  - FM-C01(가구/벽 근처) 5개, FM-C02 5개, FM-C03 3개
- Developer: Watcher 지시 수신 후 미응답 → Watchdog 트리거 전송
- Training: GPU A100 idle, 에피소드 50개 이상 대기
- Evaluation: Loop 1 보고서 GCS 업로드 예정

## Loop 2 목표 (Watcher 20:46 설정)

- bucket non-zero 비율 ≥ 20%
- lift non-zero 비율 ≥ 20%
- 에피소드 목표: 50개 이상
- DomainExpert 시나리오 13개 통합

## Watchdog 조치 내역

- 20:57 KST: Developer (18분 침묵, Watcher 지시 미응답) → Discord REQUEST 메시지 전송
- 20:41 KST: Training (42분 침묵) → Discord REQUEST 메시지 전송 → Training 응답 완료 ✅
- 모든 VM RUNNING 확인 (5/5)
- 모든 openclaw 프로세스 정상 실행 확인 (5/5)

## 주요 이벤트

- 20:46 KST - Watcher: Loop 2 액션 목표 설정 + Developer에게 배치 생성 지시
- 20:46 KST - Training: GPU A100 idle 확인, LeRobot 환경 세팅 예정 REPORT
- 20:42 KST - DomainExpert: Loop 1 피드백 반영 시나리오 13개 생성 DONE
- 20:41 KST - Watcher: Loop 2 목표 설정 (액션 분포 편향 해소 1순위)
- 20:40 KST - Evaluation: Loop 1 데이터 품질 검증 완료 REPORT
- 20:39 KST - Developer: SSOT 재확인, 멘션 규칙 강조 반영 REPORT
- 20:38 KST - Developer: 레고 10개 중 7개 수거 (70%), 65초 시뮬 완료
- ~19:59 KST - Training: INSTRUCTIONS 확인 완료 (마지막 메시지 → Watchdog 트리거로 복귀)
