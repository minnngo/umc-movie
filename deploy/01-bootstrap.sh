#!/usr/bin/env bash
# 워크북 3.3 · 3.4 · 3.8 — ECR, 첫 이미지, SSM 파라미터, IAM, 앱 SG, 시작 템플릿
# 여러 번 실행해도 안전합니다 (이미 있는 자원은 건너뜁니다).
cd "$(dirname "$0")/.."
source deploy/env.sh

say "계정 $ACCOUNT · 리전 $AWS_REGION · VPC $VPC_ID"

# ── 1. ECR 저장소 + 수명 주기 정책 (3.8: untagged 7일 만료, tagged 최근 10개 유지)
if ! aws ecr describe-repositories --repository-names "$ECR_REPO" >/dev/null 2>&1; then
  say "ECR 저장소 $ECR_REPO 생성"
  aws ecr create-repository --repository-name "$ECR_REPO" >/dev/null
fi
aws ecr put-lifecycle-policy --repository-name "$ECR_REPO" --lifecycle-policy-text '{
  "rules": [
    {"rulePriority": 1, "description": "untagged 7일 만료",
     "selection": {"tagStatus": "untagged", "countType": "sinceImagePushed", "countUnit": "days", "countNumber": 7},
     "action": {"type": "expire"}},
    {"rulePriority": 2, "description": "tagged 최근 10개 유지",
     "selection": {"tagStatus": "tagged", "tagPatternList": ["v*"], "countType": "imageCountMoreThan", "countNumber": 10},
     "action": {"type": "expire"}}
  ]}' >/dev/null

# ── 2. 첫 이미지 빌드 & 푸시
say "이미지 빌드 & 푸시 (linux/arm64)"
IMAGE=$(build_push)
aws ssm put-parameter --name /umc/app/image --type String --overwrite --value "$IMAGE" >/dev/null
echo "/umc/app/image = $IMAGE"

# ── 3. SSM 파라미터. 비밀값은 화면에 보이지 않게 입력받습니다. 이미 있으면 Enter 로 유지.
ask() { # ask <name> <String|SecureString> <설명> [기본값]
  local name=$1 type=$2 desc=$3 def=${4:-} cur val
  cur=$(aws ssm get-parameter --name "/umc/app/$name" --query Parameter.Name --output text 2>/dev/null || true)
  local hint=""; [ -n "$cur" ] && hint=" (Enter=기존 값 유지)"; [ -z "$cur" ] && [ -n "$def" ] && hint=" (Enter=$def)"
  if [ "$type" = SecureString ]; then read -rsp "  $desc$hint: " val; echo; else read -rp "  $desc$hint: " val; fi
  [ -z "$val" ] && [ -n "$cur" ] && return 0
  [ -z "$val" ] && val=$def
  [ -z "$val" ] && { echo "  값이 필요합니다."; ask "$@"; return; }
  aws ssm put-parameter --name "/umc/app/$name" --type "$type" --overwrite --value "$val" >/dev/null
}
if [ -z "${SKIP_PARAMS:-}" ]; then   # SKIP_PARAMS=1 이면 이미 넣어둔 파라미터를 그대로 씁니다
  say "SSM 파라미터 입력 (RDS 정보)"
  ask db-host     String       "RDS 엔드포인트 (xxx.rds.amazonaws.com)"
  ask db-user     String       "DB 사용자" admin
  ask db-name     String       "DB 이름" umc_movie
  ask db-password SecureString "DB 비밀번호"
  ask ddl-auto    String       "JPA ddl-auto (RDS 에 테이블이 이미 있으면 validate, 비어 있으면 update)" validate
  read -rp "  JWT 시크릿을 새로 무작위 생성할까요? [Y/n] " yn
  if [ "${yn:-Y}" != n ] && [ "${yn:-Y}" != N ]; then
    aws ssm put-parameter --name /umc/app/jwt-secret --type SecureString --overwrite \
      --value "$(openssl rand -base64 48)" >/dev/null
  else
    ask jwt-secret SecureString "JWT 시크릿 (32자 이상)"
  fi
