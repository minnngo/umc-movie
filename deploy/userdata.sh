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

# 3. Alloy Config
# 2주차 워크북에서 추가
