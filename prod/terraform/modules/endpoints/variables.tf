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
  description = "Interface Endpoint를 생성할 VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "엔드포인트 SG의 443 인바운드 허용 대상 (VPC 내부)"
  type        = string
}

variable "subnet_ids" {
  description = "Endpoint ENI를 둘 서브넷 목록. 비용상 compute_az 한 곳만 권장(EP는 AZ×개수로 시간당 과금)"
  type        = list(string)
}
