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

variable "blocked_cidrs" {
  description = "Public NACL에서 deny할 악성 IP/CIDR 목록 (ALB 로그 분석 결과)"
  type        = list(string)
  default     = []
}

# k8s 사전 설치 커스텀 AMI. CP·System·App 워커가 모두 이 하나를 공유한다
# (차이는 부팅 후 kubeadm init이냐 join이냐뿐).
# 기본값을 두지 않아 var-file 없이 apply하면 즉시 실패한다 —
# 실수로 맨 AL2023이 떠서 클러스터에 붙지 않는 상황을 막기 위함.
variable "node_ami_id" {
  description = "노드 공용 커스텀 AMI ID (k8s·containerd·Calico 사전 설치)"
  type        = string
}
