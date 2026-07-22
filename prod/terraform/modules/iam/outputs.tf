output "role_name" {
  description = "노드 공통 IAM Role 이름"
  value       = aws_iam_role.node.name
}

output "role_arn" {
  description = "노드 공통 IAM Role ARN"
  value       = aws_iam_role.node.arn
}

output "instance_profile_name" {
  description = "EC2에 부착할 Instance Profile 이름 (인스턴스 모듈에서 사용)"
  value       = aws_iam_instance_profile.node.name
}

output "instance_profile_arn" {
  description = "Instance Profile ARN"
  value       = aws_iam_instance_profile.node.arn
}
