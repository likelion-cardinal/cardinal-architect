# manifest-review 리포트

> 판정: PASS(커버리지 충족) · 라운드 1/2 · 치명 0 / 경고 5 / 정보 10
> PASS는 "12개 축을 근거 있게 다 봤다"는 뜻이지 "매니페스트에 문제가 없다"는 뜻이 아니다.
> (서브에이전트 Write가 하네스 정책으로 차단되어 오케스트레이터가 arbiter 반환 본문을 그대로 전사함. 내용 무변경.)

## 요약

- 치명 0건 / 경고 5건 / 정보 10건 · 라운드 1/2 · 판정 PASS
- 지금 `terraform apply` + 매니페스트 배포를 그대로 하면 **apply 자체는 성공하고 파드도 전부 뜬다. 깨지는 순서는 외부에서 안쪽으로다.** ① 가장 먼저 깨지는 것은 외부 접근이다 — `prod.tfvars:22`의 `register_app_nodes_to_alb = false` 때문에 ALB Target Group에 타깃이 0개라 80 리스너로 들어온 모든 요청이 503이 된다(backend·frontend·grafana 전부 접근 불가). ② 그 값을 true로 되돌려 접근이 뚫리는 순간 두 번째가 드러난다 — 443 리스너가 생성되지 않은 상태(`domain_name` 미설정)인데 `configmap.yaml:43`이 `JWT_COOKIE_SECURE: "true"`라, 평문 HTTP 응답의 Secure 쿠키를 브라우저가 저장하지 않아 로그인이 200을 받고도 세션이 남지 않는다(에러 로그가 없어 원인 추적이 어렵다). ③ 세 번째는 배포된 이미지 자체다 — backend/frontend가 `cardinal-be-staging:staging`을 그대로 가리켜 prod에 staging 아티팩트가 올라가고, 가변 태그라 ArgoCD 자동 배포도 성립하지 않는다. ④ 그다음이 노드 용량·저장소로, system 노드 메모리 limit 합 7488Mi가 allocatable 추정 7760Mi의 96%라 부하가 오르면 MySQL·Prometheus가 축출되고, 데이터 EBS가 60초 안에 안 보이면 user_data가 마운트를 **경고 한 줄 없이** 건너뛰어 네 컴포넌트의 hostPath가 통째로 루트 EBS로 떨어진다(AMI 교체 시 전량 소실). 축 1(라벨 전파)·2(CP 테인트/toleration)·3(CA 3중 정합)·4(리전)은 재검증 결과 실제로 문자 그대로 일치하며, 클러스터를 못 세우는 치명 결함은 이번 라운드에서 발견되지 않았다.

## 치명

- 없음

## 경고

### [경고] 데이터 EBS가 60초 안에 안 보이면 user_data가 마운트를 조용히 건너뛰고 4개 컴포넌트의 hostPath가 루트 EBS로 떨어진다

- 근거: manifest/system-node/mysql/mysql.yaml:110-112 — "hostPath:" / "path: /mnt/data/mysql" / "type: DirectoryOrCreate"
- 근거: manifest/system-node/prometheus-grafana/prometheus.yaml:210-212, manifest/system-node/prometheus-grafana/grafana.yaml:100-102, manifest/system-node/rabbitmq/rabbitmq.yaml:84-86 — 동일하게 `type: DirectoryOrCreate` (경로가 없으면 kubelet이 만들어 마운트 실패를 감지하지 못한다)
- 대조: terraform/modules/system-node/user_data.sh.tftpl:26 — "for _ in $(seq 1 30); do" (`:32`의 `sleep 2`와 합쳐 최대 60초 대기)
- 대조: terraform/modules/system-node/user_data.sh.tftpl:35 — "if [ -n \"$DATA_DEV\" ]; then" (이 블록은 `:54`의 `fi`로 끝나며 **else가 없다**. `:51-53`의 WARNING은 안쪽 `mountpoint -q` 실패 경로 전용이라, 디스크 자체가 안 보이면 마운트·서브디렉토리 생성·경고가 전부 건너뛰어진 채 스크립트가 정상 종료한다)
- 대조: terraform/modules/system-node/main.tf:73,86 — "availability_zone = aws_instance.system.availability_zone" / "instance_id = aws_instance.system.id" (`aws_ebs_volume`·`aws_volume_attachment`가 인스턴스 생성 **이후**에 만들어지는 의존 순서라 부팅 직후 경합 창이 실재한다)
- 영향: 경합에서 지면 `/mnt/data` 미마운트 상태로 kubeadm join까지 성공한다. `DirectoryOrCreate`가 30GiB 루트 EBS(`system-node/variables.tf:53`) 위에 같은 경로를 새로 만들어 MySQL·Prometheus·Grafana·RabbitMQ 데이터가 전부 루트로 간다. `terraform/main.tf:112-113`이 명시적으로 금지한 상태("살아남아야 할 데이터를 루트에 두면 AMI를 다시 굽는 순간 메트릭과 대시보드가 전소한다")가 **무증상으로** 성립하며, AMI 교체/replacement 시 전량 소실된다. 파드는 정상 기동하고 로그에 WARNING 한 줄도 남지 않아 배포 시점에 발견할 수단이 없다 — 치명(Pending/CrashLoop)은 아니지만 조용한 데이터 소실 구조라 경고를 유지한다.
- 확신도: 추정
- 권고: `user_data.sh.tftpl` `:34` 뒤에 `DATA_DEV`가 비었을 때 stderr 로그를 남기고 `exit 1`로 죽는 분기를 추가해 join 전에 실패가 드러나게 하고, 대기 루프를 30회→90회(약 180초)로 늘릴 것. 매니페스트 쪽은 mysql.yaml:112 / prometheus.yaml:212 / grafana.yaml:102 / rabbitmq.yaml:86의 `type`을 `DirectoryOrCreate`에서 `Directory`로 바꾸면 경로 부재 시 파드가 Pending으로 드러난다.
- 검사축: 6

