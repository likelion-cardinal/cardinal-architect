locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  ami_id = var.ami_id != "" ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023.value)

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    hostname           = var.hostname
    etcd_backup_bucket = var.etcd_backup_bucket
  })
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ── 단일 Control Plane EC2 (Private, Public IP 없음) ──
resource "aws_instance" "cp" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_name != "" ? var.key_name : null

  associate_public_ip_address = false # Private 격리, SSM으로만 접근
  user_data                   = local.user_data

  metadata_options {
    http_tokens   = "required" # IMDSv2 강제
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(local.tags, {
    Name = "${local.name}-cp"
    Role = "control-plane"
  })

  # user_data 변경만으로 인스턴스를 재생성하지 않도록(운영 중 CP 교체 방지).
  # AMI·타입 등 실질 변경 시에만 교체.
  lifecycle {
    ignore_changes = [user_data]
  }
}
