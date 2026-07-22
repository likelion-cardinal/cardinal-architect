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

variable "ssm_parameter_path" {
  description = "노드가 접근할 SSM Parameter Store 경로 prefix (join 토큰 등). 실제 ARN은 이 경로 하위 전체(/*)로 스코프된다."
  type        = string
  default     = "kubeadm"
}

variable "etcd_backup_bucket_arn" {
  description = "etcd 스냅샷 백업용 공유 S3 버킷 ARN. 비우면 S3 접근 정책을 생략한다(버킷 모듈 생성 후 root에서 주입)."
  type        = string
  default     = ""
}
