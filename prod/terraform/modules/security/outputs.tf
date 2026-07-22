output "alb_sg_id" {
  description = "ALB Security Group ID"
  value       = aws_security_group.alb.id
}

output "nat_sg_id" {
  description = "NAT Instance Security Group ID"
  value       = aws_security_group.nat.id
}

output "control_plane_sg_id" {
  description = "Control Plane Security Group ID"
  value       = aws_security_group.cp.id
}

output "system_sg_id" {
  description = "System Worker Security Group ID"
  value       = aws_security_group.system.id
}

output "app_sg_id" {
  description = "App Worker Security Group ID"
  value       = aws_security_group.app.id
}

output "public_nacl_id" {
  description = "Public Subnet NACL ID"
  value       = aws_network_acl.public.id
}
