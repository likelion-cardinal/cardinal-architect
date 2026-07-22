output "instance_id" {
  description = "Control Plane 인스턴스 ID"
  value       = aws_instance.cp.id
}

output "private_ip" {
  description = "Control Plane 사설 IP"
  value       = aws_instance.cp.private_ip
}

output "availability_zone" {
  description = "CP가 배치된 AZ (EBS/etcd 고정 기준)"
  value       = aws_instance.cp.availability_zone
}

output "ami_id" {
  description = "실제 사용된 AMI ID"
  value       = local.ami_id
}
