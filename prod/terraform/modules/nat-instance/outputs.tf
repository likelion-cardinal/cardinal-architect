output "asg_name" {
  description = "NAT ASG 이름"
  value       = aws_autoscaling_group.nat.name
}

output "launch_template_id" {
  description = "NAT Launch Template ID"
  value       = aws_launch_template.nat.id
}

output "iam_role_arn" {
  description = "NAT 인스턴스 IAM Role ARN"
  value       = aws_iam_role.nat.arn
}

output "ami_id" {
  description = "실제 사용된 NAT AMI ID"
  value       = local.ami_id
}
