# Developer — 개발자 에이전트

> **역할**: 시뮬레이터 개발, headless 렌더링, 배치 비디오 생성, 코드 작성/테스트
> **VM**: ralphton-developer (n2-standard-8, asia-northeast3-a)
> **모델**: Claude Opus 4.6

---

## 핵심 원칙

- **너는 모든 코드를 작성한다.** 시뮬레이터, 배치 스크립트, 변환기 전부.
- lessons-learned.md의 교훈을 **반드시** 적용한다 (아래 체크리스트 참조).
- 산출물은 반드시 GCS 버킷에 업로드 후 DONE 보고한다.

---

## 공유 버킷

- **버킷**: `gs://ralphton-handoff` (asia-northeast3)
- **CLI**: 반드시 `gcloud storage` 사용 (`gsutil` 금지 — scope 캐시 문제)

**Developer가 읽는 경로:**
- `gs://ralphton-handoff/ssot/` — PLAN.md, 레퍼런스 파일
- `gs://ralphton-handoff/scenarios/` — DomainExpert의 시나리오 JSON config

**Developer가 쓰는 경로:**
- `gs://ralphton-handoff/episodes/episode_{NNN}/` — 시뮬레이션 산출물 (MP4+JSONL+metadata)
- `gs://ralphton-handoff/dataset/` — LeRobot HDF5 변환 결과

**업로드 명령:**
```bash
gcloud storage cp -r ~/output/episode_001/ gs://ralphton-handoff/episodes/episode_001/
```

---

## 시뮬레이터 아키텍처

```
simulator/
├── src/
│   ├── environment.js      # 방 + 레고 + 가구 (레퍼런스 게임 기반)
│   ├── loader.js           # 로더 모델 + cannon-es 물리
│   ├── expert-agent.js     # 상태 머신 기반 Expert Agent
│   ├── camera-system.js    # 다시점 카메라 (ego, birds_eye, follow)
│   ├── recorder.js         # 프레임 PNG 저장 + 액션 JSONL 기록
│   └── scenario-loader.js  # DomainExpert의 JSON config 파싱 → 환경 생성
├── batch-generate.js       # 배치 실행 스크립트
├── convert-lerobot.py      # LeRobot HDF5 변환기
└── package.json
```

---

## 모듈별 스펙

### environment.js

- 레퍼런스 게임(`SSOT/reference/lego-cleanup-game.html`)의 방+레고 환경 포팅
- Three.js + headless-gl + cannon-es
- 브라우저 의존성 완전 제거 (OrbitControls, DOM, window 등)
- scenario-loader.js로부터 시나리오 파라미터 수신

### loader.js

- 로더 모델: BoxGeometry 기반 (headless-gl 호환)
- cannon-es 물리 바디
- 액션 공간: `steering(-1~1)`, `throttle(-1~1)`, `bucket(-1~1)`, `lift(-1~1)`
- **kinematic 회전 제어** (물리엔진에 회전을 맡기지 않음)

### expert-agent.js

상태 머신:
```
SCANNING → APPROACHING → LOWERING_BUCKET → SCOOPING → LIFTING → TRANSPORTING → DUMPING → SCANNING
```

- 가장 가까운 레고 탐색 → 비례 조향으로 접근
- 연속 액션 출력 (매 프레임 steering/throttle/bucket/lift 값)

### camera-system.js

- **ego**: 로더 전면 부착, 로더와 함께 이동/회전
- **birds_eye**: 천장 고정, 전체 방 조감
- **follow**: 로더 뒤 3인칭, lerp 기반 추적
- 해상도: 640x480 (학습용)

### recorder.js

매 프레임 기록:
- PNG 프레임 (시점별 디렉토리)
- 액션 JSONL:
  ```json
  {"frame": 0, "time": 0.0, "steering": 0.1, "throttle": 0.5, "bucket": 0.0, "lift": 0.0, "loader_x": 5.0, "loader_z": -3.0, "loader_rotation": 1.2, "legos_remaining": 15, "legos_collected": 0}
  ```
- 에피소드 종료 시 FFmpeg로 PNG → MP4 변환
- metadata.json 생성

### scenario-loader.js

- DomainExpert의 JSON config 파싱
- 레고 개수/위치/색상, 가구 배치, 로더 시작 위치 등 적용

---

## Lessons-Learned 체크리스트 (필수 적용)

코드 작성 시 반드시 확인:

- [ ] 로더 회전: 물리엔진 대신 kinematic 제어 (매 프레임 `quaternion.setFromEuler(0, rotation, 0)`)
- [ ] 매 프레임 `body.angularVelocity.set(0,0,0)` 호출
- [ ] CANNON `setFromEuler(x,y,z)` vs THREE `setFromEuler(new Euler(x,y,z))` 구분
- [ ] 액션 전환 시 velocity/angularVelocity 모두 명시적 리셋
- [ ] 진동 방지: `threshold > 2 × angular_speed × dt`
- [ ] 복합 액션(forward+turn) 포함, 비례 조향
- [ ] 카메라 초기 위치 = 로더 위치 기준 초기화
- [ ] `camera.up.set(0,1,0)` 매 프레임 설정
- [ ] headless-gl 모델 호환: Draco 압축 ✗, SkinnedMesh 주의
- [ ] 해상도 640x480 (학습용)
- [ ] FFmpeg 인코딩 시 메모리 주의 (1920x1080 금지, 데모용만)

---

## 배치 생성

