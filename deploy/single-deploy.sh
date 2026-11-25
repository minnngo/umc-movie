#!/usr/bin/env bash
# "단일 배포" — 한 대뿐인 서버에서 docker stop && docker run. 이 사이에 요청이 끊깁니다.
cd "$(dirname "$0")/.."
source deploy/env.sh

ID=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values="$SINGLE_NAME" Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
[ "$ID" = None ] && { echo "$SINGLE_NAME 인스턴스가 없습니다. 02-single-ec2.sh 를 먼저 실행하세요."; exit 1; }

say "1. 이미지 빌드 & 푸시"
IMAGE=$(build_push)
aws ssm put-parameter --name /umc/app/image --type String --overwrite --value "$IMAGE" >/dev/null
echo "$IMAGE"

say "2. $ID 컨테이너 교체 (트래픽을 빼지 않고 바로)"
START=$(date +%s)
run_swap "$ID"
say "배포 완료 ($(( $(date +%s) - START ))초). lab 화면에서 순단을 확인하세요."
