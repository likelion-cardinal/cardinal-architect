output "security_group_id" {
  description = "엔드포인트 전용 SG ID"
  value       = aws_security_group.endpoints.id
}

output "endpoint_ids" {
  description = "서비스별 Interface Endpoint ID 맵"
  value       = { for k, ep in aws_vpc_endpoint.this : k => ep.id }
}
