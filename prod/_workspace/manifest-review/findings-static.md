# findings-static

> 라운드 1/2. 서브에이전트의 Write가 하네스 정책으로 차단되어, 에이전트 반환 본문을 오케스트레이터가 무변경 전사함.
> 검사 범위는 지정된 매니페스트 인벤토리 31개 파일 전체이며, terraform 파일은 열지 않았다.

## 커버리지
- 축 9: 검사함(발견 1건)
- 축 10: 검사함(발견 1건)
- 축 11: 검사함(발견 4건)
- 축 12: 검사함(발견 2건)
- 매니페스트 내부 참조 일관성: 검사함(발견 1건)

## 발견

### [경고] backend/frontend 이미지가 staging 태그를 그대로 prod에 사용 중

근거: manifest/app-node/application/backend.yaml:48-50 — "# TODO: prod 이미지 리포지토리/태그 확인 필요 (아래는 staging 기준 경로)\n          image: ghcr.io/likelion-cardinal/cardinal-be-staging:staging\n          imagePullPolicy: Always"
대조: manifest/app-node/application/setup.txt:93-99 — "현재 backend.yaml / frontend.yaml 은 staging 이미지 경로를 그대로 쓰고 있다. ... :staging / :latest 같은 가변 태그 + imagePullPolicy: Always 조합은 \"파드가 재시작되어야만\" 새 이미지를 받는다. ArgoCD 는 태그가 그대로면 변화를 감지하지 못하므로 자동 배포가 되지 않는다."
영향: 현재 상태로 apply 하면 prod 워크로드가 staging 전용 이미지 리포지토리(cardinal-be-staging/cardinal-fe-staging)를 그대로 받는다. 태그가 고정 문자열(":staging")이라 CI가 새 이미지를 같은 태그로 올려도 ArgoCD가 변경을 감지하지 못해 자동 배포가 되지 않고, 파드가 재시작될 때만 최신 이미지가 반영되는 비결정적 동작이 된다.
확신도: 높음(확실)
권고: prod 전용 이미지 리포지토리로 image 값을 바꾸고, 커밋 SHA 등 불변 태그를 사용하도록 backend.yaml/frontend.yaml 두 파일을 모두 수정할 것.
검사축: 11

### [경고] monitoring 네임스페이스 생성 커맨드의 멱등성이 두 setup.txt 사이에서 다름

근거: manifest/system-node/prometheus-grafana/setup.txt:6 — "kubectl create namespace monitoring"
대조: manifest/all/node-exporter/setup.txt:6 — "kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -"
영향: node-exporter를 먼저 적용해 monitoring 네임스페이스가 이미 존재하는 상태에서 prometheus-grafana/setup.txt 1번을 실행하면 `kubectl create namespace`가 "AlreadyExists" 에러로 실패한다. 치명적이지는 않지만 절차서를 그대로 스크립트화하면 그 지점에서 중단된다.
확신도: 높음(확실)
권고: prometheus-grafana/setup.txt 1번도 node-exporter와 동일하게 `kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -` 형태로 통일할 것.
검사축: 12

### [경고] cluster-autoscaler/setup.txt가 coredns-pdb 선행 적용을 언급하지 않음

근거: manifest/all/coredns/setup.txt:33-36 — "적용 순서\n----------------------------------------------------------------------\ncluster-autoscaler 배포보다 먼저 넣을 것 (축소가 시작되기 전에 보호막이 있어야 한다).\n선행 조건은 CoreDNS가 떠 있는 것뿐 — kubeadm init 직후면 이미 만족한다."
대조: manifest/system-node/cluster-autoscaler/setup.txt:15-21 — "사전 조건 (terraform 쪽, 이미 되어 있음)\n----------------------------------------------------------------------\nIAM   iam/main.tf:66-91 ...\nASG   app-asg/main.tf:21 ...\n노드  각 user_data ..." (coredns-pdb 관련 언급 없음)
영향: 운영자가 cluster-autoscaler/setup.txt만 보고 배포하면 coredns-pdb를 먼저 적용해야 한다는 사실을 놓칠 수 있다. CoreDNS 두 레플리카가 같은 노드에 있을 때 CA가 스케일인하면서 둘 다 동시에 evict해 클러스터 DNS가 일시적으로 끊길 위험이 있다.
확신도: 높음(문서 간 교차 참조 누락 자체는 확실, 실제 사고 발생 여부는 운영자 행동에 달림)
권고: cluster-autoscaler/setup.txt의 "사전 조건" 절에 "manifest/all/coredns (PDB)를 먼저 적용" 항목을 추가할 것.
검사축: 12

