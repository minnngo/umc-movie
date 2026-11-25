#!/usr/bin/env bash
# 실습이 끝나면 과금되는 자원을 지웁니다 (ALB · EC2 는 켜두면 시간당 과금).
# RDS 는 건드리지 않습니다. ECR 이미지 · SSM 파라미터 · IAM 은 묻고 지웁니다.
cd "$(dirname "$0")/.."
source deploy/env.sh

read -rp "ASG · ALB · 타겟 그룹 · 인스턴스 · 시작 템플릿 · SG 를 삭제합니다. 계속할까요? [y/N] " yn
[ "$yn" = y ] || [ "$yn" = Y ] || exit 0

say "ASG 삭제 (인스턴스 함께 종료)"
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --force-delete 2>/dev/null || true
SINGLE=$(aws ec2 describe-instances --filters Name=tag:Name,Values="$SINGLE_NAME" \
  Name=instance-state-name,Values=pending,running,stopped --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$SINGLE" ] && aws ec2 terminate-instances --instance-ids $SINGLE >/dev/null

say "ALB · 타겟 그룹 삭제"
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != None ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
fi
TG=$(aws elbv2 describe-target-groups --names "$TG_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
# ALB 가 지워진 직후엔 리스너 참조가 잠깐 남아 있어 몇 번 재시도합니다
if [ -n "$TG" ] && [ "$TG" != None ]; then
  for _ in 1 2 3 4 5 6; do aws elbv2 delete-target-group --target-group-arn "$TG" 2>/dev/null && break; sleep 10; done
fi

say "인스턴스 종료 대기"
IDS=$(aws ec2 describe-instances --filters Name=instance.group-name,Values="$APP_SG_NAME" \
  Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$IDS" ] && aws ec2 wait instance-terminated --instance-ids $IDS

aws ec2 delete-launch-template --launch-template-name "$LT_NAME" >/dev/null 2>&1 || true

say "보안 그룹 삭제 (RDS SG 에 걸린 참조를 먼저 지워야 할 수 있습니다)"
APP_SG=$(sg_id "$APP_SG_NAME"); ALB_SG=$(sg_id "$ALB_SG_NAME")
[ "$APP_SG" != None ] && { aws ec2 delete-security-group --group-id "$APP_SG" || echo "  $APP_SG 삭제 실패 — RDS SG 의 3306 인바운드(소스 $APP_SG)를 먼저 지우세요"; }
sleep 5
[ "$ALB_SG" != None ] && { aws ec2 delete-security-group --group-id "$ALB_SG" || true; }

read -rp "ECR 저장소 · SSM 파라미터 · IAM 역할도 지울까요? [y/N] " yn
if [ "$yn" = y ] || [ "$yn" = Y ]; then
  aws ecr delete-repository --repository-name "$ECR_REPO" --force >/dev/null 2>&1 || true
  for n in image db-host db-user db-name db-password jwt-secret ddl-auto; do
    aws ssm delete-parameter --name "/umc/app/$n" 2>/dev/null || true
  done
  aws iam remove-role-from-instance-profile --instance-profile-name "$ROLE" --role-name "$ROLE" 2>/dev/null || true
  aws iam delete-instance-profile --instance-profile-name "$ROLE" 2>/dev/null || true
  aws iam delete-role-policy --role-name "$ROLE" --policy-name umc-ssm-params 2>/dev/null || true
  for p in AmazonEC2ContainerRegistryReadOnly AmazonSSMManagedInstanceCore; do
    aws iam detach-role-policy --role-name "$ROLE" --policy-arn "arn:aws:iam::aws:policy/$p" 2>/dev/null || true
  done
  aws iam delete-role --role-name "$ROLE" 2>/dev/null || true
fi
say "정리 완료"
