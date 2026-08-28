locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  ami_id = var.ami_id != "" ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023.value)

  # join 토큰 파라미터 경로. iam(권한)·app-asg(수신)과 같은 값을 봐야 한다.
  join_param = "/${var.project}/${var.env}/${var.ssm_parameter_path}/${var.join_parameter_name}"

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    hostname               = var.hostname
    kubernetes_version     = var.kubernetes_version
    node_labels            = var.node_labels
    pod_subnet             = var.pod_subnet
    calico_manifest        = var.calico_manifest_path
    join_param             = local.join_param
    token_refresh_schedule = var.token_refresh_schedule
    etcd_backup_bucket     = var.etcd_backup_bucket
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
  private_ip             = var.private_ip != "" ? var.private_ip : null
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_name != "" ? var.key_name : null

  associate_public_ip_address = false # Private 격리, SSM으로만 접근
  user_data                   = local.user_data

  # T 계열의 기본값은 unlimited — baseline(t3.medium = 2 vCPU × 20% = 400m)을 넘는 순간
  # 초과분이 vCPU-시간당 별도 과금된다. 상한이 없는 요금은 지원금 정산에 쓸 수 없으므로
  # standard로 고정해 "초과하면 과금" 대신 "초과하면 쓰로틀"을 택한다.
  # 소규모 클러스터의 apiserver+etcd 유휴 사용량은 100~150m 수준이라 baseline 안에 들어온다.
  # 넘기 시작하면 그때 인스턴스 타입을 올릴 것 (unlimited로 되돌리는 건 원인을 가리는 선택).
  #
  # credit_specification은 T 계열 전용 속성이다. 정적으로 쓰면 instance_type을 m7i-flex
  # 같은 비버스터블로 바꾼 순간 apply가 AWS API 에러로 죽으므로, 타입을 보고 알아서 빠지게 한다.
  dynamic "credit_specification" {
    for_each = startswith(var.instance_type, "t") ? [1] : []

    content {
      cpu_credits = "standard"
    }
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 강제
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2 # 파드에서 IMDS 접근 허용
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
