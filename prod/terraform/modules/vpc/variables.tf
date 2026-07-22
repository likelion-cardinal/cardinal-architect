variable "project" {
  description = "프로젝트명 (태그·네이밍 prefix). 예: daedongje"
  type        = string
}

variable "env" {
  description = "환경 (prod/dev). 태그·네이밍에 사용"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 대역. 예: 10.0.0.0/16"
  type        = string
}

variable "azs" {
  description = "사용할 가용영역 목록. ALB 요구로 2개 이상. 예: [\"ap-northeast-2a\",\"ap-northeast-2c\"]"
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "ALB는 서로 다른 AZ의 서브넷 2개 이상을 요구하므로 azs는 2개 이상이어야 한다."
  }
}

variable "public_subnet_cidrs" {
  description = "AZ별 Public 서브넷 CIDR. azs와 같은 순서·길이. 예: [\"10.0.0.0/24\",\"10.0.1.0/24\"]"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs 길이는 azs 길이와 같아야 한다."
  }
}

variable "private_subnet_cidrs" {
  description = "AZ별 Private 서브넷 CIDR. azs와 같은 순서·길이. 예: [\"10.0.10.0/24\",\"10.0.11.0/24\"]"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs 길이는 azs 길이와 같아야 한다."
  }
}

variable "tags" {
  description = "모든 리소스에 병합할 공통 태그"
  type        = map(string)
  default     = {}
}