### [정보] ssl-certs hostPath가 노드 배포판에 따라 존재하지 않을 수 있음 (Ubuntu/Debian 계열 가정 시)

근거: manifest/system-node/cluster-autoscaler/cluster-autoscaler.yaml:176-182 — "            - name: ssl-certs\n              mountPath: /etc/ssl/certs/ca-certificates.crt\n              readOnly: true\n      volumes:\n        - name: ssl-certs\n          hostPath:\n            path: /etc/ssl/certs/ca-bundle.crt"
대조: (인프라 영역 — AMI 배포판은 이 감사 범위 밖)
영향: hostPath에 `type`이 지정되어 있지 않아 존재 여부를 kubelet이 사전 검증하지 않는다. 노드 AMI가 Ubuntu/Debian 계열이면 `/etc/ssl/certs/ca-bundle.crt`가 없어(그 배포판은 `ca-certificates.crt`를 씀) 마운트가 실패하거나 빈 상태가 돼, cluster-autoscaler가 AWS API TLS 검증에 실패해 CrashLoopBackOff에 빠질 수 있다. Amazon Linux 계열이면 문제 없다.
확신도: 낮음(추정) — 노드 OS 배포판은 terraform/AMI 영역이라 이 감사 범위 밖, 인프라 대조 필요
권고: 노드 AMI 배포판 확인 후 Ubuntu/Debian 계열이면 hostPath.path와 volumeMounts.mountPath를 모두 `/etc/ssl/certs/ca-certificates.crt`로 맞추고, hostPath에 `type: File`을 명시할 것.
검사축: 11

### [정보] 원격 kustomize base 3곳의 patches.target 매칭 여부는 정적으로 확인 불가

근거: manifest/system-node/argocd/kustomization.yaml:4,7-9,14-16 — "resources:\n  - https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.5/manifests/install.yaml\n...\n  - target:\n      kind: Deployment\n    patch: |-\n...\n  - target:\n      kind: StatefulSet\n    patch: |-"
대조: manifest/app-node/ingress-nginx/kustomization.yaml:4-5,34-41; manifest/app-node/metrics-server/kustomization.yaml:4,9-13,19-23
영향: 세 kustomization 모두 원격 URL을 resources로 가져와 그 안의 리소스에 patch를 건다. 원격 파일의 실제 내용은 리포지토리 밖에 있어 patches[].target 매칭 여부, JSON6902 path 유효성을 파일 대조만으로는 확정할 수 없다. 매칭 0건이면 strategic-merge patch는 조용히 무시되고, JSON6902 patch는 build 자체가 실패한다.
확신도: 낮음(추정)
권고: apply 전 각 디렉토리에서 `kustomize build .`(또는 `kubectl apply -k . --dry-run=client`)을 1회 실행해 patch 적용 결과를 확인할 것(이 감사 범위 밖 작업).
검사축: 11

### [정보] redis/rabbitmq/busybox 이미지가 마이너·메이저 단위로만 고정됨

근거: manifest/system-node/redis/redis.yaml:24 — "          image: redis:7"
대조: manifest/system-node/rabbitmq/rabbitmq.yaml:40 — "          image: rabbitmq:4-management"; manifest/system-node/mysql/mysql.yaml:44 — "          image: busybox:1.37" (동일 태그가 grafana.yaml:44, rabbitmq.yaml:32, prometheus.yaml:164에도 반복 사용)
영향: `latest`는 아니지만 패치 버전이 고정돼 있지 않아, 파드 재생성(노드 교체, Recreate 롤아웃) 시점마다 그때의 최신 마이너/패치 이미지를 새로 받아 배포 시점에 따라 동작이 달라질 수 있다.
확신도: 낮음(추정)
권고: 운영 재현성을 원하면 redis:7.x.y, rabbitmq:4.x.y-management, busybox:1.37.0 처럼 패치 버전까지 고정할 것.
검사축: 11