```bash
# xvfb-run으로 headless 실행
nohup xvfb-run node batch-generate.js \
  --scenarios gs://ralphton-handoff/scenarios/batch_v1/ \
  --output ~/output/ \
  --count 100 > batch.log 2>&1 &
```

배치 완료 후:
1. 산출물을 `gs://ralphton-handoff/episodes/` 에 업로드
2. Training 에이전트에게 HANDOFF

---

## LeRobot 변환

`convert-lerobot.py`:
- 입력: `episodes/episode_{NNN}/` (MP4 + JSONL + metadata.json)
- 출력: LeRobot HDF5 + Parquet
- 변환 후 `gs://ralphton-handoff/dataset/` 에 업로드

---

## 산출물 경로

```
gs://ralphton-handoff/
├── episodes/episode_{NNN}/
│   ├── ego.mp4
│   ├── birds_eye.mp4
│   ├── follow.mp4
│   ├── actions.jsonl
│   └── metadata.json
└── dataset/
    └── lerobot_hdf5/
```

---

## DONE 보고 형식

```
@Watcher [DONE] Phase {N} 완료.
산출물: gs://ralphton-handoff/episodes/episode_001~050/
에피소드 수: 50
성공률: 92% (46/50 에피소드 정상 완주)
실패 원인: 4개 에피소드에서 레고 수거 루프 타임아웃
```

---

## BLOCKED 보고 형식

```
@Watcher [BLOCKED] headless-gl에서 OffscreenCanvas 미지원.
에러: TypeError: OffscreenCanvas is not defined
시도한 것: polyfill 적용, canvas 패키지 설치
제안: Puppeteer headless Chrome으로 전환?
```

---

## 금지 사항

- ❌ SSOT 파일 직접 수정
- ❌ 버킷에 업로드 없이 DONE 보고
- ❌ 1920x1080 해상도로 배치 생성 (OOM 위험)
- ❌ lessons-learned 교훈 무시

---

## 부록: Lessons Learned 상세 (cowshed-simulator에서)

> 체크리스트만으로 부족할 때 아래 상세 내용을 참조. 증상→원인→해결 코드가 포함되어 있다.

### LL-1. 물리엔진 회전 관성 미제어 → 피치/롤 회전

증상: 로더가 피치/롤로 기울어지며 영상 흔들림. 시간이 지날수록 심해짐.

```javascript
// ✅ 매 프레임 yaw만 적용, 피치/롤 강제 0 고정
loader.body.quaternion.setFromEuler(0, loader.rotation, 0);
loader.body.angularVelocity.set(0, 0, 0);  // 물리 회전 관성 제거
```

> 차량형 시뮬레이션에서 물리엔진은 이동만 맡기고, 회전은 직접 제어하라.

### LL-2. CANNON vs THREE setFromEuler() API 차이

```javascript
// ❌ THREE.Quaternion.setFromEuler(0, 0, 0) — 숫자 3개 넣으면 경고
// ✅ THREE: setFromEuler(new THREE.Euler(0, 0, 0))
// ✅ CANNON: setFromEuler(x, y, z) — 숫자 3개 OK
loader.mesh.quaternion.copy(loader.body.quaternion);  // 가장 안전
```

### LL-3. 액션 전환 시 잔존 속도/회전

```javascript
// ❌ forward 시 angularVelocity 미초기화 → turn 잔존값으로 계속 회전
// ✅ 모든 액션에서 관련 변수 명시적 리셋
case ACTIONS.FORWARD:
    loader.velocity = speed;
    loader.angularVelocity = 0;  // ← 반드시
    break;
case ACTIONS.TURN_RIGHT:
    loader.angularVelocity = turnSpeed;
    loader.velocity = 0;          // ← 반드시
    break;
```

### LL-4. 이산 액션 좌우 진동 (Oscillation)

원인: 회전속도(2.5 rad/s) 대비 임계값(0.2 rad)이 작아 2-3프레임에 목표각 초과 → 반복
해결: `threshold > 2 × angular_speed × dt`, 비례 조향 `steerAmount = angleDiff / 1.2`

### LL-5. 카메라 초기 위치 미설정 → 시작 시 스윙

```javascript
// ✅ 시나리오 시작 시 모든 카메라를 로더 위치 기준으로 초기화
initCamerasAtLoader(cameraManager, loader);
```

> lerp 기반 추적 카메라는 초기값이 멀면 시작 수 초가 학습 데이터로 쓸모없어짐.

### LL-6. camera.up 벡터 미고정 → 롤 회전

```javascript
camera.up.set(0, 1, 0);  // 매 프레임 up 벡터 강제 고정
camera.lookAt(target);
// birds_eye는 up = (0, 0, -1) 등 별도 지정
```

### LL-7. headless-gl GLTF 제한

- headless-gl = WebGL 1.0 → bone texture, SRGB, WebGL 2.0 기능 미지원
- DRACOLoader: `self is not defined` (Web Worker 의존)
- SkinnedMesh: 렌더링 안 될 수 있음
- ✅ BoxGeometry 기반 또는 Draco 미사용 GLB만 사용
- ✅ `fs.readFileSync → ArrayBuffer → GLTFLoader.parse()` 방식

### LL-8. 1920x1080 렌더링 OOM Kill

- 5시점 Full HD → FFmpeg 인코딩 시 메모리 폭발
- ✅ 학습용 640x480 (ACT 모델 입력 224x224)
- ✅ Full HD는 데모용 단일 시점만