### [경고] system 노드 메모리 limit 합 7488Mi가 allocatable 추정치(약 7760Mi)의 96%다

- 근거: manifest/system-node/mysql/mysql.yaml:76-77 — "limits:" / "memory: 2Gi"
- 근거: manifest/system-node/prometheus-grafana/prometheus.yaml:186-187 (1Gi), manifest/system-node/prometheus-grafana/grafana.yaml:76-77 (1Gi), manifest/system-node/rabbitmq/rabbitmq.yaml:60-61 (1Gi), manifest/system-node/redis/redis.yaml:41-43 (384Mi), manifest/system-node/cluster-autoscaler/cluster-autoscaler.yaml:173-174 (512Mi), manifest/system-node/argocd/kustomization.yaml:37,53,69,85 (512+448+256+128 = 1344Mi), manifest/all/node-exporter/node-exporter.yaml:44-45 (128Mi) — 합계 **7488Mi** (재계산으로 확인)
- 대조: terraform/modules/system-node/variables.tf:33 — "description = \"System Worker 타입 (ArgoCD·Prom·Graf·MySQL ≈7Gi → 8Gi)\"" (`:35` 기본값 `m7i-flex.large` = 2 vCPU / 8GiB. 이 산정 근거에 **RabbitMQ(limit 1Gi)와 Redis(384Mi)가 빠져 있고**, 둘 다 이번에 새로 추가된 디렉토리다)
- 영향: **CPU와 requests는 여유가 있어 파드가 못 뜨는 상황은 없다** — requests CPU 975m(argocd 325m + CA 100 + prometheus 100 + grafana 50 + mysql 250 + rabbitmq 100 + redis 50; applicationset/notifications/dex는 `kustomization.yaml:92,109,126`의 `replicas: 0`이라 0m) + DaemonSet(node-exporter 10m, calico-node 250m 추정) = 1235m/2000m(62%), 메모리 requests 3040Mi. 문제는 limit 합 7488Mi 대 allocatable 약 7760Mi(capacity 약 7860Mi − evictionHard 100Mi)다. kubeadm이 `kube-reserved`/`system-reserved`를 설정하지 않아 kubelet·containerd·systemd의 500~800Mi가 이 안에서 경합하므로, 파드들이 limit 근처로 오르면 eviction이 시작되고 Burstable QoS인 MySQL·Prometheus가 우선 축출돼 hostPath 파드가 재시작된다. CoreDNS 2레플리카(70Mi×2)가 이 노드에 얹히면 여유는 더 준다. 기동은 되므로 치명은 아니나 "용량 부족"에 해당해 경고.
- 확신도: 추정
- 권고: (a) `system-node/variables.tf:35`를 `m7i-flex.xlarge`(4 vCPU/16GiB)로 올리고 `:33` 산정 문구에 RabbitMQ·Redis를 반영하거나, (b) limit 합을 allocatable 80%(약 6200Mi) 이하로 내릴 것 — mysql 2Gi→1536Mi, grafana 1Gi→512Mi, rabbitmq 1Gi→768Mi가 손해가 가장 적다. 어느 쪽이든 kubelet에 `--system-reserved`/`--kube-reserved`(예: cpu=200m,memory=512Mi)를 걸어 호스트 몫을 먼저 빼두는 편이 정확하다.
- 검사축: 7

### [경고] App 노드가 ALB Target Group에 등록되지 않아 매니페스트가 전제하는 ALB→NodePort 경로가 성립하지 않는다

- 근거: manifest/app-node/ingress-nginx/kustomization.yaml:29 — "nodePort: 30080" (`:24` `type: NodePort`, `:32` `nodePort: 30443`)
- 근거: manifest/app-node/ingress-nginx/setup.txt:26 — "ALB 타겟그룹 port 30080  ←→  Service nodePort 30080  (http)" (application/ingress.yaml·prometheus-grafana/ingress.yaml 모두 이 경로로만 외부 노출된다)
- 대조: terraform/env/prod.tfvars:22 — "register_app_nodes_to_alb = false"
- 대조: terraform/main.tf:192 — "target_group_arns = var.register_app_nodes_to_alb ? [module.alb.target_group_arn] : []" (→ app ASG에 TG가 붙지 않는다. system 노드는 ASG가 아니어서 `system-node/main.tf:33-64`에 TG 참조가 아예 없다)
- 영향: apply는 성공하고 파드도 정상 기동하지만, `alb/main.tf:91-98`의 80 리스너 forward가 **타깃 0개 TG**로 넘겨 모든 외부 요청이 503이 된다. backend·frontend·grafana 어느 것도 외부 접근이 안 된다. 다만 `prod.tfvars:11-21`이 이 상태를 의도된 임시 단계로 명시하고 복구 절차(4단계)까지 적어두었고 `ingress-nginx/setup.txt:19-21`에도 같은 단계가 있어, **문서화된 수동 선행 단계 의존**으로 판정해 경고를 유지한다(절차를 잊으면 서비스가 통째로 접속 불가로 남으므로 실질 영향은 치명급이다). 반대로 컨트롤러 배포 전에 true로 올리면 `prod.tfvars:19-20` 경고대로 노드가 약 45초마다 교체된다.
- 확신도: 확실
- 권고: ingress-nginx 배포 후 app 노드에서 `curl -I localhost:30080`이 응답(404 포함, matcher가 200-404)하는 것을 확인한 직후 `prod.tfvars:22`를 `true`로 바꿔 apply할 것(ASG in-place 업데이트라 노드 교체 없음). `prod.tfvars:11`의 TODO 제거까지 절차에 포함시킬 것. 매니페스트 수정은 불필요하다.
- 검사축: 8