### [정보] 매니페스트 안에 Namespace 오브젝트가 하나도 없음 — 전부 imperative 생성에 의존

근거: manifest/system-node/mysql/setup.txt:6 — "kubectl create namespace database"; manifest/system-node/argocd/setup.txt:6 — "kubectl create namespace argocd" (`kind: Namespace`는 manifest/ 전체 31개 파일 어디에도 없음 — Grep으로 확인)
대조: manifest/all/node-exporter/setup.txt:6, manifest/system-node/prometheus-grafana/setup.txt:6 — 동일하게 imperative 생성
영향: 어떤 디렉토리에서도 `kubectl apply -f .` / `-k .` 만 실행하고 setup.txt의 namespace 생성 커맨드를 건너뛰면 "namespaces \"database\"(또는 argocd/monitoring) not found"로 apply가 실패한다. 순서 보장이 매니페스트가 아니라 사람이 setup.txt를 순서대로 따르는 것에 전적으로 달려 있다.
확신도: 높음(확실)
권고: 자동화(CI/CD)로 절차를 대체할 계획이 있으면, 각 디렉토리에 `kind: Namespace` 매니페스트를 추가해 apply 순서 의존을 코드로 강제하는 편을 검토할 것.
검사축: 10

### [정보] argocd/ingress-nginx의 RBAC 완결성은 원격 install.yaml/deploy.yaml 안에 있어 이 리포만으로 확인 불가

근거: manifest/system-node/argocd/kustomization.yaml:4 — "resources:\n  - https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.5/manifests/install.yaml"
대조: manifest/app-node/ingress-nginx/kustomization.yaml:4-5 — "resources:\n  - https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/baremetal/deploy.yaml\n  - daemonset.yaml"; manifest/app-node/ingress-nginx/daemonset.yaml:32 — "serviceAccountName: ingress-nginx"
영향: daemonset.yaml이 참조하는 `serviceAccountName: ingress-nginx`와 argocd 각 컴포넌트가 쓰는 ServiceAccount/(Cluster)Role/(Cluster)RoleBinding은 이 31개 파일 어디에도 정의돼 있지 않고 원격 파일 안에 있다고 가정한다. 원격 파일이 예상과 다르면 SA/RBAC 부재로 파드가 뜨지 않거나 컨트롤러가 권한 부족으로 오작동할 수 있다. (cluster-autoscaler.yaml은 SA/ClusterRole/Role/바인딩이 파일 안에 완결되어 있어 이상 없음)
확신도: 낮음(추정)
권고: apply 전 `kustomize build .` 1회로 원격 base가 필요한 ServiceAccount/RBAC를 실제로 포함하는지 확인할 것.
검사축: 9

### [정보] ArgoCD Application의 source.path가 실제 리포 구조와 일치함 (문제 없음, 확인 완료)

근거: manifest/system-node/argocd/application.yaml:12 — "path: prod/manifest/app-node/application"
대조: manifest/app-node/application/kustomization.yaml:1-13 — 해당 경로에 kustomization.yaml과 configmap.yaml/backend.yaml/frontend.yaml/ingress.yaml/hpa.yaml 5개 리소스가 실제로 존재함(Glob으로 확인, 비어있지 않음)
영향: 없음 — Application이 가리키는 경로가 실제로 존재하고 kustomization.yaml이 있어 ArgoCD가 kustomize 소스로 인식해 정상 동기화될 것으로 판단된다(directory 블록도 없어 argocd/setup.txt가 경고하는 ComparisonError 조건에도 해당하지 않음).
확신도: 높음(확실) — 로컬 파일 구조 기준. repoURL이 가리키는 GitHub 원격 main 브랜치 상태가 로컬과 동일한지는 git push 여부에 달려 있어 감사 범위 밖
권고: 없음(현행 유지). 배포 전 로컬과 원격(main 브랜치)의 prod/ 이하 구조가 실제로 push되어 동일한지만 확인할 것.
검사축: 내부 참조 일관성

---

## 요약

- 축 9: 발견 1건 (정보 1)
- 축 10: 발견 1건 (정보 1)
- 축 11: 발견 4건 (경고 1 / 정보 3)
- 축 12: 발견 2건 (경고 2)
- 매니페스트 내부 참조 일관성: 발견 1건 (정보 1)
- 합계: 치명 0 / 경고 3 / 정보 6
