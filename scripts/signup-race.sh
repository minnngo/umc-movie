#!/usr/bin/env bash
# 같은 이메일·닉네임으로 회원가입 요청을 동시에 보내 DB UNIQUE 제약 위반을 재현합니다.
# 사용법: ./scripts/signup-race.sh [동시 요청 수(기본 10)]
#
# 요청들이 거의 같은 순간에 사전 중복 체크(existsByEmail)를 통과하면,
# 먼저 저장한 1개만 201이 되고 나머지는 DB UNIQUE 제약에서 막혀 409가 됩니다.
# 매번 새 이메일·닉네임을 쓰므로 실행할 때마다 회원이 1명 생깁니다.

COUNT=${1:-10}
# 닉네임은 12자 이하여야 하므로 시각의 끝 6자리만 씁니다. (race + 6자리 = 10자)
SUFFIX=$(date +%s | tail -c 7)
BODY="{\"email\":\"race${SUFFIX}@example.com\",\"password\":\"Movie123!\",\"nickname\":\"race${SUFFIX}\"}"

echo "요청 Body: ${BODY}"
echo "동시 요청 수: ${COUNT}"
echo

for i in $(seq 1 "$COUNT"); do
  curl -s -o "/tmp/signup-race-$i.json" -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" -d "$BODY" \
    http://localhost:8080/members > "/tmp/signup-race-$i.status" &
done
wait

for i in $(seq 1 "$COUNT"); do
  echo "[$i] HTTP $(cat "/tmp/signup-race-$i.status") $(cat "/tmp/signup-race-$i.json")"
done
