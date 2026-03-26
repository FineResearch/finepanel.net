#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-784064929014}"
ECS_CLUSTER="${ECS_CLUSTER:-ECSCluster-production}"
ECR_REPO="${ECR_REPO:-production/finepanel}"

API_SERVICE="Api-ECSService-production-4"
SIDEKIQ_SERVICE="Sidekiq-ECSService-production-4"

API_TASKDEF_FILE="taskdef-api-new.json"
SIDEKIQ_TASKDEF_FILE="taskdef-sidekiq-new.json"

API_CONTAINER="api"
SIDEKIQ_CONTAINER="sidekiq"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
IMAGE_TAG="${IMAGE_TAG:-deploy-${TIMESTAMP}}"
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"

echo "================================================"
echo "FINEPANEL ECS DEPLOY"
echo "Cluster: ${ECS_CLUSTER}"
echo "Image  : ${IMAGE_URI}"
echo "Repo   : $(pwd)"
echo "================================================"

echo
echo "[0/9] Git status"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
UPSTREAM_BRANCH="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

echo "Current branch : ${CURRENT_BRANCH:-unknown}"
echo "Upstream       : ${UPSTREAM_BRANCH:-none}"

if [[ -n "${CURRENT_BRANCH}" ]]; then
  if [[ -n "${UPSTREAM_BRANCH}" ]]; then
    echo "Running git pull on ${UPSTREAM_BRANCH}..."
    git pull --ff-only
  else
    echo "WARNING: branch '${CURRENT_BRANCH}' has no upstream configured."
    echo "Skipping git pull."
    echo "To configure it manually, run something like:"
    echo "  git branch --set-upstream-to=origin/${CURRENT_BRANCH} ${CURRENT_BRANCH}"
  fi
else
  echo "WARNING: could not detect git branch. Skipping git pull."
fi

echo
echo "[1/9] Login ECR"
aws ecr get-login-password --region "${AWS_REGION}" \
| docker login --username AWS --password-stdin \
"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo
echo "[2/9] Build Docker image"
docker build -f Dockerfile.release -t "${IMAGE_URI}" .

echo
echo "[3/9] Push Docker image"
docker push "${IMAGE_URI}"

update_taskdef () {
  local TASKDEF_FILE="$1"
  local CONTAINER_NAME="$2"

  cp "${TASKDEF_FILE}" "${TASKDEF_FILE}.bak.${TIMESTAMP}"

  export TASKDEF_FILE CONTAINER_NAME IMAGE_URI

  python3 << 'PY'
import json
import os

file = os.environ["TASKDEF_FILE"]
container = os.environ["CONTAINER_NAME"]
image = os.environ["IMAGE_URI"]

with open(file) as f:
    data = json.load(f)

updated = False
for c in data["containerDefinitions"]:
    if c["name"] == container:
        c["image"] = image
        updated = True

if not updated:
    raise SystemExit(f"Container '{container}' not found in {file}")

with open(file, "w") as f:
    json.dump(data, f, indent=2)

print(f"Updated {file} -> {image}")
PY
}

echo
echo "[4/9] Update task definitions"
update_taskdef "${API_TASKDEF_FILE}" "${API_CONTAINER}"
update_taskdef "${SIDEKIQ_TASKDEF_FILE}" "${SIDEKIQ_CONTAINER}"

echo
echo "[5/9] Register API task definition"
API_TASKDEF_ARN="$(aws ecs register-task-definition \
  --cli-input-json "file://${API_TASKDEF_FILE}" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text \
  --no-cli-pager)"

echo "API task definition ARN: ${API_TASKDEF_ARN}"

echo
echo "[6/9] Register Sidekiq task definition"
SIDEKIQ_TASKDEF_ARN="$(aws ecs register-task-definition \
  --cli-input-json "file://${SIDEKIQ_TASKDEF_FILE}" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text \
  --no-cli-pager)"

echo "Sidekiq task definition ARN: ${SIDEKIQ_TASKDEF_ARN}"

echo
echo "[7/9] Update ECS services with new task definitions"
aws ecs update-service \
  --cluster "${ECS_CLUSTER}" \
  --service "${API_SERVICE}" \
  --task-definition "${API_TASKDEF_ARN}" \
  --force-new-deployment \
  --no-cli-pager > "/tmp/update-api-${TIMESTAMP}.json"

aws ecs update-service \
  --cluster "${ECS_CLUSTER}" \
  --service "${SIDEKIQ_SERVICE}" \
  --task-definition "${SIDEKIQ_TASKDEF_ARN}" \
  --force-new-deployment \
  --no-cli-pager > "/tmp/update-sidekiq-${TIMESTAMP}.json"

echo
echo "[8/9] Waiting services to stabilize..."
aws ecs wait services-stable \
  --cluster "${ECS_CLUSTER}" \
  --services "${API_SERVICE}"

aws ecs wait services-stable \
  --cluster "${ECS_CLUSTER}" \
  --services "${SIDEKIQ_SERVICE}"

echo
echo "[9/9] Show running ECS-related containers"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep ecs || true

echo
echo "================================================"
echo "DEPLOY COMPLETE"
echo "Image deployed: ${IMAGE_URI}"
echo "API taskdef   : ${API_TASKDEF_ARN}"
echo "Sidekiq taskdef: ${SIDEKIQ_TASKDEF_ARN}"
echo "================================================"
