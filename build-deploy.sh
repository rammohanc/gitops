#!/bin/sh
set -o errexit

export APP_NAME="${1:-spring-petclinic}"
export APP_IMAGE_REVISION="${2:-v1.0}"
export APP_GIT_URL="${3:-https://github.com/rammohanc/spring-petclinic.git}"
export APP_IMAGE_TAG="${4:-harbor.run.haas-222.pez.pivotal.io/tbs/spring-petclinic}"
export APP_GITOPS_URL="${5:-https://github.com/rammohanc/gitops.git}"
export APP_IMAGE_REVISION_NO_PERIOD="$(echo "${APP_IMAGE_REVISION//./}")" 

ytt -f templates/build --data-value-yaml metadata_name=${APP_NAME} --data-value-yaml git_revision=$APP_IMAGE_REVISION --data-value-yaml git_url=$APP_GIT_URL --data-value-yaml tag=${APP_IMAGE_TAG} -o yaml > tbs/spring-petclinic-image.yaml


#ytt -f templates/deploy --data-value-yaml ksvc_metadata_name=${APP_NAME}-${APP_IMAGE_REVISION_NO_PERIOD} --data-value-yaml tag=${APP_IMAGE_TAG}:${APP_IMAGE_REVISION} -o yaml > ksvc/spring-petclinic-serverless.yaml


git add .
git commit -m "build and deploy $APP_NAME $APP_IMAGE_REVISION"
#git tag $APP_IMAGE_REVISION
git push

argocd app create spring-petclinic-tbs-image --upsert --sync-policy auto --repo $APP_GITOPS_URL --path tbs --dest-server https://kubernetes.default.svc --dest-namespace tbs

#install jq
sleep 240
TEST_READINESS=`kubectl get images.kpack.io ${APP_NAME} -o json | jq -r '.status.conditions[] | select(.type=="Ready") | .status'`
while [ ! $TEST_READINESS = "True" ]; do
    echo $(kubectl get images.kpack.io ${APP_NAME} -o json | jq -r '.status.conditions[] | select(.type=="Ready") | .message')
    sleep 60
    TEST_READINESS=`kubectl get images.kpack.io ${APP_NAME} -o json | jq -r '.status.conditions[] | select(.type=="Ready") | .status'`
done

echo "Image built.."
echo "Deploying image .."

#argocd app create spring-petclinic-serverless --upsert --sync-policy auto --repo $APP_GITOPS_URL --revision $APP_IMAGE_REVISION  --path ksvc --dest-server https://kubernetes.default.svc --dest-namespace tbs


export APP_IMAGE_DIGEST="$(kubectl get images.kpack.io $APP_NAME -o json | jq -r '.status.latestImage')"

ytt -f templates/deploy --data-value-yaml ksvc_metadata_name=${APP_NAME} --data-value-yaml tag=${APP_IMAGE_DIGEST} -o yaml > ksvc/spring-petclinic-serverless.yaml
#ytt -f deploy.yaml --data-value-yaml APP_NAME=$APP_NAME --data-value-yaml APP_IMAGE_DIGEST="$(kubectl get images.kpack.io $APP_NAME -o json | jq -r '.status.latestImage')" -o yaml > app-deploy/deploy.yaml

git add .
git commit -m "update $APP_NAME $APP_IMAGE_REVISION"
git push


argocd app create spring-petclinic-serverless --upsert --sync-policy auto --repo $APP_GITOPS_URL  --path ksvc --dest-server https://kubernetes.default.svc --dest-namespace tbs
