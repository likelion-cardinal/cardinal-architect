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
  description = "System Worker를 배치할 Private 서브넷 ID (compute_az). MySQL EBS가 이 AZ에 고정"
  type        = string
}

variable "security_group_id" {
  description = "System Worker SG ID (security 모듈의 system_sg_id)"
  type        = string
}

variable "instance_profile_name" {
  description = "부착할 Instance Profile 이름 (iam 모듈의 노드 공통 profile)"
  type        = string
}

variable "instance_type" {
  description = "System Worker 타입 (ArgoCD·Prom·Graf·MySQL ≈7Gi → 8Gi)"
  type        = string
  default     = "m7i-flex.large"
}

variable "ami_id" {
  description = "AMI ID. 비우면 최신 Amazon Linux 2023 (kubeadm 사전설치 AMI가 있으면 주입)"
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

variable "hostname" {
  description = "System Worker hostname"
  type        = string
  default     = "system-1"
}

variable "mysql_data_volume_size" {
  description = "MySQL 데이터용 별도 EBS 크기(GB). 0이면 생성 안 함. >0이면 정적 EBS를 노드 AZ에 고정 부착 후 mysql_mount_point에 마운트"
  type        = number
  default     = 0
}

variable "mysql_mount_point" {
  description = "MySQL 데이터 EBS를 마운트할 디렉토리 (파드가 hostPath PV로 사용)"
  type        = string
  default     = "/mnt/mysql-data"
}
