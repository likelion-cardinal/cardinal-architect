output "arn" {
  description = "ALB ARN"
  value       = aws_lb.this.arn
}

output "dns_name" {
  description = "ALB DNS 이름. 도메인 연결 전에는 이 주소로 직접 접속해 확인한다"
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "ALB의 Route53 Hosted Zone ID (Alias A 레코드에 필요)"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "App Worker ASG가 자동 등록될 Target Group ARN"
  value       = aws_lb_target_group.this.arn
}

output "https_enabled" {
  description = "443 리스너 생성 여부 (인증서 주입 시 true)"
  value       = length(aws_lb_listener.https) > 0
}
