variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "프로젝트명"
  type        = string
  default     = "cardinal"
}

variable "env" {
  description = "환경 (prod/dev)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 대역"
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "사용할 가용영역. ALB 요구로 2개 이상"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "AZ별 Public 서브넷 CIDR (azs 순서)"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "AZ별 Private 서브넷 CIDR (azs 순서)"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.12.0/24"]
}

# private_subnet_cidrs[0](10.20.10.0/24) 안의 주소여야 한다. .0~.3과 .255는 AWS 예약.
variable "control_plane_private_ip" {
  description = "CP 고정 사설 IP. 교체 후에도 워커가 같은 주소로 붙게 해 복구를 가능하게 한다"
  type        = string
  default     = "10.20.10.10"
}

# Ingress Controller 배포 전에 켜면 ELB 헬스체크 실패로 App 노드가 계속 교체된다.
variable "register_app_nodes_to_alb" {
  description = "App Worker ASG를 ALB Target Group에 등록할지. 클러스터에 Ingress Controller를 올린 뒤 true로 바꾼다"
  type        = bool
  default     = false
}

variable "alb_log_retention_days" {
  description = "공유 버킷 alb-logs/ 보존 기간(일). 축제 후 IP 분석이 끝나면 쌓아둘 이유가 없다"
  type        = number
  default     = 90
}

variable "etcd_backup_retention_days" {
  description = "공유 버킷 etcd/ 스냅샷 보존 기간(일)"
  type        = number
  default     = 30
}

variable "mysql_backup_retention_days" {
  description = "공유 버킷 mysql/ 덤프 보존 기간(일). EBS는 논리적 삭제(DELETE·DROP)를 막지 못해 이 덤프가 유일한 복구 수단이다"
  type        = number
  default     = 30
}

variable "blocked_cidrs" {
  description = "Public NACL에서 deny할 악성 IP/CIDR 목록 (ALB 로그 분석 결과)"
  type        = list(string)
  default     = []
}

# 도메인은 나중에 사서 붙여도 되므로 기본값을 빈 문자열로 둔다.
# 비어 있으면 dns 모듈 전체가 생성되지 않고(Hosted Zone 월 $0.50도 안 나간다),
# 도메인 구매 후 이 값만 채우면 Zone·인증서가 따라 만들어진다.
variable "domain_name" {
  description = "구매한 apex 도메인 (예: cardinal.kr). 비우면 dns 모듈을 건너뛴다"
  type        = string
  default     = ""
}

variable "wait_for_certificate_validation" {
  description = "ACM 발급 완료까지 apply를 대기할지. 가비아 네임서버를 Route53 NS로 바꾸고 전파된 뒤 true로 올린다"
  type        = bool
  default     = false
}

# k8s 사전 설치 커스텀 AMI. CP·System·App 워커가 모두 이 하나를 공유한다
# (차이는 부팅 후 kubeadm init이냐 join이냐뿐).
# 기본값을 두지 않아 var-file 없이 apply하면 즉시 실패한다 —
# 실수로 맨 AL2023이 떠서 클러스터에 붙지 않는 상황을 막기 위함.
variable "node_ami_id" {
  description = "노드 공용 커스텀 AMI ID (k8s·containerd·Calico 사전 설치)"
  type        = string
}
