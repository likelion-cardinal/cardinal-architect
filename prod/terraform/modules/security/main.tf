locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  # 클러스터 노드 SG 3종. 노드 간 mesh·ALB NodePort 대상 계산에 재사용.
  node_sgs = {
    cp     = aws_security_group.cp.id
    system = aws_security_group.system.id
    app    = aws_security_group.app.id
  }
  # cp/system/app 모든 조합(9개, self 포함) → 노드 간 all-traffic 허용
  node_mesh = {
    for pair in setproduct(keys(local.node_sgs), keys(local.node_sgs)) :
    "${pair[0]}-from-${pair[1]}" => { target = pair[0], source = pair[1] }
  }
  # ALB→NodePort 대상 워커 SG (CP 제외)
  worker_sgs = {
    system = aws_security_group.system.id
    app    = aws_security_group.app.id
  }
}

# ═══════════════════════════════════════════════════════
#  ALB SG  (인터넷 80/443 수신 → 워커 NodePort 전달)
# ═══════════════════════════════════════════════════════
resource "aws_security_group" "alb" {
  name_prefix = "${local.name}-alb-"
  description = "ALB: 80/443 from internet, forward to Worker NodePort"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-alb-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP from internet (redirect to 443)"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from internet"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodeport" {
  for_each = local.worker_sgs

  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.nodeport_from
  to_port                      = var.nodeport_to
  description                  = "ALB to ${each.key} worker NodePort"
}

# ═══════════════════════════════════════════════════════
#  NAT SG  (VPC 내부 아웃바운드 중계 → 인터넷)
# ═══════════════════════════════════════════════════════
resource "aws_security_group" "nat" {
  name_prefix = "${local.name}-nat-"
  description = "NAT Instance: forward outbound from private nodes"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-nat-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "nat_from_vpc" {
  security_group_id = aws_security_group.nat.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "forward outbound from private nodes (VPC internal)"
}

resource "aws_vpc_security_group_egress_rule" "nat_internet" {
  security_group_id = aws_security_group.nat.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "NAT outbound to internet"
}

# ═══════════════════════════════════════════════════════
#  클러스터 노드 SG  (Control Plane / System / App)
#  - 노드 간: SG 참조로 all-traffic 허용(CNI 무관)
#  - 워커: ALB NodePort 수신
#  - 공통: 아웃바운드 전체(이미지 pull / SSM / NAT 경유)
# ═══════════════════════════════════════════════════════
resource "aws_security_group" "cp" {
  name_prefix = "${local.name}-cp-"
  description = "Control Plane: node-to-node only (SSM outbound, no public inbound)"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-cp-sg", Role = "control-plane" })

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "system" {
  name_prefix = "${local.name}-system-"
  description = "System Worker: node-to-node + ALB NodePort"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-system-sg", Role = "system" })

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "app" {
  name_prefix = "${local.name}-app-"
  description = "App Worker: node-to-node + ALB NodePort"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-app-sg", Role = "application" })

  lifecycle { create_before_destroy = true }
}

# 노드 간 전체 허용 (cp/system/app 9조합, 출처를 클러스터 노드 SG로만 한정)
resource "aws_vpc_security_group_ingress_rule" "node_mesh" {
  for_each = local.node_mesh

  security_group_id            = local.node_sgs[each.value.target]
  referenced_security_group_id = local.node_sgs[each.value.source]
  ip_protocol                  = "-1"
  description                  = "cluster node-to-node all (${each.value.source}->${each.value.target}, CNI agnostic)"
}

# 워커 NodePort 수신 (출처=ALB SG만)
resource "aws_vpc_security_group_ingress_rule" "worker_nodeport_from_alb" {
  for_each = local.worker_sgs

  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.nodeport_from
  to_port                      = var.nodeport_to
  description                  = "NodePort from ALB"
}

# 노드 공통 아웃바운드 전체
resource "aws_vpc_security_group_egress_rule" "node_egress" {
  for_each = local.node_sgs

  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "node outbound all (image pull / SSM / via NAT)"
}

# ═══════════════════════════════════════════════════════
#  Public Subnet NACL  (서브넷 경계, stateless, 1차 방어)
#  rule_number 오름차순 평가 → deny(1~) 를 allow(100~)보다 앞에.
#  stateless라 응답용 ephemeral 포트와 VPC 내부(NAT 중계)를 반드시 함께 허용.
# ═══════════════════════════════════════════════════════
resource "aws_network_acl" "public" {
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids
  tags       = merge(local.tags, { Name = "${local.name}-public-nacl" })
}

locals {
  blocked = { for idx, cidr in var.blocked_cidrs : tostring(idx) => cidr }
}

# 악성 IP deny (인바운드/아웃바운드), allow(100~)보다 낮은 번호로 우선 평가.
resource "aws_network_acl_rule" "deny_in" {
  for_each = local.blocked

  network_acl_id = aws_network_acl.public.id
  rule_number    = 1 + tonumber(each.key)
  egress         = false
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = each.value
}

resource "aws_network_acl_rule" "deny_out" {
  for_each = local.blocked

  network_acl_id = aws_network_acl.public.id
  rule_number    = 1 + tonumber(each.key)
  egress         = true
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = each.value
}

# 인바운드 allow: HTTP/HTTPS(사용자) + ephemeral(응답·NAT 반환) + VPC 내부(NAT 중계)
resource "aws_network_acl_rule" "in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "in_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "in_ephemeral_tcp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "in_ephemeral_udp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 130
  egress         = false
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "in_vpc_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 140
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
}

# 아웃바운드 allow: 전체(NAT 중계·ALB 응답은 임의 포트로 나감)
resource "aws_network_acl_rule" "out_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}