fi
echo "파라미터 개수: $(aws ssm get-parameters-by-path --path /umc/app --query 'length(Parameters)')"

# ── 4. IAM 역할 + 인스턴스 프로파일
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  say "IAM 역할 $ROLE 생성"
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
  aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name umc-ssm-params --policy-document "{
  \"Version\": \"2012-10-17\", \"Statement\": [
    {\"Effect\": \"Allow\", \"Action\": [\"ssm:GetParameter\", \"ssm:GetParameters\"],
     \"Resource\": \"arn:aws:ssm:${AWS_REGION}:${ACCOUNT}:parameter/umc/app/*\"},
    {\"Effect\": \"Allow\", \"Action\": \"kms:Decrypt\", \"Resource\": \"*\",
     \"Condition\": {\"StringEquals\": {\"kms:ViaService\": \"ssm.${AWS_REGION}.amazonaws.com\"}}}
  ]}"
if ! aws iam get-instance-profile --instance-profile-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$ROLE" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$ROLE" --role-name "$ROLE"
  echo "인스턴스 프로파일 전파 대기 (15초)"; sleep 15
fi

# ── 5. 앱 SG. "before" 측정 동안은 인터넷에서 3000 으로 직접 들어옵니다 (03 에서 ALB 로 제한)
APP_SG=$(sg_id "$APP_SG_NAME")
if [ "$APP_SG" = None ]; then
  say "앱 보안 그룹 $APP_SG_NAME 생성"
  APP_SG=$(aws ec2 create-security-group --group-name "$APP_SG_NAME" \
    --description "UMC app instances" --vpc-id "$VPC_ID" --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$APP_SG" \
    --protocol tcp --port "$APP_PORT" --cidr 0.0.0.0/0 >/dev/null
fi
echo "APP_SG = $APP_SG"

# RDS 가 앱 인스턴스의 3306 접속을 받도록 (RDS 에 붙은 SG ID 를 입력)
[ -z "${RDS_SG+x}" ] && read -rp "  RDS 에 붙어 있는 보안 그룹 ID (sg-..., 건너뛰려면 Enter): " RDS_SG
if [ -n "$RDS_SG" ]; then
  aws ec2 authorize-security-group-ingress --group-id "$RDS_SG" \
    --protocol tcp --port 3306 --source-group "$APP_SG" >/dev/null 2>&1 \
    && echo "  $RDS_SG ← 3306 from $APP_SG 허용" || echo "  (이미 허용돼 있음)"
fi

# ── 6. 시작 템플릿
say "시작 템플릿 $LT_NAME"
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  --query Parameter.Value --output text)
B64=$(sed "s/__REGION__/$AWS_REGION/" deploy/userdata.sh | base64 | tr -d '\n')
LT_DATA=$(cat <<JSON
{
  "ImageId": "$AMI",
  "InstanceType": "t4g.micro",
  "IamInstanceProfile": { "Name": "$ROLE" },
  "NetworkInterfaces": [{ "DeviceIndex": 0, "AssociatePublicIpAddress": true,
                          "Groups": ["$APP_SG"], "DeleteOnTermination": true }],
  "UserData": "$B64"
}
JSON
)
if aws ec2 describe-launch-templates --launch-template-names "$LT_NAME" >/dev/null 2>&1; then
  aws ec2 create-launch-template-version --launch-template-name "$LT_NAME" \
    --launch-template-data "$LT_DATA" --query 'LaunchTemplateVersion.VersionNumber' --output text
else
  aws ec2 create-launch-template --launch-template-name "$LT_NAME" \
    --launch-template-data "$LT_DATA" --query 'LaunchTemplate.LatestVersionNumber' --output text
fi

say "완료. 다음: bash deploy/02-single-ec2.sh"
