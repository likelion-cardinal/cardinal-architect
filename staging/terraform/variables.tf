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
  description = "환경"
  type        = string
  default     = "staging"
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "루트 EBS 볼륨 크기(GiB)"
  type        = number
  default     = 15
}

# 로컬 ~/.ssh/cardinal.pem 에 대응하는 공개키. terraform이 이 값으로
# EC2 키페어를 만들어 인스턴스에 심는다. 접속: ssh -i ~/.ssh/cardinal.pem ec2-user@<ip>
variable "public_key_path" {
  description = "인스턴스에 심을 SSH 공개키 파일 경로"
  type        = string
  default     = "~/.ssh/cardinal.pub"
}

# SSH(22)를 열어줄 대역. 기본값은 이 설정을 만든 시점의 내 공인 IP들.
# IP가 바뀌거나 접속 위치가 늘면 이 목록만 갱신하면 된다.
variable "ssh_ingress_cidrs" {
  description = "SSH(22)를 허용할 CIDR 목록. 내 IP만 여는 것을 권장"
  type        = list(string)
  default = [
    "61.73.4.159/32",   # 집
    "118.235.13.43/32", # 공인 IP
  ]
}

# 웹(80/443)은 브라우저로 아무 데서나 확인하려고 열어둔다. 필요 시 좁혀라.
variable "web_ingress_cidr" {
  description = "웹 포트(80/443)를 허용할 CIDR"
  type        = string
  default     = "0.0.0.0/0"
}
