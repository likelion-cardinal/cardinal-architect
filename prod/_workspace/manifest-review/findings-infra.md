# findings-infra — 매니페스트 ↔ 테라폼 인프라 교차 대조 (축 1~8)

> 라운드 1/2. 서브에이전트의 Write가 하네스 정책으로 차단되어, 에이전트 반환 본문을 오케스트레이터가 무변경 전사함.
>
> 축별 건수: 축 1: 0건 / 축 2: 0건 / 축 3: 1건 / 축 4: 0건 / 축 5: 1건 / 축 6: 3건 / 축 7: 2건 / 축 8: 2건
> 등급 집계: 치명 0 / 경고 4 / 정보 5

## 변수 전개표 (축 1·3·4 판정 기반)

`terraform/variables.tf:10` project 기본값 `"cardinal"` + `terraform/env/prod.tfvars:1` `env = "prod"`
→ 모든 모듈의 `local.name = "${var.project}-${var.env}"` 최종값 = **`cardinal-prod`**
(`app-asg/main.tf:2`, `iam/main.tf:2`, `system-node/main.tf:2`, `security/main.tf:2`, `alb/main.tf:2`, `vpc/main.tf:2` 모두 동일 조립식. root `main.tf`는 어느 모듈에도 다른 project/env를 넘기지 않는다.)

`node_labels` 최종값 (root `main.tf`에 오버라이드 없음 → 모듈 기본값이 최종값):
- control-plane `cardinal.io/role=control-plane` (`control-plane/variables.tf:118`)
- system-node `cardinal.io/role=system` (`system-node/variables.tf:83`)
- app-asg `cardinal.io/role=application` (`app-asg/variables.tf:113`)

`region` = `ap-northeast-2` (`variables.tf:4`, tfvars:32 주석 처리) · `alb.target_port` = `30080` (`alb/variables.tf:68`, root `main.tf:150` 주석 처리) · app ASG min/max = 1/3 (`main.tf:186-187`) · `data_volume_size` = 20 (`main.tf:115`)

## 커버리지

**축 1 (노드 라벨 전파 사슬): 검사함(이상 없음).** 매니페스트 라벨 전제 전수 — `redis.yaml:21`, `rabbitmq.yaml:19`, `mysql.yaml:36`, `prometheus.yaml:156`, `grafana.yaml:36`, `cluster-autoscaler.yaml:142`, `argocd/kustomization.yaml:13,20`(=system), `ingress-nginx/daemonset.yaml:37`, `ingress-nginx/kustomization.yaml:41`, `metrics-server/kustomization.yaml:30`, `backend.yaml:31`, `frontend.yaml:24`(=application), `node-exporter.yaml:22`(=`cardinal.io/role` Exists). 공급·전파 3단 모두 확인: 모듈 변수 기본값 → `templatefile()` 인자(`system-node/main.tf:24`, `app-asg/main.tf:16`, `control-plane/main.tf:16`) → kubelet 인자(`system-node/user_data.sh.tftpl:86`, `app-asg/user_data.sh.tftpl:37`의 `KUBELET_EXTRA_ARGS ... --node-labels=${node_labels}`, `control-plane/user_data.sh.tftpl:50-51`의 v1beta4 name/value). 키·값이 문자 그대로 일치하고 `cardinal.io/` 접두사라 NodeRestriction에 걸리지 않는다.

**축 2 (CP 테인트 ↔ toleration): 검사함(이상 없음).** `control-plane/user_data.sh.tftpl:38-60`의 InitConfiguration에 `taints:`가 없어 kubeadm 기본 `node-role.kubernetes.io/control-plane:NoSchedule`만 걸린다. 전 노드 대상 DaemonSet은 node-exporter 하나뿐이며 동일 키/effect toleration(`:25-27`)과 Exists affinity(`:22`)를 함께 가져 CP에도 뜬다. ingress-nginx DaemonSet은 application nodeSelector라 대상 아님.

