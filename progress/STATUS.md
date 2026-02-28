# Ralphton 진행상황

> 마지막 업데이트: 2026-02-28 21:10 KST (CCD Watchdog 자동 갱신)

## 현재 상태

- **Phase**: Phase 1 → Loop 2 진행 중 (Developer 배치 에피소드 생성 중)
- **Loop**: Loop 2 진행 중 (Developer 자체 시나리오로 배치 생성 착수)
- **전체 VM**: 5/5 RUNNING ✅
- **전체 openclaw**: 5/5 실행 중 ✅

## 에이전트 현황

- **Watcher**: 활성 (0분 전, 21:10) - Evaluation/DomainExpert GCS scope 우회 방법 안내 (gcloud storage cp)
- **Developer**: 활성 (10분 전, 21:00) - Loop 2 배치 생성 착수 중 (자체 시나리오 사용)
- **DomainExpert**: ⚠️ 침묵 (28분 전, 20:42) - 시나리오 13개 생성 완료, GCS 업로드 BLOCKED → Watchdog 트리거 전송됨 (21:10)
- **Training**: ⚠️ 침묵 (24분 전, 20:46) - LeRobot 환경 세팅 중, 에피소드 50개 대기 → Watchdog 트리거 전송됨 (21:10)
- **Evaluation**: 응답 (2분 전, 21:08) - Loop 1 검증 완료, GCS 업로드 BLOCKED (scope), Watcher 우회 방법 수신

## 공통 이슈: GCS scope 문제

- **증상**: DomainExpert, Evaluation VM에서 `gcloud compute scp` / `gcloud storage cp` 실패 (devstorage.read_only scope)
- **Watcher 21:10 우회 방법**:
  - Evaluation: `tar czf eval_artifacts_v1.tgz ...` → Discord 첨부파일 업로드
  - DomainExpert: `gcloud storage cp` 시도 (compute scp ≠ storage cp, 별도 scope)
- **Developer 우회**: 자체 시나리오로 52에피소드 생성 중 (scp 기다리지 않음)

## Loop 1 결과

- 수거 성공률: 70% (에피소드 10개 중 7개)
- 데이터셋: gs://ralphton-handoff/dataset/lerobot_data.hdf5 업로드 완료
- 평가 완료: 에피소드 ep000, ep001 검증 통과 (에러 0건)
- 이슈: bucket 76% zero, lift 84% zero (액션 편향)

## Loop 2 진행 상황

- DomainExpert: "조작(action-rich)" 시나리오 13개 생성 완료 ✅ (DomainExpert VM 내 저장)
  - 경로: `/home/inkeun/scenarios/batch_v2_action_rich/` (DomainExpert VM)
  - FM-C01(가구/벽 근처) 5개, FM-C02(밀집 클러스터) 5개, FM-C04(다양한 크기) 3개
  - ⚠️ gcloud scp 스코프 부족으로 Developer VM 전달 실패 → Developer 자체 구현으로 우회
  - ⚠️ GCS 업로드 시도 필요 (Watchdog 21:10 트리거)
- Developer: 21:00 KST BLOCKED 해제, 자체 시나리오로 52에피소드 생성 착수 중 🔄
  - 목표: 13 시나리오 × 4 에피소드 = 52 에피소드
  - HDF5 v2: ego 1뷰, 320×240 다운스케일 (Watcher 21:01 권고)
- Training: GPU A100 idle, 에피소드 50개 이상 + HDF5 v2 대기 (LeRobot 세팅 중)
- Evaluation: Loop 2 데이터 대기 중, GCS 업로드 우회 조치 수신

## Loop 2 목표 (Watcher 20:46 설정)

- bucket non-zero 비율 ≥ 20%
- lift non-zero 비율 ≥ 20%
- 에피소드 목표: 50개 이상
- HDF5 v2: ego 1뷰, 320×240, fps 감축 (Watcher 21:01 권고)

## Watchdog 조치 내역

- 21:10 KST: DomainExpert (28분 침묵) → Discord REQUEST 메시지 전송 (GCS storage cp 우회 요청)
- 21:10 KST: Training (24분 침묵) → Discord REQUEST 메시지 전송 (LeRobot 세팅 상태 확인)
- 21:05 KST: Evaluation (25분 침묵) → Discord REQUEST 메시지 전송 → Evaluation 응답 완료 ✅ (21:08)
- 20:57 KST: Developer (18분 침묵, Watcher 지시 미응답) → Discord REQUEST 메시지 전송 → Developer 응답 완료 ✅ (21:00)
- 20:41 KST: Training (42분 침묵) → Discord REQUEST 메시지 전송 → Training 응답 완료 ✅
- 모든 VM RUNNING 확인 (5/5)
- 모든 openclaw 프로세스 정상 실행 확인 (5/5)

## 주요 이벤트

- 21:10 KST - Watcher: GCS scope 우회 방법 안내 (Evaluation → Discord 첨부, DomainExpert → storage cp)
- 21:10 KST - Watchdog: DomainExpert(28분) + Training(24분) 트리거 전송
- 21:08 KST - Evaluation: Loop 1 검증 완료 REPORT, GCS BLOCKED 확인
- 21:07 KST - Watchdog→Evaluation: REQUEST 트리거 → 1분 만에 응답
- 21:01 KST - Watcher: HDF5 v2 포맷 가이드 (ego 1뷰, 해상도 다운스케일, fps 감축)
- 21:00 KST - Developer: BLOCKED(scp 실패) 보고 → 자체 시나리오로 52에피소드 생성 착수
- 20:46 KST - Watcher: Loop 2 액션 목표 설정 + Developer에게 배치 생성 지시
- 20:46 KST - Training: GPU A100 idle 확인, LeRobot 환경 세팅 예정 REPORT
- 20:42 KST - DomainExpert: Loop 1 피드백 반영 시나리오 13개 생성 DONE
- 20:41 KST - Watcher: Loop 2 목표 설정 (액션 분포 편향 해소 1순위)
- 20:40 KST - Evaluation: Loop 1 데이터 품질 검증 완료 REPORT
- 20:38 KST - Developer: 레고 10개 중 7개 수거 (70%), 65초 시뮬 완료
