# PromQL — Spring Boot(Micrometer) 지표 이름 기준

워크북의 PromQL 은 Node.js(`prom-client`) 이름(`http_requests_total`, `http_request_duration_seconds_bucket`)으로 되어 있습니다.
Spring Boot 는 Micrometer 가 `http.server.requests` 하나로 계측하고, Prometheus 에는 아래 이름으로 나갑니다.

| 워크북 (Node.js) | 이 앱 (Spring Boot) |
| --- | --- |
| `http_requests_total` | `http_server_requests_seconds_count` |
| `http_request_duration_seconds_bucket` | `http_server_requests_seconds_bucket` |
| 라벨 `route` | 라벨 `uri` |
| 라벨 `status` | 라벨 `status` (같음) |
| `nodejs_eventloop_lag_seconds` | (해당 없음) → `hikaricp_connections_pending`, `jvm_threads_live_threads` |

모든 질의에서 `/actuator/prometheus`(Alloy 스크랩)와 `/health`(ALB 헬스체크)는 빼야 실제 사용자 트래픽만 남습니다.
아래에서 `$F` 는 이 필터를 뜻합니다 — Grafana 에 붙여 넣을 때 그대로 치환하세요.

```
$F = application="movie", uri!~"/actuator.*|/health"
```

## 대시보드 패널

| 질문 | PromQL |
| --- | --- |
| 초당 요청 수 | `sum(rate(http_server_requests_seconds_count{application="movie", uri!~"/actuator.*\|/health"}[1m]))` |
| p95 지연(ms) | `histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{application="movie", uri!~"/actuator.*\|/health"}[1m]))) * 1000` |
| p99 지연(ms) | `histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{application="movie", uri!~"/actuator.*\|/health"}[1m]))) * 1000` |
| 에러율 | `sum(rate(http_server_requests_seconds_count{application="movie", status=~"5.."}[5m])) / sum(rate(http_server_requests_seconds_count{application="movie", uri!~"/actuator.*\|/health"}[5m])) or vector(0)` |
| 경로별 p95 | `histogram_quantile(0.95, sum by (le, uri) (rate(http_server_requests_seconds_bucket{application="movie", uri!~"/actuator.*\|/health"}[5m])))` |
| 인스턴스별 처리량 | `sum by (instance) (rate(http_server_requests_seconds_count{application="movie", uri!~"/actuator.*\|/health"}[1m]))` |
| CPU 사용률 | `1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[1m]))` |
| JVM 프로세스 CPU | `process_cpu_usage{application="movie"}` |
| 메모리 사용률 | `1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` |
| 힙 사용량 | `sum by (instance) (jvm_memory_used_bytes{application="movie", area="heap"})` |
| DB 커넥션 수 | `max(mysql_global_status_threads_connected)` |
| 실행 중인 쿼리 | `max(mysql_global_status_threads_running)` |
| 커넥션 풀 사용 중 | `sum(hikaricp_connections_active{application="movie"})` |
| **커넥션 풀 대기** | `sum(hikaricp_connections_pending{application="movie"})` |
| 커넥션 획득 시간 최대 | `max(hikaricp_connections_acquire_seconds_max{application="movie"})` (히스토그램을 켜지 않아 `_bucket` 은 없음) |

> 앱 2대 × HikariCP 기본 풀 10개 = `threads_connected` 가 20 근처에서 고정됩니다.
> 포화 시 `threads_connected` 는 그대로이고 **`hikaricp_connections_pending` 이 치솟는지**를 봐야 병목이 풀인지 DB 인지 구분됩니다.

## 알림

### p95 지연 (미션 스크린샷용)

```
histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{application="movie", uri!~"/actuator.*|/health"}[1m]))) or vector(0)
```

- 조건: `IS ABOVE 0.5` (초 단위), pending period `1m`
- `1` 로 잡으면 포화 상태에서도 거의 울리지 않습니다. 앱 타이머는 Tomcat 스레드가 요청을 집은 뒤부터 재므로,
  포화 시 대부분의 대기(TCP·accept 큐)가 빠집니다. 실측: 클라이언트 p95 4.2s 일 때 앱 p95 ≈ 1.0s.
- 트래픽이 없을 때 `histogram_quantile` 은 `NaN` 을 냅니다. `NaN > 0.5` 은 거짓이라 발화하지 않으므로 OK 로 남습니다.
  `No data` 는 `or vector(0)` 으로 막습니다.

### 5xx 에러율 (워크북 7.2)

```
sum(rate(http_server_requests_seconds_count{application="movie", status=~"5.."}[5m])) / sum(rate(http_server_requests_seconds_count{application="movie", uri!~"/actuator.*|/health"}[5m])) or vector(0)
```

- 워크북의 `IS ABOVE 1` 은 비율(0~1)이라 **절대 울리지 않습니다.** 1% 기준이면 `IS ABOVE 0.01` 로 넣으세요.

### 앱 다운

```
min(up{job=~".*app.*"}) or vector(0)
```

- 조건: `IS BELOW 1`, pending `1m`
