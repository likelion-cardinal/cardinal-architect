output "asg_name" {
  description = "App Worker ASG 이름 (Cluster Autoscaler 대상)"
  value       = aws_autoscaling_group.app.name
}

output "asg_arn" {
  description = "App Worker ASG ARN"
  value       = aws_autoscaling_group.app.arn
}

output "launch_template_id" {
  description = "App Worker Launch Template ID"
  value       = aws_launch_template.app.id
}

output "ami_id" {
  description = "실제 사용된 AMI ID"
  value       = local.ami_id
}

output "join_parameter_name" {
  description = "노드가 읽는 join 커맨드 SSM 파라미터 이름 (CP가 이 이름으로 갱신 저장해야 한다)"
  value       = local.join_param
}
