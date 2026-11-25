# 2주차 미션 — SLO 정의서 + 한계 측정 리포트

- 측정일: 2026-11-26 (KST 00:00 전후, UTC 2026-11-25 15:00 전후)
- 구성: `ALB + EC2 t4g.micro ×2 (ASG, launch template v4) + RDS db.t4g.micro (MySQL)`, 리전 ap-southeast-2(시드니)
- 앱: Spring Boot, 이미지 `v0.0.1-26-11-25-2`, HikariCP 기본 풀 10 / 인스턴스
- 부하: zero-downtime-lab (로컬 노트북, 한국 → 시드니). 대상 `POST /movie-records` (트랜잭션 안에서 쿼리 5회)
- 원본: `deploy/results/limit-*.json`

---

## 1. SLO 정의서

### 1.1 대상 사용자 여정

| 여정 | 엔드포인트 | 왜 이걸 고르나 |
| --- | --- | --- |
| 영화 기록 남기기 | `POST /movie-records` | 쓰기 경로. 트랜잭션 안에서 쿼리 5번 → 가장 먼저 꺾인다 |
| 그 외 API 전체 | `/members/**`, `/ratings/**`, `/favorites/**` 등 | 가용성만 본다 |

`/health`(ALB 헬스체크)와 `/actuator/**`(Alloy 스크랩)는 사용자 트래픽이 아니므로 모든 SLI 에서 제외한다.

### 1.2 SLI · SLO

| # | SLI (무엇을 재나) | 측정 위치 | SLO (목표) | 기간 |
| --- | --- | --- | --- | --- |
| 1 | **가용성** — 5xx 가 아닌 응답의 비율 | 앱 (`http_server_requests_seconds_count`) | **99.5 %** | 30일 롤링 |
| 2 | **지연** — 500ms 안에 끝난 `POST /movie-records` 비율 | 앱 (`http_server_requests_seconds_bucket{le="0.5"}`) | **99 %** | 30일 롤링 |
| 3 | **지연(꼬리)** — `POST /movie-records` p95 | 앱 히스토그램 | **300ms 이하** (5분 창) | 상시 |

- SLI 2 는 `application.yaml` 의 `slo` 버킷(50ms ~ 3s)에 `0.5` 가 있어서 **보간 없이 정확히** 셀 수 있다. 그래서 백분위수(SLI 3)보다 SLO 판정에 더 적합하다.
- 앱에서 재는 값은 **서버 처리 시간**이다. 사용자가 체감하는 시간에는 네트워크 왕복이 더해진다 (이번 측정에서 한국 → 시드니 왕복만 약 220ms).

```promql
# SLI 1 — 가용성
1 - (
  sum(rate(http_server_requests_seconds_count{application="movie", status=~"5..", uri!~"/actuator.*|/health"}[30d]))
  / sum(rate(http_server_requests_seconds_count{application="movie", uri!~"/actuator.*|/health"}[30d]))
)

# SLI 2 — 500ms 안에 끝난 비율
sum(rate(http_server_requests_seconds_bucket{application="movie", uri="/movie-records", le="0.5"}[30d]))
/ sum(rate(http_server_requests_seconds_count{application="movie", uri="/movie-records"}[30d]))

# SLI 3 — p95 (초)
histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{application="movie", uri="/movie-records"}[5m])))
```

### 1.3 에러 버짓

| SLO | 30일 에러 버짓 |
| --- | --- |
| 가용성 99.5 % | 실패 요청 0.5 % ≒ 전 기간 다운이라면 **3시간 36분** |
| 지연 99 % | 500ms 를 넘는 요청 1 % |

버짓을 절반 이상 쓰면 기능 배포보다 안정화 작업을 먼저 한다.

### 1.4 알림

| 알림 | 조건 | 근거 |
| --- | --- | --- |
| p95 지연 | 앱 히스토그램 p95 **> 500ms, 1분 지속** | 처음엔 1s 로 잡았으나 포화(클라이언트 p95 4s)에서도 앱 기준 p95 는 약 1.0s 에 머물러 울리지 않았다. 앱 타이머는 Tomcat 이 요청을 받기 전 대기(TCP·accept 큐)를 재지 못하기 때문. 500ms 로 낮춰 수신 확인 (2026-11-26 00:46, A=1.001) |
| 5xx 비율 | **> 1 %, 5분 지속** | 가용성 SLO 99.5 % 의 버짓을 빠르게 태우는 속도 |
| 앱 다운 | `up` < 1, 1분 지속 | 지표가 아예 안 오는 상태는 위 두 알림이 못 잡는다 |

