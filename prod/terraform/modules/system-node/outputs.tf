output "instance_id" {
  description = "System Worker 인스턴스 ID"
  value       = aws_instance.system.id
}

output "private_ip" {
  description = "System Worker 사설 IP"
  value       = aws_instance.system.private_ip
}

output "availability_zone" {
  description = "System Worker AZ (데이터 EBS 고정 기준)"
  value       = aws_instance.system.availability_zone
}

output "data_volume_id" {
  description = "영속 데이터용 정적 EBS 볼륨 ID (생성한 경우)"
  value       = var.data_volume_size > 0 ? aws_ebs_volume.data[0].id : null
}