**축 3 (CA 3중 정합 + 인증 구조): 검사함(발견 1건).** 3중 문자열 **일치** — ① `cluster-autoscaler.yaml:156` `...tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/cardinal-prod` ② ASG 태그 `app-asg/main.tf:22-23` 전개 → `.../enabled=true`, `.../cardinal-prod=owned` ③ IAM 조건 키 `iam/main.tf:91` 전개 → `autoscaling:ResourceTag/k8s.io/cluster-autoscaler/cardinal-prod=owned`. auto-discovery는 태그 키만 보므로 `propagate_at_launch=false`(`app-asg/main.tf:120`)는 무관. 권한 배치도 정합(CA는 system 노드 고정, system 노드가 공용 프로파일 장착 `main.tf:103`, `iam/variables.tf:26` 기본 true로 정책 실제 부착). IMDS hop limit 2는 3개 노드 그룹 전부(`system-node/main.tf:47`, `app-asg/main.tf:50`, `control-plane/main.tf:61`).

**축 4 (리전): 검사함(이상 없음).** 매니페스트 리전 하드코딩은 `cluster-autoscaler.yaml:164-165`의 `AWS_REGION: ap-northeast-2` 하나뿐(전수 grep). `variables.tf:4` 기본값·`provider.tf:2`·`prod.tfvars:32`(주석)와 일치. AZ 전제 매니페스트 없음.

**축 5 (버전 정합): 검사함(발견 1건).** CA `v1.34.5`(`:149`) ↔ 클러스터 `v1.34.9`(`control-plane/variables.tf:76`, `prod.tfvars:4`) 마이너 동일 — 정합. Prometheus/Grafana/node-exporter/mysql/redis/rabbitmq는 k8s 버전 의존 없음. 원격 base 3종만 판정 보류(아래 정보).

**축 6 (hostPath ↔ 디스크·마운트·생성 주체): 검사함(발견 3건).** hostPath 전수: `/mnt/data/{mysql,prometheus,grafana,rabbitmq}` 모두 `DirectoryOrCreate`, 그 외 node-exporter의 `/proc`·`/sys`·`/`와 CA의 `/etc/ssl/certs/ca-bundle.crt`(AL2023 기본 제공, 이상 없음). 용량 계산: 20GiB − ext4 5% 예약 ≈ 가용 18GiB; Prometheus 5GB(base-2=5GiB)+WAL ≈ 5.5GiB, Grafana ≈0.5, RabbitMQ ≈0.5 → MySQL 몫 약 11.5GiB. 즉각 고갈 없음.

**축 7 (requests ↔ allocatable): 검사함(발견 2건).** system CPU 1235m/2000m(62%), mem req 3040Mi — 여유. limits 7488Mi가 allocatable 추정 7760Mi의 96%. app 노드 HPA min 기준 1110m/1986Mi, HPA max(1900m)도 3노드 잔여 4820m 안. `min_size=1`이라 app 파드가 처음부터 못 뜨는 상황은 없음. 가정: kubeadm은 kube/system-reserved 미설정 → allocatable ≈ capacity(약 7860Mi) − evictionHard 100Mi; DaemonSet은 node-exporter 10m/32Mi(실측) + calico-node 250m(AMI 기본값, 추정) + kube-proxy 0m.

**축 8 (네트워크): 검사함(발견 2건).** NodePort 30080/30443(`ingress-nginx/kustomization.yaml:29,32`)은 30000-32767 범위(`security/variables.tf:41,47`) 안이고 ALB SG 출처로만 인바운드 개방(`security/main.tf:139-148`), ALB 아웃바운드도 대응(`:56-65`). TG는 30080/HTTP/`/`+`200-404`(`alb/main.tf:41-57`)로 nodePort·nginx 기본 404와 정합. 노드 mesh는 cp/system/app 9조합 `ip_protocol="-1"`(`security/main.tf:127-136`)이라 6443·10250·2379-2380·NodePort·**VXLAN 4789/UDP**·BGP 179 전부 포함. NACL은 public 서브넷 전용(노드는 private)이며 ephemeral 1024-65535 tcp/udp(`:221-241`)·VPC 전체(`:243-250`)·아웃바운드 전체(`:253-260`)로 리턴 트래픽 차단 없음.

