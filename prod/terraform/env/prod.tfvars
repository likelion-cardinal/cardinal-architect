env = "prod"

# 노드 공용 커스텀 AMI (2026-07-22 빌드)
#   AL2023 x86_64 / k8s 1.34.9 / containerd 2.2.5 / Calico 3.32.1(VXLAN=Always)
#   루트 10GiB로 구움 — 실제 노드 크기는 각 모듈의 root_volume_size(30)가 결정
node_ami_id = "ami-0c32cc5a0cd32fe2c"

# App ASG 노드를 ALB Target Group에 등록한다. 30080에 응답하는 파드가 이미 떠 있어야
# ELB 헬스체크를 통과한다(빈 상태로 켜면 ASG가 노드를 5분마다 교체한다).
#
# !!! TODO(2026-07-28): 최초 구축 중이라 일부러 false로 내려둠. 반드시 true로 되돌릴 것 !!!
#   지금 false인 이유: state가 비어 있어 클러스터부터 새로 올린다. 30080을 여는 주체가
#   ingress-nginx Service(NodePort)라, 컨트롤러 배포 전에는 healthy가 될 방법이 없다.
#   되돌리는 순서:
#     1. 이 값 false로 apply → 클러스터 구축
#     2. manifest/app-node/ingress-nginx/ 배포 (setup.txt 1~4 순서 준수)
#     3. app 노드에서 `curl -I localhost:30080` → 404라도 응답 확인 (matcher가 200-404)
#     4. 이 값 true로 apply
#   3번을 건너뛰지 말 것: 이미 떠 있는 노드는 grace_period 300초가 남아 있지 않아,
#   응답이 없으면 TG 판정만으로 약 45초 만에 교체된다(신규 구축보다 빨리 깨진다).
#   true로 되돌리는 건 ASG in-place 업데이트라 노드 교체는 일어나지 않는다.
register_app_nodes_to_alb = true

# 도메인 구매 후 주석을 풀면 dns 모듈(Hosted Zone + ACM 인증서)이 생성된다.
# 비어 있는 동안에는 모듈 전체가 건너뛰어져 Hosted Zone 요금($0.50/월)도 발생하지 않는다.
# 순서: 구매 → apply → `terraform output route53_name_servers` → 등록기관에 NS 4개 입력
#       → 전파 후 wait_for_certificate_validation = true 로 apply
domain_name = "2026cardinal.com"
wait_for_certificate_validation = true

# 기본값(variables.tf)을 그대로 쓰면 아래는 생략 가능.
# region               = "ap-northeast-2"
# vpc_cidr             = "10.20.0.0/16"
# azs                  = ["ap-northeast-2a", "ap-northeast-2c"]
# public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
# private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]