### [경고] ALB 443 리스너가 생성되지 않는 상태인데 매니페스트는 "ALB가 TLS를 종료한다"를 전제로 Secure 쿠키를 강제한다

- 근거: manifest/app-node/application/configmap.yaml:43 — "JWT_COOKIE_SECURE: \"true\"" (`:40` 주석이 "ALB 가 TLS 를 종료하고 뒤로는 평문 HTTP 다. 브라우저 입장에서는 https 이므로 true 로 둔다"로 전제를 명시)
- 대조: terraform/main.tf:146 — "enable_https    = var.domain_name != \"\" && var.wait_for_certificate_validation"
- 대조: terraform/env/prod.tfvars:28-29 — "# domain_name = \"2026cardinal.com\"" / "# wait_for_certificate_validation = true" (두 줄 모두 주석 처리 → `variables.tf:80`의 기본값 `""`, `variables.tf:86`의 기본값 `false` → **enable_https=false** → `alb/main.tf:102-103`의 `count = local.https_enabled ? 1 : 0`으로 443 리스너 미생성, dns 모듈도 `main.tf:123`의 count 0으로 생략)
- 영향: 외부 접점이 `http://<alb-dns-name>/` 하나뿐이 된다. 브라우저는 평문 HTTP 응답의 `Secure` 쿠키를 저장하지 않으므로 로그인은 200을 받고도 세션이 남지 않아 즉시 로그아웃 상태가 되고, 서버 에러 로그가 없어 원인 파악이 어렵다. 위 ALB TG 미등록 항목을 해소한 직후 **가장 먼저 사용자에게 보이는 고장**이 이것이다. 백엔드 파드 자체는 정상 기동·응답하고 미인증 경로는 동작하므로 "기능을 전혀 못 한다"에는 못 미쳐 경고로 판정하되, 경고 대역의 최상단이다. `ingress.yaml:10`의 `nginx.ingress.kubernetes.io/ssl-redirect: "false"`는 현 상태에서 오히려 옳다(true였다면 존재하지 않는 443으로 무한 리다이렉트). Grafana는 `GF_SERVER_ROOT_URL`이 `%(protocol)s`(grafana.yaml:66)라 영향 없다.
- 확신도: 확실
- 권고: 도메인 취득 전까지 `configmap.yaml:43`을 `"false"`로 둘 것. 도메인 구매 후 `prod.tfvars:28-29` 두 줄의 주석을 풀어 443 리스너가 실제로 생성된 것을 확인한 뒤 `"true"`로 되돌린다. 되돌릴 때 `configmap.yaml:41-42`가 요구하는 Spring `server.forward-headers-strategy` 설정이 실제로 들어가 있는지 함께 확인할 것.
- 검사축: 8

### [경고] backend/frontend 이미지가 staging 리포지토리·가변 태그를 그대로 prod에 사용한다

- 근거: manifest/app-node/application/backend.yaml:48-50 — "# TODO: prod 이미지 리포지토리/태그 확인 필요 (아래는 staging 기준 경로)" / "image: ghcr.io/likelion-cardinal/cardinal-be-staging:staging" / "imagePullPolicy: Always"
- 대조: manifest/app-node/application/setup.txt:93-99 — "현재 backend.yaml / frontend.yaml 은 staging 이미지 경로를 그대로 쓰고 있다. ... :staging / :latest 같은 가변 태그 + imagePullPolicy: Always 조합은 \"파드가 재시작되어야만\" 새 이미지를 받는다. ArgoCD 는 태그가 그대로면 변화를 감지하지 못하므로 자동 배포가 되지 않는다."
- 영향: 현재 상태로 apply하면 prod 워크로드가 staging 전용 리포지토리(`cardinal-be-staging`/`cardinal-fe-staging`)의 아티팩트를 받는다. 파드는 뜨므로 치명은 아니지만, 태그가 고정 문자열이라 CI가 새 이미지를 같은 태그로 올려도 ArgoCD가 변경을 감지하지 못해 **자동 배포가 성립하지 않고**, 파드가 재시작될 때만 최신 이미지가 반영되는 비결정적 동작이 된다(= 롤백 대상 아티팩트도 특정 불가). `argocd/application.yaml:18-21`의 `automated.selfHeal: true`가 의미를 잃는다.
- 확신도: 확실
- 권고: backend.yaml:49와 frontend.yaml의 대응 줄을 prod 전용 이미지 리포지토리로 바꾸고, 커밋 SHA 등 불변 태그를 쓰도록 두 파일을 모두 수정할 것. 불변 태그로 바꾸면 `imagePullPolicy`는 `IfNotPresent`가 적절하다.
- 검사축: 11

## 정보

### [정보] CA용 AWS 권한이 노드 공용 인스턴스 프로파일에 있어 app 노드 파드에도 그대로 노출된다

