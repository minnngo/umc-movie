#!/usr/bin/env bash
# zero-downtime-lab(localhost:9376)에 측정을 시작시킵니다. before/after 가 같은 조건이 되도록 고정값을 씁니다.
#   bash deploy/lab-start.sh http://<EC2 IP>:3000  300    # before
#   bash deploy/lab-start.sh http://<ALB DNS>      900    # after
set -euo pipefail
BASE=${1:?대상 주소 (예: http://1.2.3.4:3000)}
DURATION=${2:-300}
LAB=${LAB:-http://localhost:9376}

# 엔드포인트: 이메일 중복 확인 (인증 불필요 · DB 조회 · 데이터가 쌓이지 않음)
jq -n --arg url "${BASE%/}/members/email/lab{{counter}}@test.local" --argjson d "$DURATION" '{
  name: "배포 유실 측정",
  target: { url: $url, method: "GET", headers: {}, body: "", timeoutMs: 5000 },
  success: { statusCodes: [200] },
  load: { rps: 20, durationSec: $d },
  analysis: { slowThresholdMs: 1000, baselineSec: 30, minConsecutiveFailures: 3 }
}' | curl -sS -X POST "$LAB/api/runs" -H 'Content-Type: application/json' -d @-
echo
echo "브라우저 $LAB 에서 진행 상황을 보세요. 베이스라인 30초가 지난 뒤 배포를 시작하세요."