---

## 발견

### [경고] CA용 AWS 권한이 노드 공용 인스턴스 프로파일에 있어 app 노드 파드에도 그대로 노출된다

근거: manifest/system-node/cluster-autoscaler/cluster-autoscaler.yaml:139 — "serviceAccountName: cluster-autoscaler" (SA 정의 `:1-7`에 IRSA 어노테이션이 없다 = AWS 자격을 노드 인스턴스 프로파일에서만 얻는 구조)
대조: terraform/main.tf:175 — "instance_profile_name = module.iam.instance_profile_name" (app_asg 인자. system_node `:103`, control_plane `:77`과 **동일한 단일 프로파일**이며 그 Role에 `iam/main.tf:78-95`의 SetDesiredCapacity·TerminateInstanceInAutoScalingGroup, `:25-37`의 SSM join 토큰 Get/Put, `:44`의 `kms:Decrypt`가 모두 붙는다)
영향: apply는 성공하고 CA도 정상 동작한다(축 3의 기능 정합은 문제없음). 문제는 노출 범위다 — `app-asg/main.tf:50`의 hop limit 2로 app 노드의 모든 파드가 IMDS에 도달하며, 그 노드에는 인터넷에 직접 노출되는 ingress-nginx·backend·frontend가 뜬다. 하나라도 SSRF/RCE가 나면 `ssm:GetParameter`+`kms:Decrypt`로 join 커맨드 전문(SecureString)을 읽어 임의 노드를 클러스터에 붙이거나 app ASG 인스턴스를 종료할 수 있다.
확신도: 높음(확실) — 세 모듈이 같은 `module.iam.instance_profile_name`을 받는 것과 hop limit 2가 파일에 그대로 있고, IRSA/OIDC 설정은 인벤토리 어디에도 없다.
권고: iam 모듈을 역할별로 분리해 CA·SSM Put 권한은 system/CP 프로파일에만 남기고, app-asg에는 join 토큰 읽기(`ssm:GetParameter`+`kms:Decrypt`)만 가진 최소 프로파일을 붙인다. app 노드는 파드가 IMDS를 쓸 이유가 없으므로 `http_put_response_hop_limit`을 1로 되돌린다(system 노드만 2 유지).
검사축: 3

### [정보] 원격 base 3종(argo-cd v3.4.5 / metrics-server v0.8.0 / ingress-nginx v1.15.1)의 k8s 1.34 지원 범위를 로컬 근거로 확정할 수 없다

근거: manifest/system-node/argocd/kustomization.yaml:4 — "- https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.5/manifests/install.yaml" (동종으로 metrics-server/kustomization.yaml:5의 v0.8.0, ingress-nginx/kustomization.yaml:5의 controller-v1.15.1)
대조: terraform/modules/control-plane/variables.tf:76 — "default     = \"v1.34.9\"" (prod.tfvars:4의 "k8s 1.34.9 / containerd 2.2.5 / Calico 3.32.1(VXLAN=Always)"와 동일)
영향: 세 base 중 하나라도 1.34에서 제거된 API를 쓰면 해당 컴포넌트만 apply/기동에 실패한다. 지원 범위 안이면 아무 일도 없다. 같은 축의 CA는 `v1.34.5`로 클러스터 마이너와 정확히 맞아 이 위험이 없다.
확신도: 낮음(추정) — 원격 매니페스트 본문이 없고 네트워크 조회·kustomize build를 하지 않는다. 세 태그 모두 1.34 릴리스 이후로 보인다는 정황 판단까지만 가능.
권고: 각 프로젝트 호환 매트릭스에서 1.34 포함 여부만 확인하고 결과를 setup.txt에 "검증한 클러스터 버전: 1.34.9"로 남긴다. 매니페스트 값 변경 근거는 없다.
검사축: 5

