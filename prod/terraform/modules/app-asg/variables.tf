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

variable "subnet_ids" {
  description = "App Worker를 배치할 Private 서브넷 ID 목록. 현재는 compute_az 한 곳(단일 AZ 절충), 후속 단계에서 2AZ로 확장"
  type        = list(string)
}

variable "security_group_id" {
  description = "App Worker SG ID (security 모듈의 app_sg_id)"
  type        = string
}

variable "instance_profile_name" {
  description = "부착할 Instance Profile 이름 (iam 모듈의 노드 공통 profile)"
  type        = string
}

variable "instance_type" {
  description = "App Worker 타입 (Spring BE + React FE ≈1.6Gi + 시스템 → 8Gi 여유)"
  type        = string
  default     = "m7i-flex.large"
}

variable "ami_id" {
  description = "App Worker AMI ID. 비우면 최신 Amazon Linux 2023 (kubeadm 사전설치 Custom AMI를 주입해야 join이 동작)"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "SSH 키페어(선택). SSM 접속 시 불필요"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "루트 EBS 크기(GB)"
  type        = number
  default     = 30
}

variable "min_size" {
  description = "ASG 최소 노드 수 (평시 규모)"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "ASG 최대 노드 수 (축제 피크 상한 = 비용 상한)"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "최초 생성 시 희망 용량. 이후 변경은 Cluster Autoscaler가 관리하므로 terraform이 되돌리지 않는다(ignore_changes)"
  type        = number
  default     = 1
}

variable "target_group_arns" {
  description = "노드를 자동 등록할 ALB Target Group ARN 목록. alb 모듈 생성 전에는 빈 목록"
  type        = list(string)
  default     = []
}

variable "health_check_grace_period" {
  description = "신규 인스턴스가 join·파드 기동을 마칠 때까지 헬스체크 유예(초)"
  type        = number
  default     = 300
}

variable "cpu_target_value" {
  description = "Target Tracking(평균 CPU %) 목표치. 0이면 정책을 만들지 않는다 — 기본은 Cluster Autoscaler 단독 운용(둘을 동시에 켜면 서로 desired_capacity를 밀어 진동한다)"
  type        = number
  default     = 0
}

variable "ssm_parameter_path" {
  description = "join 토큰이 저장된 SSM Parameter Store 경로 prefix. iam 모듈의 동명 변수와 반드시 같은 값이어야 권한이 맞는다"
  type        = string
  default     = "kubeadm"
}

variable "join_parameter_name" {
  description = "join 커맨드 전문이 담긴 파라미터 이름 (경로 하위). CP가 SecureString으로 갱신 저장한다"
  type        = string
  default     = "join-command"
}

variable "join_retry_attempts" {
  description = "join 커맨드 조회·실행 재시도 횟수 (10초 간격). 기본 60회 ≈ 10분 — CP가 아직 토큰을 안 올렸을 때를 견딘다"
  type        = number
  default     = 60
}

variable "node_labels" {
  description = "kubelet이 스스로 붙이는 노드 라벨. kubernetes.io/k8s.io 접두사는 NodeRestriction이 막으므로 자체 도메인을 쓴다"
  type        = string
  default     = "cardinal.io/role=application"
}
