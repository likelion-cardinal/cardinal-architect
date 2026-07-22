env = "prod"

# 노드 공용 커스텀 AMI (2026-07-22 빌드)
#   AL2023 x86_64 / k8s 1.34.9 / containerd 2.2.5 / Calico 3.32.1(VXLAN=Always)
#   루트 10GiB로 구움 — 실제 노드 크기는 각 모듈의 root_volume_size(30)가 결정
node_ami_id = "ami-0c32cc5a0cd32fe2c"

# 도메인 구매 후 주석을 풀면 dns 모듈(Hosted Zone + ACM 인증서)이 생성된다.
# 비어 있는 동안에는 모듈 전체가 건너뛰어져 Hosted Zone 요금($0.50/월)도 발생하지 않는다.
# 순서: 구매 → apply → `terraform output route53_name_servers` → 등록기관에 NS 4개 입력
#       → 전파 후 wait_for_certificate_validation = true 로 apply
# domain_name = "2026cardinal.com"
# wait_for_certificate_validation = true

# 기본값(variables.tf)을 그대로 쓰면 아래는 생략 가능.
# region               = "ap-northeast-2"
# vpc_cidr             = "10.20.0.0/16"
# azs                  = ["ap-northeast-2a", "ap-northeast-2c"]
# public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
# private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]
