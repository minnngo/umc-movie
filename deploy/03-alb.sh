#!/usr/bin/env bash
# 워크북 3.2 · 3.5 · 3.6 — ALB SG, 앱 SG 를 ALB 로 제한, 타겟 그룹, ALB, 리스너, ASG
cd "$(dirname "$0")/.."
source deploy/env.sh

APP_SG=$(sg_id "$APP_SG_NAME")
[ "$APP_SG" = None ] && { echo "01-bootstrap.sh 를 먼저 실행하세요."; exit 1; }

# ── 3.2 ALB 보안 그룹
ALB_SG=$(sg_id "$ALB_SG_NAME")
if [ "$ALB_SG" = None ]; then
  say "ALB 보안 그룹 $ALB_SG_NAME 생성"
  ALB_SG=$(aws ec2 create-security-group --group-name "$ALB_SG_NAME" \
    --description "ALB inbound from internet" --vpc-id "$VPC_ID" --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 80  --cidr 0.0.0.0/0 >/dev/null
  aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 443 --cidr 0.0.0.0/0 >/dev/null
fi
say "앱 SG: ALB → $APP_PORT 허용, 인터넷 → $APP_PORT 제거"
aws ec2 authorize-security-group-ingress --group-id "$APP_SG" \
  --protocol tcp --port "$APP_PORT" --source-group "$ALB_SG" >/dev/null 2>&1 || true
aws ec2 revoke-security-group-ingress --group-id "$APP_SG" \
  --protocol tcp --port "$APP_PORT" --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
aws ec2 describe-security-groups --group-ids "$APP_SG" \
  --query 'SecurityGroups[0].IpPermissions[].{port:FromPort,from:UserIdGroupPairs[0].GroupId,cidr:IpRanges[0].CidrIp}' --output table

# ── 3.5 서브넷 · 타겟 그룹 · ALB · 리스너
SUBS=($(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
          --query 'Subnets[0:3].SubnetId' --output text))
echo "subnets: ${SUBS[*]}"

TG=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
       --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
if [ -z "$TG" ] || [ "$TG" = None ]; then
  say "타겟 그룹 $TG_NAME 생성"
  TG=$(aws elbv2 create-target-group --name "$TG_NAME" \
    --protocol HTTP --port "$APP_PORT" --vpc-id "$VPC_ID" --target-type instance \
    --health-check-protocol HTTP --health-check-path /health \
    --health-check-interval-seconds 10 --healthy-threshold-count 2 --unhealthy-threshold-count 2 \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
fi
aws elbv2 modify-target-group-attributes --target-group-arn "$TG" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=30 >/dev/null

ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
            --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = None ]; then
  say "ALB $ALB_NAME 생성 (활성까지 2~3분)"
  ALB_ARN=$(aws elbv2 create-load-balancer --name "$ALB_NAME" \
    --type application --scheme internet-facing \
    --subnets "${SUBS[@]}" --security-groups "$ALB_SG" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)
fi
aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"

if [ "$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query 'length(Listeners)')" = 0 ]; then
  aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG" >/dev/null
fi

# ── "before" 측정용 단일 인스턴스는 이제 필요 없습니다
SINGLE=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values="$SINGLE_NAME" Name=instance-state-name,Values=pending,running,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$SINGLE" ]; then
  say "단일 인스턴스 종료: $SINGLE"
  aws ec2 terminate-instances --instance-ids $SINGLE >/dev/null
fi

# ── 3.6 Auto Scaling 그룹
if [ "$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
        --query 'length(AutoScalingGroups)')" = 0 ]; then
  say "ASG $ASG_NAME 생성 (2대)"
  aws autoscaling create-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" \
    --launch-template "LaunchTemplateName=$LT_NAME,Version=\$Latest" \
    --min-size 2 --max-size 4 --desired-capacity 2 \
    --vpc-zone-identifier "$(IFS=,; echo "${SUBS[*]}")" \
    --target-group-arns "$TG" \
    --health-check-type EC2 --health-check-grace-period 180
fi

say "타겟 2대가 healthy 가 되기를 기다립니다 (3~5분)"
for _ in $(seq 1 60); do
  N=$(aws elbv2 describe-target-health --target-group-arn "$TG" \
        --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])")
  printf '\r  healthy: %s/2 ' "$N"
  [ "$N" -ge 2 ] && break
  sleep 10
done
echo

ALB=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --query 'LoadBalancers[0].DNSName' --output text)
curl -fsS -m 5 "http://$ALB/health" && echo
echo
echo "측정 대상 URL (lab 에 넣을 값):"
echo "  http://$ALB"
say "다음: lab 측정을 시작하고 30초 뒤  bash deploy/deploy.sh"
