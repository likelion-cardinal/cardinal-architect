output "instance_id" {
  description = "System Worker 인스턴스 ID"
  value       = aws_instance.system.id
}

output "private_ip" {
  description = "System Worker 사설 IP"
  value       = aws_instance.system.private_ip
}

output "availability_zone" {
  description = "System Worker AZ (MySQL EBS 고정 기준)"
  value       = aws_instance.system.availability_zone
}

output "mysql_volume_id" {
  description = "MySQL 정적 EBS 볼륨 ID (생성한 경우)"
  value       = var.mysql_data_volume_size > 0 ? aws_ebs_volume.mysql[0].id : null
}