- 근거: manifest/system-node/cluster-autoscaler/cluster-autoscaler.yaml:139 — "serviceAccountName: cluster-autoscaler" (SA 정의 `:1-7`에 IRSA 어노테이션이 없음을 직접 확인 = AWS 자격을 노드 인스턴스 프로파일에서만 얻는 구조)
- 대조: terraform/main.tf:175 — "instance_profile_name = module.iam.instance_profile_name" (app_asg 인자. system_node `:103`, control_plane `:77`과 **동일한 단일 프로파일**)
- 대조: terraform/modules/iam/main.tf:78-95 — "autoscaling:SetDesiredCapacity" / "autoscaling:TerminateInstanceInAutoScalingGroup", `:25-37`의 `ssm:GetParameter`·`ssm:PutParameter`·`ssm:DeleteParameter`, `:44`의 `kms:Decrypt` — 모두 같은 `aws_iam_role.node` 하나에 붙는다(`:153-157`)
- 대조: terraform/modules/app-asg/main.tf:50 — "http_put_response_hop_limit = 2 # 파드에서 IMDS 접근 허용"
- 영향: apply는 성공하고 CA도 정상 동작한다(축 3의 기능 정합은 재검증 결과 문제없음). 문제는 노출 범위다 — hop limit 2로 app 노드의 모든 파드가 IMDS에 도달하며, 그 노드에는 인터넷에 직접 노출되는 ingress-nginx·backend·frontend가 뜬다. 하나라도 SSRF/RCE가 나면 `ssm:GetParameter --with-decryption`+`kms:Decrypt`로 join 커맨드 전문(SecureString)을 읽어 임의 노드를 클러스터에 붙이거나 `TerminateInstanceInAutoScalingGroup`으로 app ASG 인스턴스를 종료할 수 있다. **심각도는 감사자의 경고에서 정보로 내렸다** — 이 리뷰의 심각도 정의는 apply 실패·Pending/CrashLoop·기능 상실·운영 중 장애를 기준으로 하고 "권한 부족"만 경고 예시에 있는 반면 이 건은 권한 **과다**라 운영 중 장애를 일으키지 않는다. 등급 인하는 위험의 부정이 아니라 이 리뷰 rubric상의 분류다.
- 확신도: 확실
- 권고: iam 모듈을 역할별로 분리해 CA 권한(`autoscaling:SetDesiredCapacity`·`TerminateInstanceInAutoScalingGroup`)과 `ssm:PutParameter`/`DeleteParameter`는 system·CP 프로파일에만 남기고, app-asg에는 join 토큰 읽기(`ssm:GetParameter`+`kms:Decrypt`)만 가진 최소 프로파일을 붙일 것. 다만 app 노드 `http_put_response_hop_limit`을 1로 낮추는 안은 "IRSA가 없어 파드가 인스턴스 프로파일을 쓴다"는 이 클러스터의 기존 결정과 충돌할 수 있으니, app 노드에 IMDS를 쓰는 파드가 없다는 것을 확인한 뒤에만 적용할 것.
- 검사축: 3

### [정보] 원격 kustomize base 3종(argo-cd v3.4.5 / ingress-nginx v1.15.1 / metrics-server v0.8.0)의 내용이 리포 밖에 있어 patch 매칭·RBAC 포함·k8s 1.34 호환을 정적으로 확정할 수 없다

- 근거: manifest/system-node/argocd/kustomization.yaml:4 — "- https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.5/manifests/install.yaml" (`:7-9`·`:14-16`이 `target: kind: Deployment`/`kind: StatefulSet`에 JSON6902 `op: add /spec/template/spec/nodeSelector`를 건다)
- 근거: manifest/app-node/ingress-nginx/kustomization.yaml:5 — "- https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/baremetal/deploy.yaml" (`:9-15`의 `$patch: delete`, `:34-41`의 `target: kind: Job` JSON6902)
- 근거: manifest/app-node/metrics-server/kustomization.yaml:5 — "- https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.0/components.yaml" (`:10-17`의 `path: /spec/template/spec/containers/0/args/-`, `:22-30`의 nodeSelector add — 감사자 인용의 줄번호 9-13/19-23을 실제 값으로 교정)
- 근거: manifest/app-node/ingress-nginx/daemonset.yaml:32 — "serviceAccountName: ingress-nginx" (이 SA와 argocd 각 컴포넌트의 SA/(Cluster)Role/(Cluster)RoleBinding은 로컬 매니페스트 어디에도 없고 원격 base 안에 있다고 가정한다 — `kind: ServiceAccount|ClusterRole|RoleBinding` 전수 Grep으로 확인. cluster-autoscaler.yaml(`:2,11,70,86,103`)과 prometheus.yaml(`:2,9,27`)은 파일 안에서 RBAC가 완결되어 있어 이상 없음)
- 대조: terraform/modules/control-plane/variables.tf:76 — "default     = \"v1.34.9\"" (`prod.tfvars:4` "k8s 1.34.9 / containerd 2.2.5 / Calico 3.32.1(VXLAN=Always)"와 동일)
- 영향: 하나의 원인(원격 base 3종의 본문이 리포지토리 밖에 있다)에서 세 가지 증상이 나온다. ① `patches[].target` 매칭이 0건이면 strategic-merge patch는 **조용히 무시**되고(→ nodeSelector가 안 붙어 argocd가 app 노드로 새거나, ingress-nginx Deployment 삭제가 실패해 Deployment와 DaemonSet이 동시에 뜬다), JSON6902 patch는 `kustomize build` 자체가 실패한다. ② argocd/ingress-nginx의 SA·RBAC가 원격 base에 기대와 다르게 들어 있으면 파드가 안 뜨거나 컨트롤러가 권한 부족으로 오작동한다. ③ 세 base 중 하나라도 1.34에서 제거된 API를 쓰면 그 컴포넌트만 apply/기동에 실패한다. 어느 쪽도 파일 대조만으로는 확정할 수 없어 판정 보류다. 같은 축의 cluster-autoscaler는 `:149`의 `v1.34.5`로 클러스터 마이너와 정확히 맞아 이 위험이 없다.
- 확신도: 추정
- 권고: apply 전 argocd/ingress-nginx/metrics-server 세 디렉토리에서 각각 `kustomize build .`(또는 `kubectl apply -k . --dry-run=client`)을 1회 실행해 (i) patch가 실제로 반영됐는지, (ii) ServiceAccount/RBAC가 산출물에 포함되는지 확인할 것. 세 프로젝트 호환 매트릭스에서 1.34 포함 여부를 확인한 뒤 각 setup.txt에 "검증한 클러스터 버전: 1.34.9"를 남길 것. 매니페스트 값을 지금 바꿀 근거는 없다.
- 검사축: 5, 9, 11

