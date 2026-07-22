locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  https_enabled = var.enable_https
  logs_enabled  = var.access_log_bucket != ""
}

resource "aws_lb" "this" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.subnet_ids
  security_groups    = [var.security_group_id]

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection

  # 헤더 스머글링 방지. ALB가 규격에 어긋난 헤더를 뒤로 넘기지 않는다.
  drop_invalid_header_fields = true

  # 공유 버킷의 alb-logs/ prefix. 악성 IP를 찾아 security 모듈의 blocked_cidrs로 넘기는 근거가 된다.
  dynamic "access_logs" {
    for_each = local.logs_enabled ? [1] : []

    content {
      bucket  = var.access_log_bucket
      prefix  = var.access_log_prefix
      enabled = true
    }
  }

  tags = merge(local.tags, { Name = "${local.name}-alb" })
}

# ── Target Group (instance 모드 → 워커 NodePort) ──────
# ASG가 target_group_arns로 자기 인스턴스를 자동 등록/해제한다.
resource "aws_lb_target_group" "this" {
  name        = "${local.name}-tg"
  vpc_id      = var.vpc_id
  target_type = "instance"
  port        = var.target_port
  protocol    = "HTTP"

  health_check {
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = var.health_check_matcher
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # 노드가 빠질 때 진행 중인 요청이 끝날 시간을 준다(기본 300초는 배포 때 너무 길다).
  deregistration_delay = 30

  tags = merge(local.tags, { Name = "${local.name}-tg" })

  # 이름을 바꾸면 교체가 필요한데, 리스너가 참조 중이라 새 것을 먼저 만들어야 한다.
  lifecycle {
    create_before_destroy = true
  }
}

# ── 80 리스너 ─────────────────────────────────────────
# 인증서가 있으면 443으로 영구 리다이렉트, 없으면 그대로 forward(임시 운영).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.https_enabled ? [1] : []

    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.https_enabled ? [] : [1]

    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this.arn
    }
  }
}

# ── 443 리스너 (인증서가 있을 때만) ────────────────────
resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  lifecycle {
    precondition {
      condition     = var.certificate_arn != ""
      error_message = "enable_https=true면 certificate_arn이 반드시 있어야 한다."
    }
  }

  # TLS 1.2 미만을 끊는 최신 권장 정책.
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
