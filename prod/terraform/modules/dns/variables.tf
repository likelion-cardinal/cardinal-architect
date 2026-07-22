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

variable "domain_name" {
  description = "가비아에서 구매한 apex 도메인 (예: cardinal.kr). 네임서버를 이 모듈이 만든 Hosted Zone의 NS로 바꿔야 검증이 통과한다"
  type        = string
}

variable "subject_alternative_names" {
  description = "인증서에 추가할 도메인. 기본은 와일드카드 1장 — argocd·grafana 등 서브도메인을 인증서 재발급 없이 늘릴 수 있다"
  type        = list(string)
  default     = null
}

variable "wait_for_validation" {
  description = <<-EOT
    ACM 검증 완료까지 apply를 대기할지 여부.
    false(기본): 인증서와 검증용 DNS 레코드만 만들고 넘어간다. 가비아 네임서버 변경 전이라면
    검증이 끝날 수 없으므로, 첫 apply를 여기서 붙잡아두지 않기 위한 기본값이다.
    NS 전파 후 true로 바꿔 apply하면 발급 완료를 확인하고 ALB 리스너에 물릴 수 있다.
  EOT
  type        = bool
  default     = false
}

variable "validation_timeout" {
  description = "wait_for_validation=true일 때 검증 대기 한도"
  type        = string
  default     = "45m"
}