### [정보] 20GiB 단일 데이터 볼륨의 소비자 계약이 테라폼(3개)과 매니페스트(4개)로 갈라져 있고 쿼터가 없다

- 근거: manifest/system-node/rabbitmq/rabbitmq.yaml:85 — "path: /mnt/data/rabbitmq" (`:83` 주석이 "mysql·prometheus·grafana 와 같은 데이터 EBS(/mnt/data)를 나눠 쓴다"고 스스로 선언)
- 근거: manifest/system-node/prometheus-grafana/prometheus.yaml:177 — "- --storage.tsdb.retention.size=5GB" (`:176`의 `--storage.tsdb.retention.time=15d`와 병용. base-2 파싱이라 5GiB, 블록+WAL 포함 약 5.5GiB)
- 대조: terraform/modules/system-node/user_data.sh.tftpl:47 — "mkdir -p ${mount_point}/mysql ${mount_point}/prometheus ${mount_point}/grafana" (**rabbitmq 없음**. chown도 `:49-50`의 prometheus 65534·grafana 472뿐)
- 대조: terraform/main.tf:111 — "#   /mnt/data/mysql /mnt/data/prometheus /mnt/data/grafana" (`system-node/variables.tf:87,93`의 description도 동일하게 3개만 열거)
- 대조: terraform/main.tf:115 — "data_volume_size = 20" (`system-node/main.tf:70-79`의 20GiB gp3 하나를 mysql.yaml:111·prometheus.yaml:211·grafana.yaml:101·rabbitmq.yaml:85가 서브디렉토리로 나눠 쓴다. LVM/쿼터/개별 PV 없이 같은 ext4 — `user_data.sh.tftpl:37`의 `mkfs.ext4 -L cardinal-data`)
- 영향: 기동에는 지장이 없다 — `DirectoryOrCreate`가 `/mnt/data/rabbitmq`를 root:root 0755로 만들고 `rabbitmq.yaml:29-37`의 initContainer가 `runAsUser: 0`으로 chown하므로 권한 충돌도 없다. 남는 문제는 두 가지다. ① 계약 드리프트 — 볼륨 소비자 목록이 테라폼(3개)과 실제(4개)로 갈라져 이후 볼륨 크기 산정·백업 대상 선정에서 rabbitmq가 누락되기 쉽다(redis는 hostPath를 안 쓰므로 목록 제외가 맞다). ② 쿼터 부재 — 20GiB − ext4 5% 예약(약 1.0GiB) ≈ 가용 18GiB에서 Prometheus 5.5 + Grafana 0.5 + RabbitMQ 0.5를 빼면 MySQL 몫이 약 11.5GiB인데 상한이 없어, MySQL이 이를 넘기면 같은 파일시스템의 Prometheus가 쓰기 실패로 죽고 Grafana(sqlite)·RabbitMQ(mnesia)도 동시에 깨진다. Prometheus 65534·Grafana 472로 비root 실행이라(prometheus.yaml:158, grafana.yaml:38) 5% root 예약분은 이들이 쓸 수 없어 체감 여유는 더 작다. 즉각 고갈은 없고 고갈 시점이 MySQL 증가 속도에 달려 있어 정보로 둔다.
- 확신도: 추정
- 권고: `user_data.sh.tftpl:47`의 mkdir 목록에 `${mount_point}/rabbitmq`를 추가하고 `chown 999:999`를 함께 넣을 것. `terraform/main.tf:111`과 `system-node/variables.tf:87,93`의 열거에도 RabbitMQ를 더해 계약을 일치시킬 것. 용량은 node-exporter filesystem 메트릭으로 `/mnt/data` 80% 알람을 먼저 걸고, 여유가 필요하면 `main.tf:115`의 `data_volume_size`를 20→40으로 올리거나 MySQL 전용 EBS를 분리할 것. Prometheus retention은 현행 유지가 적절하다.
- 검사축: 6

### [정보] CP는 t3.medium standard 크레딧(baseline 400m)인데 상주 파드 CPU requests 합이 910m다

- 근거: manifest/all/node-exporter/node-exporter.yaml:24-27 — "tolerations:" / "- key: node-role.kubernetes.io/control-plane" / "operator: Exists" / "effect: NoSchedule" (`:17-23`의 `cardinal.io/role Exists` nodeAffinity와 합쳐져 CP에도 반드시 스케줄. requests는 `:41-43`의 cpu 10m / memory 32Mi)
- 대조: terraform/modules/control-plane/main.tf:50-56 — "dynamic \"credit_specification\" {" / "for_each = startswith(var.instance_type, \"t\") ? [1] : []" / "cpu_credits = \"standard\"" (`variables.tf:35` 기본값 `t3.medium`에 걸리며, `main.tf:42`의 주석이 baseline을 "t3.medium = 2 vCPU × 20% = 400m"로 스스로 명시한다)
- 영향: 스케줄링은 문제없다 — 정적 파드 650m(apiserver 250 + controller-manager 200 + scheduler 100 + etcd 100) + calico-node 250m(추정) + node-exporter 10m = 910m / 2000m = 46%. 다만 standard 모드는 크레딧 소진 시 실사용이 400m로 쓰로틀되므로, CA가 app 노드를 3대까지 올려 apiserver watch 부하가 늘거나 etcd 컴팩션이 겹치면 apiserver 응답이 느려진다. `main.tf:45`의 "유휴 100~150m" 전제는 피크에는 적용되지 않는다.
- 확신도: 추정
- 권고: 지금 바꿀 필요는 없다. 피크 전 CloudWatch `CPUCreditBalance`만 확인하고 소진 추세면 `control-plane/variables.tf:35`를 `m7i-flex.large`로 올릴 것(그 순간 `main.tf:50`의 dynamic 블록이 자동으로 빠진다). unlimited 전환은 `main.tf:42-46`이 적어둔 정산 사유상 선택지가 아니다.
- 검사축: 7