### [경고] 데이터 EBS 부착이 60초 안에 안 보이면 user_data가 마운트를 조용히 건너뛰고 hostPath가 루트 EBS로 떨어진다

근거: manifest/system-node/mysql/mysql.yaml:110-112 — "hostPath:" / "path: /mnt/data/mysql" / "type: DirectoryOrCreate" (prometheus.yaml:210-212, grafana.yaml:100-102, rabbitmq.yaml:84-86 동일 — 경로가 없으면 kubelet이 만들어 마운트 실패를 감지하지 못한다)
대조: terraform/modules/system-node/user_data.sh.tftpl:26 — "for _ in $(seq 1 30); do" (2초×30 = 최대 60초만 대기하고, `:35`의 `if [ -n "$DATA_DEV" ]; then` 블록에 else가 없어 미검출 시 마운트·서브디렉토리 생성·경고까지 전부 건너뛴 채 정상 종료한다)
영향: 경합에서 지면 `/mnt/data` 미마운트 상태로 join까지 성공하고, `DirectoryOrCreate`가 30GiB 루트 EBS(`system-node/variables.tf:53`) 위에 같은 경로를 만들어 MySQL·Prometheus·Grafana·RabbitMQ 데이터가 전부 루트로 간다. `terraform/main.tf:112-113`이 명시적으로 금지한 상태가 무증상으로 성립하며 AMI 교체/replacement 시 전량 소실된다. `aws_ebs_volume`/`aws_volume_attachment`가 인스턴스 생성 **이후**에 만들어지는 의존 순서(`system-node/main.tf:73,86`)라 부팅 직후 창에서 경합이 발생하고, 스크립트가 실패로 끝나지 않아 로그에 WARNING 한 줄도 남지 않는다.
확신도: 중간(추정) — 코드 경로·의존 순서는 파일로 확정되나, 실제 60초 초과 여부는 apply 없이 확정 불가. 통상 부착은 10~20초라 대개 성공하지만 실패가 조용하다는 구조가 문제다.
권고: `:34` 뒤에 `if [ -z "$DATA_DEV" ]; then echo "FATAL: data EBS not attached" >&2; exit 1; fi`를 두어 join 전에 죽게 하고 대기를 30회→90회로 늘린다. 매니페스트 쪽은 4개 hostPath의 `type`을 `Directory`로 바꾸면 경로 부재 시 Pending으로 드러난다.
검사축: 6

### [정보] `/mnt/data/rabbitmq`는 테라폼 user_data가 만들지 않는 경로다(생성 주체 계약 불일치)

근거: manifest/system-node/rabbitmq/rabbitmq.yaml:85 — "path: /mnt/data/rabbitmq" (`:83` 주석이 "mysql·prometheus·grafana 와 같은 데이터 EBS(/mnt/data)를 나눠 쓴다"고 선언)
대조: terraform/modules/system-node/user_data.sh.tftpl:47 — "mkdir -p ${mount_point}/mysql ${mount_point}/prometheus ${mount_point}/grafana" (rabbitmq 없음. chown도 `:49-50`의 prometheus 65534·grafana 472뿐이며 `terraform/main.tf:111`·`system-node/variables.tf:87,93`도 3개만 열거)
영향: 기동은 된다 — `DirectoryOrCreate`가 root:root 0755로 만들고 `rabbitmq.yaml:29-37`의 initContainer가 `runAsUser: 0`으로 chown하므로 권한 충돌도 없다. 남는 문제는 계약 드리프트로, 볼륨 소비자 목록이 테라폼(3개)과 실제(4개)로 갈라져 이후 볼륨 크기 산정·백업 대상 선정에서 rabbitmq가 누락될 수 있다. redis는 hostPath를 쓰지 않으므로 목록 제외가 맞다.
확신도: 높음(확실) — 양쪽 파일 내용이 그대로 어긋난다.
권고: `user_data.sh.tftpl:47` mkdir 목록에 `${mount_point}/rabbitmq` 추가 + `chown 999:999`. `terraform/main.tf:111`과 `system-node/variables.tf:87,93`의 열거에 RabbitMQ를 더한다.
검사축: 6

