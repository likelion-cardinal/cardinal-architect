variable "project" {
  description = "프로젝트명 (네이밍·태그 prefix)"
  type        = string
}

variable "env" {
  description = "환경 (prod/dev)"
  type        = string
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "SG/NACL을 생성할 VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. NAT 인바운드·NACL 내부 허용에 사용"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public NACL을 연결할 Public 서브넷 ID 목록"
  type        = list(string)
}

variable "blocked_cidrs" {
  description = "NACL에서 deny할 악성 IP/CIDR 목록. ALB Access Log 분석 결과를 여기에 추가"
  type        = list(string)
  default     = []
}

variable "nodeport_from" {
  description = "쿠버네티스 NodePort 시작 포트 (ALB→Worker)"
  type        = number
  default     = 30000
}

variable "nodeport_to" {
  description = "쿠버네티스 NodePort 끝 포트"
  type        = number
  default     = 32767
}
