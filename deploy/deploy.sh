#!/usr/bin/env bash
# 워크북 3.7 — Rolling 무중단 배포. 로컬(AWS CLI 가 되는 곳)에서 실행합니다.
cd "$(dirname "$0")/.."
source deploy/env.sh

TG=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
       --query 'TargetGroups[0].TargetGroupArn' --output text)

# 1. 이미지 (태그: version-yy-mm-dd-N)
say "1. 이미지 빌드 & 푸시"
IMAGE=$(build_push)
echo "$IMAGE"

# 2. 앞으로 "새로 뜨는" 인스턴스가 읽을 태그
aws ssm put-parameter --name /umc/app/image --type String --value "$IMAGE" --overwrite >/dev/null

# 3. "지금 떠 있는" 인스턴스를 한 대씩 교체
# InService 만 고릅니다 — Terminating 인 인스턴스를 교체하려 들면 거기서 멈춥니다
START=$(date +%s)
for ID in $(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
              --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
              --output text); do
  say "── $ID"

  # 트래픽을 끊는다. 처리 중이던 요청은 deregistration_delay(30초) 만큼 기다려 준다
  echo "  deregister → draining"
  aws elbv2 deregister-targets --target-group-arn "$TG" --targets Id="$ID"
  aws elbv2 wait target-deregistered --target-group-arn "$TG" --targets Id="$ID"

  # 컨테이너 교체. 실패하면 다음 대로 넘어가지 않고 멈춘다
  echo "  swap.sh"
  if ! run_swap "$ID"; then
    echo "이 인스턴스($ID)는 타겟에서 빠진 채로 남아 있습니다. 고친 뒤 register-targets 하세요."
    exit 1
  fi

  # 다시 트래픽을 받는다. 정상이 될 때까지 기다린 뒤에야 다음 대로 넘어간다
  echo "  register → healthy 대기"
  aws elbv2 register-targets --target-group-arn "$TG" --targets Id="$ID"
  aws elbv2 wait target-in-service --target-group-arn "$TG" --targets Id="$ID"
  echo "  ✓ in service"
done
say "무중단 배포 완료 ($(( $(date +%s) - START ))초) — $IMAGE"
