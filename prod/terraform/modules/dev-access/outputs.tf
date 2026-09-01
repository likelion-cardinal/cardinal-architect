output "session_document_name" {
  description = "개발팀이 --document-name 에 넣을 이름"
  value       = aws_ssm_document.cp_devops.name
}

output "group_name" {
  description = "개발자 IAM 유저를 여기에 넣는다 (유저 생성은 콘솔에서)"
  value       = aws_iam_group.dev.name
}

output "connect_command" {
  description = "개발자에게 그대로 전달할 접속 명령"
  value       = "aws ssm start-session --target <CP_INSTANCE_ID> --document-name ${aws_ssm_document.cp_devops.name}"
}
