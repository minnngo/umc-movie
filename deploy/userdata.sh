#!/bin/bash
set -euo pipefail          # set -x 를 쓰지 않는다. 비밀값이 로그에 남는다
exec > >(tee /var/log/umc-boot.log) 2>&1

dnf install -y docker
systemctl enable --now docker

# 1. 컨테이너를 unless-stopped 로 띄우는 스크립트. 배포 때도 이 파일을 다시 부른다.
mkdir -p /opt/umc
cat > /opt/umc/swap.sh <<'SWAP'
#!/bin/bash
set -euo pipefail
REGION=__REGION__   # 01-bootstrap.sh 가 실제 리전으로 바꿔 넣습니다
p() { aws ssm get-parameter --region $REGION --name "/umc/app/$1" --with-decryption \
        --query Parameter.Value --output text; }

IMAGE=$(p image)
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin "${IMAGE%%/*}"
docker pull "$IMAGE"

# 이 아래 두 줄이 "단일 배포"의 다운타임 구간이다 (docker stop && docker run)
docker stop -t 20 app >/dev/null 2>&1 || true
docker rm -f app >/dev/null 2>&1 || true
docker run -d --name app --restart unless-stopped -p 3000:3000 \
  -e DB_HOST="$(p db-host)" -e DB_PORT=3306 \
  -e DB_USER="$(p db-user)" -e DB_PASSWORD="$(p db-password)" \
  -e DB_NAME="$(p db-name)" -e PORT=3000 \
  -e SPRING_JPA_HIBERNATE_DDL_AUTO="$(p ddl-auto 2>/dev/null || echo validate)" \
  -e JWT_SECRET="$(p jwt-secret)" -e JWT_ACCESS_EXPIRATION=3600 \
  "$IMAGE"

# 안 쓰는 옛 이미지를 정리해 t4g.micro 디스크가 차지 않게 한다
docker image prune -af >/dev/null 2>&1 || true
SWAP
chmod +x /opt/umc/swap.sh

# 2. 부팅 때 한 번 실행
/opt/umc/swap.sh

# 3. 관측 수집기 (Alloy) — 2주차
#    SSM 값을 환경변수로 올리고 → remotecfg 설정 파일을 쓰고 → Alloy 를 띄운다.
#    수집 내용(host/mysql/app)은 Fleet Management 파이프라인에서 받아온다.
REGION=__REGION__
p() { aws ssm get-parameter --region $REGION --name "/umc/app/$1" --with-decryption \
        --query Parameter.Value --output text; }
export GC_FLEET_URL=$(p gc-fleet-url)
export GC_FLEET_USER=$(p gc-fleet-user)
export GC_TOKEN=$(p gc-token)
export GCLOUD_RW_API_KEY="$GC_TOKEN"   # Grafana 기본 self-monitoring 파이프라인이 쓰는 이름
export GC_PROM_URL=$(p gc-prom-url)
export GC_PROM_USER=$(p gc-prom-user)
export MYSQL_DSN=$(p mysql-dsn)
export APP_METRICS_PATH=/actuator/prometheus   # Spring 은 /metrics 가 아니다
export APP_METRICS_ADDR=127.0.0.1:3000

mkdir -p /opt/alloy /var/lib/alloy
cat > /opt/alloy/config.alloy <<'ALLOY'
logging { level = "info" }

remotecfg {
  url = sys.env("GC_FLEET_URL")
  basic_auth {
    username = sys.env("GC_FLEET_USER")
    password = sys.env("GC_TOKEN")
  }
  id             = constants.hostname
  poll_frequency = "5m"
}
ALLOY

docker rm -f alloy >/dev/null 2>&1 || true
docker run -d --name alloy --restart unless-stopped \
  --network host --pid host \
  -v /:/rootfs:ro -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /opt/alloy/config.alloy:/etc/alloy/config.alloy:ro \
  -v /var/lib/alloy:/var/lib/alloy \
  -e GC_FLEET_URL -e GC_FLEET_USER -e GC_TOKEN \
  -e GC_PROM_URL -e GC_PROM_USER -e MYSQL_DSN \
  -e GCLOUD_RW_API_KEY -e APP_METRICS_PATH -e APP_METRICS_ADDR \
  grafana/alloy:v1.20.1 run --storage.path=/var/lib/alloy /etc/alloy/config.alloy
