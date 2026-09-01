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

# CP를 인스턴스 ID로 박으면 AMI 교체로 CP가 replacement 될 때마다 정책이 깨진다.
# 태그로 잡아두면 새 CP가 떠도 그대로 붙는다(control-plane 모듈이 Role=control-plane 을 단다).
variable "control_plane_role_tag" {
  description = "접속을 허용할 CP 인스턴스의 Role 태그 값"
  type        = string
  default     = "control-plane"
}

# 세션이 드롭할 리눅스 계정. CP에 sudo 없이 만들어 두고 제한 kubeconfig만 쥐여준다.
# (manifest/all/dev-access/setup.txt 의 "CP 준비" 절차가 이 계정을 만든다)
variable "session_linux_user" {
  description = "SSM 세션이 실행될 CP 리눅스 계정. sudo 권한이 없어야 의미가 있다"
  type        = string
  default     = "devops"
}
