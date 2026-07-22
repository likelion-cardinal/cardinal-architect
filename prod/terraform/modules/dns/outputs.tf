output "zone_id" {
  description = "Public Hosted Zone ID (root에서 ALB Alias A 레코드를 만들 때 사용)"
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "가비아 관리 콘솔에 입력할 네임서버 4개. 이걸 바꾸기 전엔 ACM 검증이 통과하지 않는다"
  value       = aws_route53_zone.this.name_servers
}

output "domain_name" {
  description = "apex 도메인"
  value       = var.domain_name
}

output "certificate_arn" {
  description = "ALB 443 리스너에 물릴 인증서 ARN. wait_for_validation=true면 발급 완료가 보장된 값이다"
  value       = var.wait_for_validation ? aws_acm_certificate_validation.this[0].certificate_arn : aws_acm_certificate.this.arn
}

output "certificate_status" {
  description = "인증서 상태 (PENDING_VALIDATION이면 아직 NS 위임이 안 끝난 것)"
  value       = aws_acm_certificate.this.status
}
