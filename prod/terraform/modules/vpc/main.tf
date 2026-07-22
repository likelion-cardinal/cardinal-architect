locals {
  name = "${var.project}-${var.env}"

  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })
}

# ── VPC ──────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name}-vpc" })
}

# ── Internet Gateway (Public 서브넷의 0.0.0.0/0) ──────
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-igw" })
}

# ── Subnets ──────────────────────────────────────────
# Public
resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${local.name}-public-${var.azs[count.index]}"
    Tier = "public"
  })
}

# Private
resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.name}-private-${var.azs[count.index]}"
    Tier = "private"
  })
}

# ── Public Route Table (→ IGW) ───────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Table (AZ별 1개) ───────────────────
# 기본 경로(0.0.0.0/0 → NAT Instance)는 nat-instance와의 결합이라
# 이 모듈이 아니라 root(main.tf) wiring에서 aws_route로 추가한다.
# 여기서는 빈 라우트 테이블 + 서브넷 연결 + S3 GW Endpoint 연결까지만 담당.
resource "aws_route_table" "private" {
  count = length(var.azs)

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-private-rt-${var.azs[count.index]}" })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ── S3 Gateway Endpoint (무료) ───────────────────────
# ECR 이미지 레이어·S3 트래픽이 NAT를 우회하도록 Private 라우트 테이블에 연결.
# NAT 데이터 처리 비용·부하를 낮춘다. 서비스명은 data source로 리전 자동 해석.
data "aws_vpc_endpoint_service" "s3" {
  service      = "s3"
  service_type = "Gateway"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = data.aws_vpc_endpoint_service.s3.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(local.tags, { Name = "${local.name}-s3-gw-endpoint" })
}