### [정보] cluster-autoscaler의 ssl-certs hostPath는 AL2023 AMI에서 해소되나 `type` 미지정이 남는다

- 근거: manifest/system-node/cluster-autoscaler/cluster-autoscaler.yaml:175-182 — "- name: ssl-certs" / "mountPath: /etc/ssl/certs/ca-certificates.crt" / "readOnly: true" / "volumes:" / "- name: ssl-certs" / "hostPath:" / "path: /etc/ssl/certs/ca-bundle.crt"
- 대조: terraform/env/prod.tfvars:3-6 — "# 노드 공용 커스텀 AMI (2026-07-22 빌드)" / "#   AL2023 x86_64 / k8s 1.34.9 / containerd 2.2.5 / Calico 3.32.1(VXLAN=Always)" / "node_ami_id = \"ami-0c32cc5a0cd32fe2c\"" (`terraform/main.tf:74,100,173`이 세 노드 그룹 모두에 같은 `var.node_ami_id`를 넘긴다)
- 영향: **두 감사자의 충돌을 조정한 항목이다.** static은 노드가 Ubuntu/Debian 계열이면 `/etc/ssl/certs/ca-bundle.crt`가 없어 CA가 AWS API TLS 검증에 실패해 CrashLoopBackOff에 빠질 수 있다고 보았고, infra는 AL2023 기본 제공이라 이상 없다고 보았다. tfvars에서 AMI가 AL2023임이 확정되므로 **static의 전제 조건이 성립하지 않아 CrashLoop 위험은 해소**된다(치명 후보 → 정보로 인하). 잔존 사항은 강건성뿐이다 — `hostPath`에 `type`이 없어 kubelet이 파일 존재를 사전 검증하지 않으므로, 이후 AMI를 다른 배포판으로 교체하면 같은 실패가 무증상으로 되살아난다.
- 확신도: 확실
- 권고: 현행 유지로 문제없다. 강건성을 원하면 `cluster-autoscaler.yaml:181-182`의 hostPath에 `type: File`을 명시해, 이후 AMI 교체로 경로가 사라지면 파드가 CrashLoop 대신 마운트 실패로 즉시 드러나게 할 것.
- 검사축: 6, 11

### [정보] redis/rabbitmq/busybox 이미지가 마이너·메이저 단위로만 고정됨

- 근거: manifest/system-node/redis/redis.yaml:24 — "image: redis:7"
- 대조: manifest/system-node/rabbitmq/rabbitmq.yaml:40 — "image: rabbitmq:4-management"
- 대조: manifest/system-node/mysql/mysql.yaml:44 — "image: busybox:1.37" (동일 태그가 rabbitmq.yaml:31, grafana.yaml:43, prometheus.yaml:163에도 반복 사용 — 감사자 인용의 grafana:44/prometheus:164를 실제 값으로 교정)
- 영향: `latest`는 아니라 최악은 아니지만 패치 버전이 고정돼 있지 않아, 파드 재생성(노드 교체, Recreate 롤아웃) 시점마다 그때의 최신 마이너/패치 이미지를 새로 받아 배포 시점에 따라 동작이 달라질 수 있다. mysql:8.4·grafana/grafana:13.1.1·prometheus:v3.13.1·node-exporter:v1.12.1·cluster-autoscaler:v1.34.5는 이미 충분히 고정돼 있어 대상이 아니다.
- 확신도: 추정
- 권고: 운영 재현성을 원하면 `redis:7.x.y`, `rabbitmq:4.x.y-management`, `busybox:1.37.0`처럼 패치 버전까지 고정할 것.
- 검사축: 11

### [정보] 매니페스트 안에 Namespace 오브젝트가 하나도 없어 전부 imperative 생성에 의존한다

- 근거: manifest/system-node/mysql/setup.txt:6 — "1. kubectl create namespace database" (`manifest/system-node/argocd/setup.txt:6`의 "kubectl create namespace argocd"도 동일 형태)
- 대조: manifest/ 전체에서 `kind: Namespace` Grep 결과 **0건** (31개 파일 어디에도 없음을 직접 확인)
- 영향: 어떤 디렉토리에서든 `kubectl apply -f .` / `-k .`만 실행하고 setup.txt의 namespace 생성 커맨드를 건너뛰면 `namespaces "database"(또는 argocd/monitoring) not found`로 apply가 실패한다. 순서 보장이 매니페스트가 아니라 사람이 setup.txt를 순서대로 따르는 것에 전적으로 달려 있다. 절차를 따르면 문제가 없으므로 정보로 둔다. 참고로 `argocd/application.yaml:23`의 `CreateNamespace=true`는 ArgoCD가 관리하는 `default` 대상에만 해당해 나머지 네임스페이스를 구제하지 못한다.
- 확신도: 확실
- 권고: 자동화(CI/CD)로 절차를 대체할 계획이 있으면 각 디렉토리에 `kind: Namespace` 매니페스트를 추가해(kustomize `resources` 첫 항목) apply 순서 의존을 코드로 강제하는 편을 검토할 것.
- 검사축: 10

