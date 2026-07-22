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
  description = "CP를 배치할 Private 서브넷 ID (compute_az). EBS/etcd가 이 AZ에 고정"
  type        = string
}

variable "security_group_id" {
  description = "Control Plane SG ID (security 모듈의 control_plane_sg_id)"
  type        = string
}

variable "instance_profile_name" {
  description = "부착할 Instance Profile 이름 (iam 모듈의 노드 공통 profile)"
  type        = string
}

variable "instance_type" {
  description = "CP 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = "CP AMI ID. 비우면 최신 Amazon Linux 2023. (kubeadm 사전설치 Custom AMI가 있으면 여기 주입)"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "SSH 키페어(선택). SSM로 접속하면 불필요"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "루트 EBS 크기(GB)"
  type        = number
  default     = 30
}

variable "hostname" {
  description = "CP hostname (kubeadm 노드명)"
  type        = string
  default     = "master-1"
}

variable "etcd_backup_bucket" {
  description = "etcd 스냅샷 업로드용 공유 S3 버킷 이름. 비우면 백업 cron 생략(버킷 생성 후 주입)"
  type        = string
  default     = ""
}