알림 질의는 `deploy/promql.md` 참고.

### 1.5 용량 목표

| 항목 | 값 |
| --- | --- |
| 측정된 한계 (처리량이 꺾이기 전) | 약 **830 req/s** (목표 1000rps) |
| 운영 상한 (한계의 70 %) | **약 580 req/s** — 이 이상이 지속되면 증설 |
| 증설 단위 | 인스턴스 1대 추가 시 약 +400 req/s 예상 (단, 아래 4장의 DB 커넥션 한계 고려) |

---

## 2. 한계 측정 리포트

> 💡 **처리량이 꺾이는 지점은 `1000` RPS 이다.**
> 목표 1000rps 에서 실제 처리량 약 830/s, p95 0.4s 로 버텼고, 목표 1200rps 에서 처리량이 **692/s 로 오히려 떨어지고** p95 가 **4.6s** 로 치솟았다.

| 목표 RPS | 처리량 | p95 | 실패(유형) | CPU (EC2 a / b) | `threads_connected` | `threads_running` (최대 / 평균) |
| --- | --- | --- | --- | --- | --- | --- |
| 200 | 199.8/s | 233ms | 0 | 12% / 11% | 23 | 5 / 3.0 |
| 400 | 398.3/s | 235ms | 0 | 17% / 12% | 23 | 8 / 4.3 |
| 600 | 593.8/s | 316ms | 0 | 29% / 21% | 23 | 14 / 7.7 |
| 800 | 781.4/s | 421ms | 0 | 28% / 25% | 23 | 21 / 10.0 |
| 1000 | 832.6/s | 398ms | 0 (부하기 dropped 6,694) | 22% / 25% | 23 | 17 / 9.9 |
| **1200** | **691.6/s** | **4,650ms** | **19,103** (timeout 17,175 · network 1,918 · client 10) | 50% / 27% | 23 | 20 / 10.6 |

측정값 출처:

- 처리량·p95·실패: zero-downtime-lab (클라이언트 기준, 네트워크 왕복 약 220ms 포함). 처리량 = 성공 / 40초.
- CPU: CloudWatch `CPUUtilization` 1분 최대값 (세부 모니터링). RDS CPU 는 200→1200 에서 21 → 32 → 39 → 45 → 42 → 47 %.
- `threads_*`: 인스턴스의 Alloy MySQL exporter 를 2초마다 샘플링 (`mysql_global_status_threads_*`).
- 200·400 은 인스턴스 교체 직후(JVM 웜업 전) 한 번 쟀을 때 p95 945ms / 1,063ms 가 나와 웜업 후 다시 쟀다. 웜업 전 값은 `limit-200-cold.json`, `limit-400-cold.json`.
- 1000 까지는 lab 1개, 1200 은 lab 2개 × 600rps 동시 실행(`limit-1200-a.json` + `limit-1200-b.json`). lab 은 1개당 1000rps 가 상한이다.
- OOM 이후 망가진 상태에서 잰 값은 `limit-800-after-oom.json`, `limit-1000-after-oom.json` (3.2 참고).

### 2.1 포화인가, 시나리오 오류인가

| 판단 기준 | 1200rps 결과 | 판정 |
| --- | --- | --- |
| 실패 유형 | timeout 90 % | 포화 |
| p95·p99 | 0.4s → **4.6s / 4.9s** | 포화 |
| 처리량 | 목표 1200 → **692/s** (1000 때보다 낮음) | 포화 |
| 사전 수동 요청 | 각 단계 전 201 확인 | 시나리오 정상 |

### 2.2 1000rps 의 `dropped` 는 서버 문제가 아니다

1000rps 에서 처리량이 830/s 에 머문 것은 **부하기(노트북 Node.js)가 슬롯을 못 쏘고 버린 것(dropped 6,694)** 이다.
서버 쪽은 실패 0, p95 398ms 로 멀쩡했다. 그래서 진짜 한계는 **830 ~ 1200 사이 어딘가**이고, 이번 장비로는 그 사이를 더 잘게 재지 못했다.

---