### [정보] namespace 생성 커맨드의 멱등성이 setup.txt마다 제각각이다

- 근거: manifest/system-node/prometheus-grafana/setup.txt:6 — "1. kubectl create namespace monitoring" (멱등하지 않음)
- 대조: manifest/all/node-exporter/setup.txt:6 — "1. kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -" (멱등)
- 대조: manifest/system-node/redis/setup.txt:6, manifest/system-node/rabbitmq/setup.txt:6 — "1. kubectl get ns database || kubectl create namespace database" (또 다른 멱등 형태. `manifest/system-node/mysql/setup.txt:6`·`manifest/system-node/argocd/setup.txt:6`은 비멱등 형태 — 같은 리포에 세 가지 관용구가 섞여 있다)
- 영향: 문서화된 순서(prometheus-grafana → node-exporter, mysql → redis/rabbitmq)를 따르면 실패하지 않는다. 다만 node-exporter나 redis/rabbitmq를 먼저 적용해 네임스페이스가 이미 있는 상태에서 prometheus-grafana/setup.txt 1번이나 mysql/setup.txt 1번을 실행하면 `AlreadyExists` 에러로 그 줄이 실패하고, 절차서를 `set -e` 스크립트로 옮기면 그 지점에서 중단된다. 클러스터 상태를 깨지 않는 절차서 부정확이므로 감사자의 경고에서 정보로 인하했다.
- 확신도: 확실
- 권고: 여섯 setup.txt의 1번을 하나의 멱등 관용구로 통일할 것 — `kubectl create namespace <ns> --dry-run=client -o yaml | kubectl apply -f -` 형태를 기준으로 삼는 편이 `get ||` 형태보다 경합에 안전하다.
- 검사축: 12

### [정보] cluster-autoscaler/setup.txt가 coredns-pdb 선행 적용을 사전 조건에 적지 않았다

- 근거: manifest/all/coredns/setup.txt:33-36 — "적용 순서" / "cluster-autoscaler 배포보다 먼저 넣을 것 (축소가 시작되기 전에 보호막이 있어야 한다)." / "선행 조건은 CoreDNS가 떠 있는 것뿐 — kubeadm init 직후면 이미 만족한다."
- 대조: manifest/system-node/cluster-autoscaler/setup.txt:15-21 — "사전 조건 (terraform 쪽, 이미 되어 있음)" / "IAM   iam/main.tf:66-91 ..." / "ASG   app-asg/main.tf:21 ..." / "노드  각 user_data ..." (terraform 선행 조건만 나열하고 **coredns-pdb 언급이 없음**)
- 영향: 운영자가 cluster-autoscaler/setup.txt만 보고 배포하면 coredns-pdb를 먼저 적용해야 한다는 사실을 놓칠 수 있다. CoreDNS 두 레플리카가 CA 관리 대상인 app 노드 한 대에 몰려 있을 때 스케일인이 둘을 동시에 evict하면 클러스터 DNS가 일시적으로 끊긴다. 보호 수단(coredns-pdb)이 리포에 실재하고 그 자신의 setup.txt가 순서를 명시하고 있어, 남은 결손은 문서 간 상호 참조 하나뿐이므로 감사자의 경고에서 정보로 인하했다.
- 확신도: 확실
- 권고: `cluster-autoscaler/setup.txt`의 "사전 조건" 절에 "manifest/all/coredns (PDB)를 먼저 적용할 것" 한 줄을 추가할 것.
- 검사축: 12

### [정보] ArgoCD Application의 source.path가 실제 리포 구조와 일치한다 (확인 완료, 조치 불필요)

- 근거: manifest/system-node/argocd/application.yaml:12 — "path: prod/manifest/app-node/application" (`:10` repoURL `https://github.com/likelion-cardinal/cardinal-architect.git`, `:11` targetRevision `main`, `:16` destination.namespace `default`)
- 대조: manifest/app-node/application/kustomization.yaml:6,8-13 — "namespace: default" / "resources:" / "- configmap.yaml" / "- backend.yaml" / "- frontend.yaml" / "- ingress.yaml" / "- hpa.yaml" (해당 경로에 kustomization.yaml이 실재하고 5개 리소스 파일이 모두 존재함을 직접 확인)
- 영향: 없음. Application이 가리키는 경로가 실재하고 kustomization.yaml이 있어 ArgoCD가 kustomize 소스로 인식한다. `directory` 블록이 없어 argocd/setup.txt가 경고하는 ComparisonError 조건에도 해당하지 않으며, kustomization의 `namespace: default`와 Application의 `destination.namespace: default`가 일치해 `kubectl apply -k`와 ArgoCD 동기화 결과가 같다.
- 확신도: 확실
- 권고: 현행 유지. 배포 전 로컬과 원격 `main` 브랜치의 `prod/` 이하 구조가 실제로 push되어 동일한지만 확인할 것(원격 상태는 파일 대조 범위 밖).
- 검사축: 매니페스트 내부 참조 일관성

## 기각된 발견

- 없음. 두 감사자의 발견 18건(static 9 + infra 9)에 대해 인용된 `파일:줄`을 전부 `Read`/`Grep`으로 열어 대조했고, 인용 문자열이 실재하지 않거나 파일이 없는 경우는 없었다. 아래 3건은 줄 번호만 어긋나 실제 값으로 교정해 채택했다.
  - static "원격 kustomize base 3곳의 patches.target" — `metrics-server/kustomization.yaml:9-13,19-23` → 실제 `:10-17,22-30`
  - static "redis/rabbitmq/busybox 이미지" — `grafana.yaml:44` → 실제 `:43`, `prometheus.yaml:164` → 실제 `:163`
  - static "ssl-certs hostPath" — `cluster-autoscaler.yaml:176-182` → 실제 `:175-182`

