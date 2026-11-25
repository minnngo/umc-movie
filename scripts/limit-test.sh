#!/usr/bin/env bash
# 2주차 6.1 — 한계 측정. RPS 단계마다 새 회원을 만들어 POST /movie-records 에 부하를 건다.
#   사용법: bash scripts/limit-test.sh 200 400 600 800 1000 1200 1500
#   전제:  zero-downtime-lab 이 localhost:9376 에서 떠 있어야 한다.
#   결과:  deploy/results/limit-<rps>.json  +  한 줄 요약
set -euo pipefail
cd "$(dirname "$0")/.."

REGION=${AWS_REGION:-ap-southeast-2}
LAB=${LAB:-http://localhost:9376}
DURATION=${DURATION:-40}
GAP=${GAP:-70}            # CloudWatch 1분 해상도에서 단계가 섞이지 않도록 쉬는 시간
TAG=${TAG:-}              # lab 여러 개를 동시에 돌릴 때 결과 파일 구분용 (예: TAG=b)
ALB=$(aws elbv2 describe-load-balancers --region "$REGION" --names umc-alb \
        --query 'LoadBalancers[0].DNSName' --output text)
BASE="http://$ALB"
PW='Limit1234!'
mkdir -p deploy/results

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

first=1
for RPS in "$@"; do
  [ $first -eq 1 ] || sleep "$GAP"
  first=0

  # 1. 이 단계 전용 회원 — (회원, 영화) 유니크 제약 때문에 매번 새로 만든다
  TS=$(date +%s)
  EMAIL="limit-$TS-$RPS-$$@test.com"
  NICK="l${TS: -4}$$"   # 닉네임 중복·12자 제한 회피
  curl -sf -X POST "$BASE/members" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\",\"nickname\":\"$NICK\"}" >/dev/null
  TOK=$(curl -sf -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}" | json 'd["result"]["accessToken"]')

  # 2. 부하 전에 손으로 한 건 — 201 이 아니면 시나리오가 틀린 것이니 멈춘다
  #    movieId 는 lab 의 {{counter}}(1부터)와 겹치지 않게 큰 값을 쓴다
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/movie-records" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" \
    -d '{"movieId": 999999999, "score": 5, "comment": "t", "addToFavorites": true}')
  if [ "$CODE" != 201 ]; then echo "[$RPS] 사전 확인 실패: $CODE" >&2; exit 1; fi

  # 3. 부하
  SCENARIO=$(python3 - "$BASE" "$TOK" "$RPS" "$DURATION" <<'PY'
import json, sys
base, tok, rps, dur = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
print(json.dumps({
  "name": f"한계측정 {rps}rps",
  "target": {"url": f"{base}/movie-records", "method": "POST",
             "headers": {"Content-Type": "application/json", "Authorization": f"Bearer {tok}"},
             "body": "{\"movieId\": {{counter}}, \"score\": 5, \"comment\": \"lab\", \"addToFavorites\": true}",
             "timeoutMs": 5000},
  "success": {"statusCodes": [200, 201]},
  "load": {"rps": rps, "durationSec": dur},
  "analysis": {"slowThresholdMs": 1000, "baselineSec": 8, "minConsecutiveFailures": 3},
}, ensure_ascii=False))
PY
)
  START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  RUN=$(curl -sf -X POST "$LAB/api/runs" -H 'Content-Type: application/json' -d "$SCENARIO" \
          | json 'd["runId"]')
  until [ "$(curl -s "$LAB/api/runs/$RUN" | json 'd["status"]')" = finished ]; do sleep 2; done
  END=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  curl -s "$LAB/api/runs/$RUN" > "deploy/results/limit-$RPS$TAG.json"
  python3 - "deploy/results/limit-$RPS$TAG.json" "$RPS" "$DURATION" "$START" "$END" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); rps, dur = int(sys.argv[2]), int(sys.argv[3])
t, p = d["totals"], d["percentiles"]
fails = ", ".join(f"{k} {v}" for k, v in t["byType"].items() if v) or "-"
print(f"rps={rps} start={sys.argv[4]} end={sys.argv[5]} sent={t['sent']} "
      f"throughput={t['success']/dur:.1f}/s p50={p['p50']} p95={p['p95']} p99={p['p99']} "
      f"fail={t['failure']} ({fails}) dropped={t['dropped']}")
PY
done
