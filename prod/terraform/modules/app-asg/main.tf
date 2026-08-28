locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  ami_id = var.ami_id != "" ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023.value)

  # iam 모듈이 권한을 준 경로와 동일하게 조립한다: /<project>/<env>/<path>/<name>
  join_param = "/${var.project}/${var.env}/${var.ssm_parameter_path}/${var.join_parameter_name}"

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    join_param          = local.join_param
    join_retry_attempts = var.join_retry_attempts
    node_labels         = var.node_labels
  })

  # Cluster Autoscaler가 확장 대상 ASG를 찾는 자동탐색(auto-discovery) 태그.
  # 노드에 붙일 필요는 없으므로 propagate_at_launch = false.
  autoscaler_tags = {
    "k8s.io/cluster-autoscaler/enabled"       = "true"
    "k8s.io/cluster-autoscaler/${local.name}" = "owned"
  }
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ═══════════════════════════════════════════════════════
#  Launch Template — Custom AMI + 부팅 즉시 kubeadm join
# ═══════════════════════════════════════════════════════
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-app-"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null
  user_data     = base64encode(local.user_data)

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.security_group_id]

  metadata_options {
    http_tokens                 = "required" # IMDSv2 강제
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2 # 파드에서 IMDS 접근 허용
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-app", Role = "application" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name}-app-root" })
  }

  tags = merge(local.tags, { Name = "${local.name}-app-lt" })

  lifecycle { create_before_destroy = true }
}

# ═══════════════════════════════════════════════════════
#  ASG — 평시 min, 피크 max. desired는 Cluster Autoscaler 소관
# ═══════════════════════════════════════════════════════
resource "aws_autoscaling_group" "app" {
  name_prefix         = "${local.name}-app-"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids

  # 노드가 join하고 파드가 뜰 시간을 준 뒤 헬스체크. TG가 붙으면 ELB 헬스체크로 전환.
  health_check_type         = length(var.target_group_arns) > 0 ? "ELB" : "EC2"
  health_check_grace_period = var.health_check_grace_period

  # ALB Target Group 자동 등록/해제 (NodePort 대상). alb 모듈 생성 전에는 빈 목록.
  target_group_arns = var.target_group_arns

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(local.tags, {
      Name = "${local.name}-app"
      Role = "application" # System(고정)과 구분하는 핵심 태그
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  dynamic "tag" {
    for_each = local.autoscaler_tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  # desired_capacity는 Cluster Autoscaler가 실시간으로 바꾼다.
  # 여기서 감시하면 terraform apply마다 스케일을 평시 값으로 되돌려 파드를 쫓아낸다.
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# ── (선택) Target Tracking — Cluster Autoscaler를 안 쓸 때만 ──
# cpu_target_value = 0 이면 생성하지 않는다(기본).
resource "aws_autoscaling_policy" "cpu" {
  count = var.cpu_target_value > 0 ? 1 : 0

  name                   = "${local.name}-app-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}