## 커버리지

| 축 | 담당 | 상태 | 발견 |
| --- | --- | --- | --- |
| 1 노드 라벨 전파 사슬 | manifest-infra-crosschecker | 검사함 | 0 |
| 2 CP 테인트 ↔ DaemonSet toleration | manifest-infra-crosschecker | 검사함 | 0 |
| 3 Cluster Autoscaler 3중 정합 + 인증 구조 | manifest-infra-crosschecker | 검사함 | 1 |
| 4 리전 하드코딩 ↔ terraform region/tfvars | manifest-infra-crosschecker | 검사함 | 0 |
| 5 버전 정합 | manifest-infra-crosschecker | 검사함 | 1 |
| 6 hostPath ↔ EBS·마운트·디렉토리 생성 주체 | manifest-infra-crosschecker | 검사함 | 3 |
| 7 파드 requests 합계 ↔ 인스턴스 allocatable | manifest-infra-crosschecker | 검사함 | 2 |
| 8 네트워크(NodePort·SG·ALB·VXLAN·NACL) | manifest-infra-crosschecker | 검사함 | 2 |
| 9 RBAC 완결성 | manifest-static-auditor | 검사함 | 1 |
| 10 Namespace 존재 전제·적용 순서 의존 | manifest-static-auditor | 검사함 | 1 |
| 11 YAML 멀티도큐먼트·kustomize patches·이미지 태그 | manifest-static-auditor | 검사함 | 4 |
| 12 setup.txt 절차 정확성 | manifest-static-auditor | 검사함 | 2 |
| 매니페스트 내부 참조 일관성 | manifest-static-auditor | 검사함 | 1 |

- `발견` 열은 각 축에 걸린 **채택 건수**다. 여러 축에 걸친 병합 항목(원격 base 3종 = 축 5·9·11, ssl-certs = 축 6·11)은 해당 축마다 1건으로 세었으므로 열의 합(18)은 채택 총계 15건과 다르다. `## 요약`과 `집계:`의 15건이 고유 건수다.
- 축 1·2·4는 두 감사자 모두 발견 0건이라고 보고했고, 심판이 직접 스팟체크했다 — 축 1은 `cardinal.io/role` 전수 Grep(매니페스트 17곳)과 `control-plane/user_data.sh.tftpl:50-51`·`system-node/user_data.sh.tftpl:86`·`app-asg/main.tf:16`의 node-labels 전달, 축 2는 `control-plane/user_data.sh.tftpl:40-51`의 InitConfiguration에 `taints:` 부재와 `node-exporter.yaml:24-27`의 toleration, 축 4는 리전/AZ 문자열 전수 Grep(`cluster-autoscaler.yaml:165` 한 건, `terraform/variables.tf:4`와 일치)으로 확인했고 **반증을 찾지 못해 `검사함`을 유지**한다.

## 미해결 gap

- 원격 kustomize base 3종(argo-cd v3.4.5 / ingress-nginx v1.15.1 / metrics-server v0.8.0)의 본문은 리포지토리 밖에 있어, 이 리뷰의 정적 대조 범위에서 patch 매칭·SA/RBAC 포함·k8s 1.34 API 호환을 확정할 수 없다. `## 정보`의 해당 항목에 판정 보류로 남겼다. 확정하려면 apply 전 각 디렉토리에서 `kustomize build .`을 1회 실행해야 하며 이는 이 리뷰의 도구 범위 밖이다(kubectl/kustomize/terraform 실행 없음).
- 축 7의 allocatable 추정치(약 7760Mi)와 calico-node의 CPU requests 250m은 kubeadm 기본 동작·AMI 내부 값에 근거한 추정이다. 인벤토리 파일에 근거가 없어 `확신도: 추정`으로 남겼고, CP 정적 파드 requests 650m도 동일하다. apply 후 `kubectl describe node`로 실측하면 축 7 두 항목의 등급이 바뀔 수 있다.
- ArgoCD `application.yaml:10`의 `repoURL`이 가리키는 GitHub `main` 브랜치 상태가 로컬 작업 트리와 동일한지는 확인하지 않았다(git status상 `manifest/app-node/application/` 등 5개 디렉토리가 untracked 상태다). 미push 상태로 ArgoCD를 띄우면 Application이 빈 경로를 보게 되지만, 원격 확인은 이 리뷰 범위 밖이라 발견으로 올리지 않았다.
- 두 감사자의 `## 커버리지` 절에는 검사한 파일 목록 필드가 없다. 축 1·2·4의 `검사함(이상 없음)`은 심판이 직접 스팟체크해 반증이 없음을 확인한 뒤 액면 그대로 인정했으며, 추론만으로 강등한 축은 없다.
- 프롬프트의 12축 배정은 기본 배정(축 1~8 = manifest-infra-crosschecker, 축 9~12 + 내부 참조 일관성 = manifest-static-auditor)과 동일해 그대로 따랐다. 라운드 번호는 프롬프트가 명시한 1/2을 사용했다.
- 심판의 `report.md` 쓰기가 하네스 정책으로 차단되어 리포트 전문을 최종 응답 텍스트로 반환했고, 오케스트레이터가 이 경로에 무변경 전사했다. 매니페스트·테라폼 소스는 하나도 수정하지 않았다.

---

판정: PASS
집계: 치명 0 / 경고 5 / 정보 10
