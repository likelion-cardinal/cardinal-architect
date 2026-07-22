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
  description = "Target Group을 만들 VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "ALB를 배치할 Public 서브넷 ID 목록. ALB는 최소 2개 AZ를 요구한다"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "ALB는 서로 다른 AZ의 서브넷이 2개 이상 필요하다."
  }
}

variable "security_group_id" {
  description = "ALB Security Group ID (security 모듈의 alb_sg_id)"
  type        = string
}

variable "enable_https" {
  description = <<-EOT
    443 리스너 생성 여부. certificate_arn의 값으로 판단하지 않는 이유는,
    ACM ARN이 apply 후에야 정해지는 값이라 count/dynamic의 조건으로 쓸 수 없기 때문이다.
    false면 80이 Target Group으로 직접 forward한다(도메인·인증서 준비 전 임시 상태).
  EOT
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "443 리스너에 물릴 ACM 인증서 ARN. enable_https=true일 때 필수이며, 인증서가 ISSUED가 아니면 리스너 생성이 실패한다"
  type        = string
  default     = ""
}

variable "access_log_bucket" {
  description = "Access Log를 쓸 공유 S3 버킷 이름. 비우면 로그를 끈다"
  type        = string
  default     = ""
}

variable "access_log_prefix" {
  description = "Access Log prefix. 공유 버킷을 etcd 백업과 나눠 쓰는 기준"
  type        = string
  default     = "alb-logs"
}

variable "target_port" {
  description = "워커 NodePort. Ingress Controller가 여는 포트와 일치해야 하고 security 모듈의 nodeport 범위 안이어야 한다"
  type        = number
  default     = 30080

  validation {
    condition     = var.target_port >= 30000 && var.target_port <= 32767
    error_message = "NodePort 범위(30000-32767) 안이어야 한다."
  }
}

variable "health_check_path" {
  description = "Target Group 헬스체크 경로"
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = <<-EOT
    정상으로 볼 HTTP 상태 코드. 기본이 200-404인 이유:
    Ingress Controller는 매칭되는 호스트/경로가 없으면 404를 준다. 그것도 "살아 있다"는 뜻이라
    200만 정상으로 두면 앱 배포 전 노드가 전부 unhealthy가 되어 ASG가 노드를 계속 교체한다.
  EOT
  type        = string
  default     = "200-404"
}

variable "idle_timeout" {
  description = "유휴 연결 유지 시간(초)"
  type        = number
  default     = 60
}

variable "enable_deletion_protection" {
  description = "실수로 인한 ALB 삭제 방지. 축제 기간에만 켜는 것을 권장"
  type        = bool
  default     = false
}