## 3. 원인 — 왜 꺾였나

### 3.1 CPU 도, DB 도 아니었다

- EC2 CPU 는 포화 직전까지 30 % 이하, RDS CPU 는 최대 47 %. **어느 쪽도 바닥나지 않았다.**
- `threads_connected` 는 처음부터 끝까지 **23 으로 고정**이다. 앱 2대 × HikariCP 풀 10 = 20 (+ exporter 등). 풀 크기가 DB 로 가는 문을 고정해 두고 있다.
- `threads_running` 은 부하에 비례해 오르다가 800rps 부터 **최대 20 근처에서 멈춘다** — 풀 20개가 전부 쿼리 중인 상태. 이 이상 들어오는 요청은 DB 가 아니라 **앱 안의 커넥션 풀 대기열**에서 기다린다.

### 3.2 무너진 직접 원인은 메모리 (OOM)

포화 구간 이후 인스턴스 a(`i-062ae941e05fb31f9`)의 커널 로그:

```
[15:14:00] Out of memory: Killed process 25311 (java) anon-rss:530584kB
[15:16:25] Out of memory: Killed process 33132 (java) anon-rss:555768kB
```

- t4g.micro 메모리 910MB 에 JVM(`-XX:MaxRAMPercentage=70` → 힙 최대 약 640MB) + Alloy 165MB + docker 가 함께 산다.
- 풀 대기열에 요청이 쌓이면 Tomcat 스레드(기본 최대 200)와 요청 객체가 늘어나 **힙 밖 메모리까지 커지고**, 결국 커널이 java 를 죽였다.
- 앱이 재시작하는 동안 ALB 가 연결을 못 해 **502 가 3,197건** 났다 (`HTTPCode_ELB_502_Count`, 앱이 낸 5xx 는 0).
- 그 결과 1200rps 직후에 다시 잰 800 / 1000rps 는 처음과 달리 timeout 6,018건 / 502 4,108건으로 망가졌다. **한 번 포화되면 스스로 회복하지 못하는** 구성이라는 뜻이다.

### 3.3 정리

```
요청 증가 → 커넥션 풀(20) 포화 → 풀 대기열·Tomcat 스레드 누적 → 메모리 증가
          → 커널 OOM 이 java 종료 → ALB 502 → 남은 1대에 부하 집중 → 연쇄 악화
```

---

## 4. 개선 방향 (적용 안 함, 다음 단계 후보)

| 방향 | 기대 효과 |
| --- | --- |
| `-XX:MaxRAMPercentage` 70 → 50~55 | 힙을 줄여 스레드 스택·메타스페이스·Alloy 몫 확보 → OOM 대신 응답 지연으로 끝나게 |
| `server.tomcat.threads.max` 200 → 50 수준, `accept-count` 제한 | 풀(10)보다 훨씬 많은 스레드가 줄 서 있을 이유가 없다. 넘치는 요청은 빨리 거절(503) → 서버는 산다 |
| HikariCP `connection-timeout` 단축 (기본 30s → 2~3s) | 풀 대기가 길어지면 빨리 실패시켜 메모리 누적 방지 |
| ASG 대상 추적 정책 (`ALBRequestCountPerTarget` ≈ 300) | 한계(인스턴스당 약 415/s)의 70 % 에서 자동 증설 |
| 인스턴스 t4g.small (2GB) | 가장 단순한 해법. 단, 풀 × 대수가 RDS `max_connections`(**60**, 실측) 를 넘지 않게 — 지금도 20 + exporter 를 쓰고 있어 인스턴스 3~4대면 한계 |

---

## 5. 아직 못 한 것 / 한계

- **Grafana 화면 증거**: 이 리포트의 수치는 lab · CloudWatch · exporter 직접 샘플링으로 모았다. Grafana 대시보드 캡처(처리량·p95 가 벌어지는 그래프)와 `hikaricp_connections_pending` 그래프를 붙이면 3장의 "풀 대기" 주장이 직접 증명된다.
- **p95 Alert 수신 스크린샷**: Grafana Alerting 에서 직접 설정 필요.
- 부하기가 한국, 서버가 시드니라 클라이언트 p50 에 왕복 약 220ms 가 늘 들어 있다. 서버 처리 시간만 보려면 Grafana 의 앱 히스토그램 p95 를 함께 적는다.
