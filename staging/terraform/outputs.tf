output "instance_id" {
  description = "생성된 EC2 인스턴스 ID"
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "인스턴스 퍼블릭 IP"
  value       = aws_instance.app.public_ip
}

output "ssh_command" {
  description = "SSH 접속 명령"
  value       = "ssh -i ~/.ssh/cardinal.pem ec2-user@${aws_instance.app.public_ip}"
}

output "web_url" {
  description = "웹 접속 URL(80/443)"
  value       = "http://${aws_instance.app.public_ip}"
}
