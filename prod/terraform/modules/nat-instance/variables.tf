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

variable "subnet_id" {
  description = "NAT를 배치할 Public 서브넷 ID (compute_az의 public 서브넷)"
  type        = string
}

variable "security_group_id" {
  description = "NAT용 Security Group ID (security 모듈의 nat_sg_id)"
  type        = string
}

variable "private_route_table_ids" {
  description = "0.0.0.0/0 → NAT 기본경로를 갱신할 Private 라우트 테이블 ID 목록"
  type        = list(string)
}

variable "instance_type" {
  description = "NAT 인스턴스 타입 (Free Tier 최소 x86)"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "NAT AMI ID. 비우면 최신 Amazon Linux 2023을 SSM 파라미터로 자동 조회"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "SSH 키페어 이름(선택). SSM로 접속하면 불필요"
  type        = string
  default     = ""
}
