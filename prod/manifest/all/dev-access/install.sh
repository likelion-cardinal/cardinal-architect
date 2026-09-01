#!/bin/bash
# 개발팀 DB 접속 준비 — CP 에서 root 로 1회 실행.
#
# 로컬 리포에 있는 파일이지만 CP 에는 리포가 없으므로, 이 파일 내용을 통째로
# 복사해 SSM 세션에 붙여넣는 방식으로 쓴다(그래서 rbac.yaml 을 안에 품고 있다).
#
#   aws ssm start-session --target i-035eaeb1fe3cd3330
#   sudo -i
#   (여기에 붙여넣기)
#
# 하는 일: RBAC 배포 → devops 계정 생성 → 제한 kubeconfig 작성 → 검증
# 여러 번 실행해도 안전하다(이미 있으면 건너뛴다).
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
export PATH="$PATH:/usr/local/bin:/usr/bin"

APISERVER="https://10.20.10.10:6443"
DEV_USER="devops"

echo "── 1/4 RBAC 배포 ─────────────────────────────────"
kubectl apply -f - <<'RBAC'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dev
  namespace: database
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dev-db-access
  namespace: database
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["pods/portforward"]
    verbs: ["create"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-db-access
  namespace: database
subjects:
  - kind: ServiceAccount
    name: dev
    namespace: database
roleRef:
  kind: Role
  name: dev-db-access
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Secret
metadata:
  name: dev-token
  namespace: database
  annotations:
    kubernetes.io/service-account.name: dev
type: kubernetes.io/service-account-token
---
# default 네임스페이스: 로그 읽기 전용. exec 은 주지 않는다 — backend 파드가
# app-secret 을 envFrom 으로 통째로 받아서, 컨테이너 안에서 env 한 번이면
# JWT·DB·카카오·R2 자격증명이 전부 보인다.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dev-log-read
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-log-read
  namespace: default
subjects:
  - kind: ServiceAccount
    name: dev
    namespace: database
roleRef:
  kind: Role
  name: dev-log-read
  apiGroup: rbac.authorization.k8s.io
RBAC

echo "── 2/4 ${DEV_USER} 계정 ──────────────────────────"
if id "$DEV_USER" >/dev/null 2>&1; then
  echo "   이미 있음 — 건너뜀"
else
  useradd -m -s /bin/bash "$DEV_USER"
  echo "   생성함"
fi
# sudo 가 붙어 있으면 이 설계 전체가 무의미하다. 명시적으로 확인만 한다.
if [ -f "/etc/sudoers.d/$DEV_USER" ]; then
  echo "   !! /etc/sudoers.d/$DEV_USER 가 있다. 지워야 한다."
fi

echo "── 3/4 kubeconfig ────────────────────────────────"
# 토큰 컨트롤러가 Secret 을 채우는 데 잠깐 걸린다.
TOKEN=""
for _ in $(seq 1 30); do
  TOKEN=$(kubectl -n database get secret dev-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
  [ -n "$TOKEN" ] && break
  sleep 1
done
if [ -z "$TOKEN" ]; then
  echo "   실패: dev-token Secret 에 토큰이 안 채워졌다."
  echo "   확인: kubectl -n database describe secret dev-token"
  exit 1
fi
CA=$(kubectl -n database get secret dev-token -o jsonpath='{.data.ca\.crt}')

install -d -o "$DEV_USER" -g "$DEV_USER" -m 700 "/home/$DEV_USER/.kube"
cat > "/home/$DEV_USER/.kube/config" <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - name: cardinal
    cluster:
      server: ${APISERVER}
      certificate-authority-data: ${CA}
users:
  - name: dev
    user:
      token: ${TOKEN}
contexts:
  - name: dev
    context:
      cluster: cardinal
      user: dev
      namespace: database
current-context: dev
KUBECONFIG
chown "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.kube/config"
chmod 600 "/home/$DEV_USER/.kube/config"
echo "   작성함 (/home/$DEV_USER/.kube/config)"

echo "── 4/4 검증 ──────────────────────────────────────"
check() { # 설명, 기대(ok|deny), 명령...
  local desc="$1" expect="$2"; shift 2
  if "$@" >/dev/null 2>&1; then got=ok; else got=deny; fi
  if [ "$got" = "$expect" ]; then echo "   PASS  $desc"; else echo "   FAIL  $desc (기대=$expect 결과=$got)"; fi
}
check "database 파드 조회 가능"    ok   sudo -iu "$DEV_USER" kubectl get pods
check "backend 로그 조회 가능"     ok   sudo -iu "$DEV_USER" kubectl -n default logs --tail=1 deploy/backend
check "secret 조회 차단(database)" deny sudo -iu "$DEV_USER" kubectl get secrets
check "secret 조회 차단(default)"  deny sudo -iu "$DEV_USER" kubectl -n default get secrets
check "backend exec 차단"          deny sudo -iu "$DEV_USER" kubectl -n default exec deploy/backend -- id
check "kube-system 차단"           deny sudo -iu "$DEV_USER" kubectl -n kube-system get pods
check "sudo 없음"                  deny sudo -iu "$DEV_USER" sudo -n true

echo
echo "완료. 7개 모두 PASS 면 정상이다."
echo "남은 것: MySQL dev 계정 생성 + 콘솔에서 IAM 유저 생성"
