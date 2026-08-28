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
  default     = 30
}

# AMI는 고정한다. most_recent 데이터소스를 쓰면 아마존이 새 AL2023 이미지를
# 낼 때마다 ami가 바뀌고, ami는 ForceNew라 apply 한 번에 인스턴스가 통째로
# 재생성된다(루트 EBS·퍼블릭 IP 소실). 이미지를 올리고 싶을 때만 이 값을 바꾼다.
#   최신 목록: aws ec2 describe-images --owners amazon \
#     --filters 'Name=name,Values=al2023-ami-2023.*-x86_64' 'Name=state,Values=available' \
#     --query 'sort_by(Images,&CreationDate)[-1].[ImageId,Name]' --output text
variable "ami_id" {
  description = "인스턴스에 사용할 AMI ID(고정). 기본값은 현재 떠 있는 인스턴스와 동일한 AL2023"
  type        = string
  default     = "ami-091c87ff6d6a3f749" # al2023-ami-2023.12.20260724.0-kernel-6.1-x86_64
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
    "61.73.4.159/32",   # 김지오
    "118.235.13.43/32", # 김지오
    "58.143.50.157/32", # 최성민 
    "1.232.160.41/32", # 유지오 
    "220.76.161.66/32", # 유지오 
    "183.96.242.88/32", # 이현서
    "163.239.255.170/32", # 학교 eduroam
    "125.128.33.67/32" # 임시 주소
  ]
}

# 웹(80/443)은 브라우저로 아무 데서나 확인하려고 열어둔다. 필요 시 좁혀라.
variable "web_ingress_cidr" {
  description = "웹 포트(80/443)를 허용할 CIDR"
  type        = string
  default     = "0.0.0.0/0"
}