### [정보] 20GiB 단일 데이터 볼륨을 4개 컴포넌트가 쿼터 없이 공유한다 — MySQL 증가가 나머지를 동시에 끌어내린다

근거: manifest/system-node/prometheus-grafana/prometheus.yaml:177 — "- --storage.tsdb.retention.size=5GB" (`:176`의 `--storage.tsdb.retention.time=15d`와 병용. base-2 파싱이라 5GiB, 블록+WAL 포함 약 5.5GiB)
대조: terraform/main.tf:115 — "data_volume_size = 20" (`system-node/main.tf:70-79`의 20GiB gp3 하나를 mysql.yaml:111·prometheus.yaml:211·grafana.yaml:101·rabbitmq.yaml:85가 서브디렉토리로 나눠 쓴다. LVM/쿼터/개별 PV 없이 같은 ext4 — `user_data.sh.tftpl:37` `mkfs.ext4 -L cardinal-data`)
영향: 즉각 고갈은 없다. 20GiB − ext4 5% 예약(약 1.0GiB) ≈ 가용 18GiB, Prometheus 5.5 + Grafana 0.5 + RabbitMQ 0.5를 빼면 MySQL 몫 약 11.5GiB. 상한이 없어 MySQL이 이를 넘기면 같은 파일시스템의 Prometheus가 쓰기 실패로 죽고 Grafana(sqlite)·RabbitMQ(mnesia)도 동시에 깨진다. Prometheus 65534·Grafana 472로 비root 실행이라(prometheus.yaml:158, grafana.yaml:38) 5% root 예약분은 이들에게 쓸 수 없어 체감 여유는 더 작다.
확신도: 중간(추정) — 볼륨 크기·retention·공유 구조는 확실, MySQL 증가 속도에 달린 고갈 시점은 추정.
권고: node-exporter filesystem 메트릭으로 `/mnt/data` 80% 알람을 먼저 걸고, 여유가 필요하면 `data_volume_size`를 20→40으로 올리거나 MySQL 전용 EBS를 분리한다. Prometheus retention은 현행 유지가 적절하다.
검사축: 6

### [경고] system 노드 메모리 limit 합 7488Mi가 allocatable 추정치(약 7760Mi)의 96%다

근거: manifest/system-node/mysql/mysql.yaml:76-77 — "limits:" / "memory: 2Gi" (system 고정 파드는 mysql.yaml:36, prometheus.yaml:156, grafana.yaml:36, rabbitmq.yaml:19, redis.yaml:21, cluster-autoscaler.yaml:142, argocd/kustomization.yaml:13,20으로 확정)
대조: terraform/modules/system-node/variables.tf:33 — "description = \"System Worker 타입 (ArgoCD·Prom·Graf·MySQL ≈7Gi → 8Gi)\"" (`:35` 기본값 `m7i-flex.large` = 2 vCPU/8GiB. 이 산정 근거에 RabbitMQ(limit 1Gi)·Redis(384Mi)가 빠져 있는데 둘 다 이번에 새로 추가된 디렉토리다)
영향: **CPU는 여유가 있어 Pending은 없다.** requests = argocd 325m(150+100+50+25; applicationset/notifications/dex는 `kustomization.yaml:92,109,126`의 `replicas: 0`이라 0m) + CA 100m + prometheus 100m + grafana 50m + mysql 250m + rabbitmq 100m + redis 50m = 975m, DaemonSet(node-exporter 10m, calico-node 250m 추정) 포함 **1235m / 2000m = 62%**. 메모리 requests도 448+128+512+256+1024+512+128+32 = **3040Mi**로 여유. 문제는 limit — 2048+1024+1024+1024+384+512+1344+128 = **7488Mi** 대 allocatable 약 **7760Mi**(capacity 약 7860Mi − evictionHard 100Mi). kubeadm이 kube/system-reserved를 설정하지 않아 kubelet·containerd·systemd의 500~800Mi가 이 안에서 경합하므로, 파드들이 limit 근처로 오르면 eviction이 시작되고 Burstable QoS인 MySQL·Prometheus가 우선 축출돼 hostPath 파드가 재시작된다. CoreDNS 2레플리카(70Mi×2)가 떨어지면 여유는 더 준다.
확신도: 중간(추정) — 합계 산술과 인용은 확실. 실사용이 limit까지 오르는지, allocatable 실측치는 apply 전이라 kubeadm 기본 동작 기반 추정.
권고: (a) `system-node/variables.tf:35`를 `m7i-flex.xlarge`(4 vCPU/16GiB)로 올리고 `:33` 산정 문구에 RabbitMQ·Redis 반영, 또는 (b) limit 합을 allocatable 80%(약 6200Mi) 이하로 — mysql 2Gi→1536Mi, grafana 1Gi→512Mi, rabbitmq 1Gi→768Mi가 손해가 가장 적다. 어느 쪽이든 kubelet에 `--system-reserved`/`--kube-reserved`(예: cpu=200m,memory=512Mi)를 걸어 호스트 몫을 빼두는 편이 정확하다.
검사축: 7

