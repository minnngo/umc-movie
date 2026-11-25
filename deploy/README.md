# 무중단 배포 미션 — 실행 순서

모든 명령은 `~/Development/movie` 에서 실행합니다. 스크립트는 여러 번 실행해도 안전하게 짜여 있습니다.

## 0. 준비 (한 번만)

| 항목 | 상태 |
|---|---|
| AWS CLI | 설치됨 (`brew install awscli`) |
| zero-downtime-lab | `~/Development/zero-downtime-lab` 에 클론 · `npm start` → http://localhost:9376 |
| 앱 코드 | `/health` 추가, `application.yaml` 환경변수화, graceful shutdown, `Dockerfile` |
| RDS | **직접 준비** — 10주차 RDS(MySQL)를 그대로 쓰면 됩니다 |

```bash
aws login --region ap-southeast-2   # 이 계정(프로젝트)은 시드니 리전만 허용
aws sts get-caller-identity
```

## 1. 기반 자원 만들기 (ECR · SSM · IAM · SG · 시작 템플릿)

```bash
bash deploy/01-bootstrap.sh
```

중간에 RDS 엔드포인트 · DB 사용자 · DB 이름 · DB 비밀번호를 물어봅니다. 비밀번호는 화면에 안 보입니다.
RDS 가 비어 있으면(테이블 없음) `ddl-auto` 에 `update` 를 넣으세요. RDS 보안 그룹 ID 를 넣으면 3306 인바운드를 열어줍니다.

## 2. "단일 배포" 측정 (before)

```bash
bash deploy/02-single-ec2.sh                       # EC2 한 대, 3000 포트 직접 노출. 끝에 URL 출력
bash deploy/lab-start.sh http://<EC2 IP>:3000 300  # 측정 시작 (20 RPS · 5분)
# 30초 기다린 뒤
bash deploy/single-deploy.sh                       # docker stop && docker run
```

측정이 끝나면 lab 화면에서 **총 요청 · 실패 · 실패율 · 순단 · 다운타임 · p95** 를 기록하고 스크린샷 + "결과 JSON 내려받기".

## 3. ALB + ASG 구성

```bash
bash deploy/03-alb.sh     # ALB SG, 앱 SG 를 ALB 로 제한, TG, ALB, 리스너, 단일 인스턴스 종료, ASG(2대)
```

## 4. "무중단 배포" 측정 (after)

```bash
bash deploy/lab-start.sh http://<ALB DNS> 900      # 같은 조건, 주소만 ALB
# 30초 기다린 뒤
bash deploy/deploy.sh                              # Rolling 배포
```

배포 중 `콘솔 > EC2 > 대상 그룹 > umc-app-tg > 대상` 에서 draining 이 보이면 스크린샷.
배포가 끝나면 lab 측정을 **중지**하고 결과 기록.

## 5. 정리 (꼭!)

```bash
bash deploy/99-cleanup.sh
```

ALB(시간당 약 $0.0225 + LCU)와 EC2 2대는 켜두면 계속 과금됩니다. RDS 는 건드리지 않습니다.

## 결과 표 (4.2) — 2026-11-18 실측 (ap-southeast-2, 20 RPS · 300초 · GET /members/email/{email})

|  | 단일 배포 | 무중단 배포 |
| --- | --- | --- |
| 대상 | EC2 퍼블릭 IP에 직접 | ALB |
| 배포 | docker stop && docker run | 컨테이너 교체 (Rolling: deregister → swap → register) |
| 총 요청 | 6,001 | 6,000 |
| 실패 | 266 (전부 network) | 0 |
| 실패율 | 4.4% | 0% |
| 순단 | 1회 | 0회 |
| 다운타임 | 13,349ms | 0ms |
| p95 | 338ms | 230ms |

원본: `deploy/results/before-single.json`, `deploy/results/after-rolling.json`
