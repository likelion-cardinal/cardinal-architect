locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  # ami_id가 비어 있으면 최신 Amazon Linux 2023 사용
  ami_id = var.ami_id != "" ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023.value)

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    route_table_ids = join(" ", var.private_route_table_ids)
  })
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ═══════════════════════════════════════════════════════
#  IAM — NAT가 자기 source/dest check·라우트를 갱신할 권한
# ═══════════════════════════════════════════════════════
data "aws_iam_policy_document" "nat" {
  statement {
    sid    = "SelfManageRouteAndAttr"
    effect = "Allow"
    actions = [
      "ec2:ModifyInstanceAttribute",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "DescribeForRouteUpdate"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRouteTables",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "nat" {
  name = "${local.name}-nat-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(local.tags, { Name = "${local.name}-nat-role" })
}

resource "aws_iam_role_policy" "nat" {
  name   = "${local.name}-nat-self-manage"
  role   = aws_iam_role.nat.id
  policy = data.aws_iam_policy_document.nat.json
}

# 디버깅용 SSM 접속 (선택이지만 붙여두면 편리)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.nat.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat" {
  name = "${local.name}-nat-profile"
  role = aws_iam_role.nat.name

  tags = merge(local.tags, { Name = "${local.name}-nat-profile" })
}

# ═══════════════════════════════════════════════════════
#  Launch Template + size-1 ASG (자동 복구)
# ═══════════════════════════════════════════════════════
resource "aws_launch_template" "nat" {
  name_prefix   = "${local.name}-nat-"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null
  user_data     = base64encode(local.user_data)

  iam_instance_profile {
    arn = aws_iam_instance_profile.nat.arn
  }

  vpc_security_group_ids = [var.security_group_id]

  # IMDSv2 강제
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-nat", Role = "nat" })
  }

  tags = merge(local.tags, { Name = "${local.name}-nat-lt" })

  lifecycle { create_before_destroy = true }
}

resource "aws_autoscaling_group" "nat" {
  name_prefix         = "${local.name}-nat-"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [var.subnet_id]
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.nat.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-nat"
    propagate_at_launch = true
  }
  tag {
    key                 = "Role"
    value               = "nat"
    propagate_at_launch = true
  }

  lifecycle { create_before_destroy = true }
}
