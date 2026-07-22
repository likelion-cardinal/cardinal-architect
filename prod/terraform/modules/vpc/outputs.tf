output "vpc_id" {
  description = "생성된 VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR 대역"
  value       = aws_vpc.this.cidr_block
}

output "igw_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "Public 서브넷 ID 목록 (azs 순서)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private 서브넷 ID 목록 (azs 순서)"
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "Public 라우트 테이블 ID"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Private 라우트 테이블 ID 목록 (root에서 NAT 기본경로 wiring에 사용)"
  value       = aws_route_table.private[*].id
}

output "availability_zones" {
  description = "서브넷이 배치된 AZ 목록"
  value       = var.azs
}
