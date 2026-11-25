#!/usr/bin/env bash
# 워크북 1.1 "before" 용 — EC2 한 대에 직접 붙는 기존 구조를 만듭니다.
# (10주차에 만든 EC2 가 이미 있고 그걸로 잴 거라면 이 스크립트는 건너뛰어도 됩니다)
cd "$(dirname "$0")/.."
source deploy/env.sh

ID=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values="$SINGLE_NAME" Name=instance-state-name,Values=pending,running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

if [ "$ID" = None ]; then
  say "단일 인스턴스 생성"
  ID=$(aws ec2 run-instances --launch-template "LaunchTemplateName=$LT_NAME,Version=\$Latest" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$SINGLE_NAME}]" \
    --query 'Instances[0].InstanceId' --output text)
fi
aws ec2 wait instance-running --instance-ids "$ID"
IP=$(aws ec2 describe-instances --instance-ids "$ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

say "$ID ($IP) 에서 앱이 뜨기를 기다립니다 (보통 2~4분)"
for _ in $(seq 1 60); do
  if curl -fsS -m 3 "http://$IP:$APP_PORT/health" >/dev/null 2>&1; then
    echo "OK  http://$IP:$APP_PORT/health"
    echo
    echo "측정 대상 URL (lab 에 넣을 값):"
    echo "  http://$IP:$APP_PORT"
    say "다음: lab 측정을 시작하고 30초 뒤  bash deploy/single-deploy.sh"
    exit 0
  fi
  printf '.'; sleep 5
done
echo
echo "5분 안에 /health 가 응답하지 않았습니다. 부팅 로그를 확인하세요:"
echo "  aws ssm start-session --target $ID   →   sudo tail -50 /var/log/umc-boot.log ; sudo docker logs app"
exit 1
