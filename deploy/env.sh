# 모든 배포 스크립트가 공통으로 읽는 설정입니다. 직접 실행하지 말고 다른 스크립트가 source 합니다.
set -euo pipefail

export AWS_REGION=${AWS_REGION:-ap-southeast-2}
export AWS_DEFAULT_REGION=$AWS_REGION
export AWS_PAGER=""

ECR_REPO=umc-app
APP_SG_NAME=umc-app-sg
ALB_SG_NAME=umc-alb-sg
LT_NAME=umc-app-lt
TG_NAME=umc-app-tg
ALB_NAME=umc-alb
ASG_NAME=umc-asg
ROLE=umc-app-instance
SINGLE_NAME=umc-single     # "before" 측정용 단일 인스턴스의 Name 태그
APP_PORT=3000

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text)

say() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }

# 이름으로 SG ID 찾기 (없으면 None)
sg_id() {
  aws ec2 describe-security-groups \
    --filters Name=group-name,Values="$1" Name=vpc-id,Values="$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' --output text
}

ecr_uri() {
  aws ecr describe-repositories --repository-names "$ECR_REPO" \
    --query 'repositories[0].repositoryUri' --output text
}

# 3.8 이미지 태깅 정책: version-yy-mm-dd-N  (예: v0.0.1-26-11-18-1)
next_tag() {
  local ver day n
  ver=v$(sed -nE "s/^version = '([0-9.]+).*'/\1/p" build.gradle)
  day=$(date +%y-%m-%d)
  n=$(aws ecr list-images --repository-name "$ECR_REPO" --filter tagStatus=TAGGED \
        --query "length(imageIds[?starts_with(imageTag, '${ver}-${day}-')])" --output text)
  echo "${ver}-${day}-$((n + 1))"
}

# 이미지를 빌드해 ECR 에 올리고, 전체 이미지 주소를 stdout 으로 돌려줍니다
build_push() {
  local uri tag
  uri=$(ecr_uri)
  tag=$(next_tag)
  aws ecr get-login-password | docker login --username AWS --password-stdin "${uri%%/*}" >&2
  docker build --platform linux/arm64 -t "${uri}:${tag}" . >&2
  docker push "${uri}:${tag}" >&2
  echo "${uri}:${tag}"
}

# 인스턴스에서 swap.sh 를 실행하고 끝날 때까지 기다립니다. 실패하면 로그를 보여주고 1 을 돌려줍니다
run_swap() {
  local id=$1 cid st
  cid=$(aws ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
          --parameters 'commands=["bash /opt/umc/swap.sh"]' \
          --query Command.CommandId --output text)
  sleep 2
  # aws ssm wait 는 100초가 상한이라 직접 돕니다
  while :; do
    st=$(aws ssm list-command-invocations --command-id "$cid" \
           --query 'CommandInvocations[0].Status' --output text)
    case "$st" in Pending|InProgress|Delayed|None) sleep 5 ;; *) break ;; esac
  done
  if [ "$st" != "Success" ]; then
    echo "교체 실패($st)." >&2
    aws ssm list-command-invocations --command-id "$cid" --details \
      --query 'CommandInvocations[0].CommandPlugins[0].Output' --output text | tail -20 >&2
    return 1
  fi
}
