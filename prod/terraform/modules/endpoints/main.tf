locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  # SSM Session Manager 사설 접속에 필요한 인터페이스 엔드포인트 3종.
  services = ["ssm", "ssmmessages", "ec2messages"]
}

# 서비스명은 리전마다 다르므로 data source로 자동 해석(하드코딩 금지).
data "aws_vpc_endpoint_service" "this" {
  for_each = toset(local.services)

  service      = each.key
  service_type = "Interface"
}

# ── 엔드포인트 전용 SG: VPC 내부에서 오는 443만 허용 ──
resource "aws_security_group" "endpoints" {
  name_prefix = "${local.name}-vpce-"
  description = "SSM interface endpoints: allow 443 from VPC"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-vpce-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "https_from_vpc" {
  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from VPC to SSM endpoints"
}

# ── SSM Interface Endpoints (ssm / ssmmessages / ec2messages) ──
resource "aws_vpc_endpoint" "this" {
  for_each = toset(local.services)

  vpc_id            = var.vpc_id
  service_name      = data.aws_vpc_endpoint_service.this[each.key].service_name
  vpc_endpoint_type = "Interface"

  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true # 없으면 SSM 접속 실패(사설 DNS로 aws 엔드포인트 해석)

  tags = merge(local.tags, { Name = "${local.name}-${each.key}-endpoint" })
}