### [정보] CP는 t3.medium standard 크레딧(baseline 400m)인데 상주 파드 CPU requests 합이 910m다

근거: manifest/all/node-exporter/node-exporter.yaml:24-27 — "tolerations:" / "- key: node-role.kubernetes.io/control-plane" / "operator: Exists" / "effect: NoSchedule" (`:22`의 Exists affinity와 합쳐져 CP에도 반드시 스케줄. requests는 `:42-43`의 cpu 10m/32Mi)
대조: terraform/modules/control-plane/main.tf:50-55 — "dynamic \"credit_specification\" {" / "for_each = startswith(var.instance_type, \"t\") ? [1] : []" / "cpu_credits = \"standard\"" (`variables.tf:35` 기본값 t3.medium에 걸리며 `main.tf:43` 주석이 baseline을 "t3.medium = 2 vCPU × 20% = 400m"로 스스로 명시)
영향: 스케줄링은 문제없다 — 정적 파드 650m(apiserver 250 + controller-manager 200 + scheduler 100 + etcd 100) + calico-node 250m(추정) + node-exporter 10m = **910m / 2000m = 46%**. 다만 standard 모드는 크레딧 소진 시 실사용이 400m로 쓰로틀되므로, CA가 app 노드를 3대까지 올려 apiserver watch 부하가 늘거나 etcd 컴팩션이 겹치면 apiserver 응답이 느려진다. `main.tf:45`의 "유휴 100~150m" 전제는 피크에 적용되지 않는다.
확신도: 낮음(추정) — 정적 파드 requests는 kubeadm 기본값이라 인벤토리 파일로 인용 불가(AMI 내부). node-exporter 몫과 크레딧 설정만 파일로 확정.
권고: 지금 바꿀 필요는 없다. 피크 전 CPUCreditBalance만 확인하고 소진 추세면 `control-plane/variables.tf:35`를 `m7i-flex.large`로 올린다(그 순간 `main.tf:50`의 dynamic 블록이 자동으로 빠진다). unlimited 전환은 `main.tf:42-46`의 정산 사유상 선택지가 아니다.
검사축: 7

### [경고] App 노드가 ALB Target Group에 등록되지 않아 매니페스트가 전제하는 ALB→NodePort 경로가 성립하지 않는다

