locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  ami_id = var.ami_id != "" ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023.value)

  mysql_static      = var.mysql_data_volume_size > 0
  mysql_volume_name = "${local.name}-mysql-data"

  # join 토큰 파라미터 경로. CP(발행)·app-asg(수신)와 같은 값을 봐야 한다.
  join_param = "/${var.project}/${var.env}/${var.ssm_parameter_path}/${var.join_parameter_name}"

  # user_data: hostname → (정적 EBS가 있으면) MySQL 볼륨 포맷/마운트 → kubeadm join.
  # MySQL 백업(mysqldump)은 클러스터 CronJob으로 별도 운영.
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    hostname            = var.hostname
    mysql_static        = local.mysql_static
    mount_point         = var.mysql_mount_point
    join_param          = local.join_param
    join_retry_attempts = var.join_retry_attempts
    node_labels         = var.node_labels
  })
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ── 고정 System Worker EC2 (확장 X, Role=system) ──────
resource "aws_instance" "system" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_name != "" ? var.key_name : null

  associate_public_ip_address = false
  user_data                   = local.user_data

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(local.tags, {
    Name = "${local.name}-system"
    Role = "system" # Cluster Autoscaler가 확장 대상(application)과 구분하는 핵심 태그
  })

  lifecycle {
    ignore_changes = [user_data]
  }
}

# ── (옵션) MySQL 데이터용 정적 EBS — 노드 AZ에 고정 ──
# 동적 PVC(EBS CSI)를 쓰면 불필요. 정적 PV로 관리하고 싶을 때만 size>0.
resource "aws_ebs_volume" "mysql" {
  count = local.mysql_static ? 1 : 0

  availability_zone = aws_instance.system.availability_zone
  size              = var.mysql_data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = merge(local.tags, { Name = local.mysql_volume_name })
}

resource "aws_volume_attachment" "mysql" {
  count = local.mysql_static ? 1 : 0

  device_name = "/dev/xvdf" # Nitro에선 NVMe로 재매핑됨(user_data가 LABEL로 마운트)
  volume_id   = aws_ebs_volume.mysql[0].id
  instance_id = aws_instance.system.id
}
