locals {
  name = "${var.project}-${var.env}"
  tags = {
    Project = var.project
    Env     = var.env
  }
}

# default VPC를 그대로 사용한다(직접 만들지 않음).
data "aws_vpc" "default" {
  default = true
}

# default VPC의 서브넷 중 하나를 골라 인스턴스를 올린다.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 최신 Amazon Linux 2023 (x86_64). prod control-plane과 동일하게 SSM 파라미터로 조회.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# 로컬 cardinal.pem 의 공개키를 EC2 키페어로 등록.
resource "aws_key_pair" "cardinal" {
  key_name   = "${local.name}-key"
  public_key = trimspace(file(pathexpand(var.public_key_path)))

  tags = merge(local.tags, {
    Name = "${local.name}-key"
  })
}

# ── 보안그룹: SSH(22, 내 IP), FE(3000), 아웃바운드 전체 ──
resource "aws_security_group" "app" {
  name        = "${local.name}-app-sg"
  description = "staging app: SSH from my IP, FE 3000"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH (my IP only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "FE (frontend)"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.fe_ingress_cidr]
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name}-app-sg"
  })
}

# ── 단일 staging EC2 (Public, SSH + FE 확인용) ──
resource "aws_instance" "app" {
  ami                    = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.cardinal.key_name

  associate_public_ip_address = true

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
    Name = "${local.name}-app"
    Role = "app"
  })
}