근거: manifest/app-node/ingress-nginx/kustomization.yaml:29 — "nodePort: 30080" (`:24` `type: NodePort`, `:32` `nodePort: 30443`. setup.txt:26이 "ALB 타겟그룹 port 30080 ←→ Service nodePort 30080 (http)"로 이 경로를 전제하며, application/ingress.yaml과 prometheus-grafana/ingress.yaml 모두 이 경로로만 외부 노출된다)
대조: terraform/env/prod.tfvars:22 — "register_app_nodes_to_alb = false" (terraform/main.tf:192 "target_group_arns = var.register_app_nodes_to_alb ? [module.alb.target_group_arn] : []" → app ASG에 TG가 붙지 않는다. system 노드는 ASG가 아니라 어떤 TG에도 등록되지 않는다 — `system-node/main.tf:33-64`에 TG 참조 없음)
영향: apply는 성공하고 파드도 정상 기동하지만 80 리스너(`alb/main.tf:91-98`의 forward)가 **타깃 0개 TG**로 넘겨 모든 외부 요청이 503이 된다. backend·frontend·grafana 어느 것도 외부 접근 불가. `prod.tfvars:11-21`이 의도된 임시 상태이며 복구 절차까지 적어둔 사안이라 설계 오류는 아니지만, 이 단계를 잊으면 서비스가 통째로 접속 불가로 남는다(그 경우 실질 영향은 치명급). 반대로 컨트롤러 배포 전에 true로 올리면 tfvars:19-20 경고대로 노드가 약 45초마다 교체된다.
확신도: 높음(확실) — tfvars 값과 root main.tf 삼항 연산이 그대로 읽힌다.
권고: ingress-nginx 배포 후 app 노드에서 30080 응답을 확인한 직후 `prod.tfvars:22`를 `true`로 바꿔 apply한다(ASG in-place 업데이트라 노드 교체 없음). `prod.tfvars:11`의 TODO 제거까지 절차에 포함시킨다. 매니페스트 수정은 불필요.
검사축: 8

### [경고] ALB 443 리스너가 생성되지 않는 상태인데 매니페스트는 "ALB가 TLS를 종료한다"를 전제로 Secure 쿠키를 강제한다

근거: manifest/app-node/application/configmap.yaml:43 — "JWT_COOKIE_SECURE: \"true\"" (`:40` 주석이 "ALB 가 TLS 를 종료하고 뒤로는 평문 HTTP 다. 브라우저 입장에서는 https 이므로 true 로 둔다"로 전제를 명시. ingress.yaml:10의 `nginx.ingress.kubernetes.io/ssl-redirect: "false"`도 같은 전제)
대조: terraform/main.tf:146 — "enable_https    = var.domain_name != \"\" && var.wait_for_certificate_validation" (prod.tfvars:28-29에서 두 값이 모두 주석 처리, `variables.tf:80` 기본값 `""` → **enable_https=false** → `alb/main.tf:102-103`의 `count`로 443 리스너 미생성, dns 모듈도 `main.tf:123`의 count 0으로 생략)
영향: 외부 접점이 `http://<alb-dns-name>/` 하나뿐이 된다. 브라우저는 평문 HTTP 응답의 `Secure` 쿠키를 저장하지 않으므로 로그인은 200을 받고도 세션이 남지 않아 즉시 로그아웃 상태가 되며, 에러 로그가 없어 원인 파악이 어렵다. ssl-redirect=false는 현 상태에서 옳다(true였다면 존재하지 않는 443으로 무한 루프). Grafana는 `GF_SERVER_ROOT_URL`이 `%(protocol)s`(grafana.yaml:66)라 영향 없다.
확신도: 높음(확실) — tfvars 주석 상태·기본값·count 조건이 모두 파일에 있고 전개 결과가 일의적이다.
권고: 도메인 취득 전까지 `configmap.yaml:43`을 `"false"`로 두고, 도메인 구매 후 `prod.tfvars:28-29` 두 줄을 풀어 443 리스너 생성을 확인한 뒤 `true`로 되돌린다. 되돌릴 때 `configmap.yaml:41-42`가 요구하는 `server.forward-headers-strategy` 설정도 함께 확인한다.
검사축: 8

---

## 요약

축 1: 0건 / 축 2: 0건 / 축 3: 1건 / 축 4: 0건 / 축 5: 1건 / 축 6: 3건 / 축 7: 2건 / 축 8: 2건
치명 0 / 경고 4 / 정보 5
