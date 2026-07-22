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

variable "private_ip" {
  description = <<-EOT
    CP에 고정할 사설 IP. subnet_id의 CIDR 안이어야 하고 앞 4개·마지막 1개는 AWS 예약이다.
    고정하는 이유: controlPlaneEndpoint와 인증서 SAN이 이 주소로 굳는다. IP가 바뀌면
    워커의 kubelet.conf가 죽은 주소를 가리켜 클러스터 전체가 복구 불가능해진다.
    비우면 AWS가 임의 할당한다(복구 시나리오를 포기한다는 뜻).
  EOT
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "kubeadm init에 고정할 k8s 버전. AMI에 프리풀된 이미지 태그와 반드시 일치해야 무인 부팅에서 pull이 발생하지 않는다"
  type        = string
  default     = "v1.34.9"
}

variable "pod_subnet" {
  description = "파드 네트워크 대역. Calico 기본 IP 풀과 일치하며 VPC CIDR과 겹치지 않아야 한다"
  type        = string
  default     = "192.168.0.0/16"
}

variable "calico_manifest_path" {
  description = "AMI에 구워둔 Calico 매니페스트 경로 (VXLAN=Always로 수정된 사본)"
  type        = string
  default     = "/opt/cardinal/calico-vxlan.yaml"
}

variable "ssm_parameter_path" {
  description = "join 토큰을 발행할 SSM Parameter Store 경로 prefix. iam·app-asg의 동명 변수와 같은 값이어야 한다"
  type        = string
  default     = "kubeadm"
}

variable "join_parameter_name" {
  description = "join 커맨드를 저장할 파라미터 이름 (경로 하위)"
  type        = string
  default     = "join-command"
}

variable "token_refresh_cron" {
  description = "join 토큰 갱신 cron 스케줄. 토큰 TTL(24h)보다 촘촘해야 만료 구멍이 생기지 않는다"
  type        = string
  default     = "0 */6 * * *"
}

variable "etcd_backup_bucket" {
  description = "etcd 스냅샷 업로드용 공유 S3 버킷 이름. 비우면 백업 cron 생략(버킷 생성 후 주입)"
  type        = string
  default     = ""
}
