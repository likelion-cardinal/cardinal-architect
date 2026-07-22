locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  # 이 계정/리전 기준으로 정책 대상 ARN을 동적으로 구성(하드코딩 금지).
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # join 토큰이 저장될 SSM Parameter Store 경로: /<project>/<env>/<path>/*
  ssm_param_arn = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/${var.project}/${var.env}/${var.ssm_parameter_path}/*"

  # etcd 백업 버킷 ARN이 주어졌을 때만 S3 statement를 포함한다.
  s3_enabled = var.etcd_backup_bucket_arn != ""
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── 노드 인라인 정책 문서 ─────────────────────────────
# join 토큰(SSM Param) 읽기/쓰기 + SecureString 복호화(KMS),
# 그리고 (버킷 주입 시) etcd 백업용 S3 접근.
data "aws_iam_policy_document" "node_extra" {
  statement {
    sid    = "SSMJoinTokenParameter"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:PutParameter", # CP가 토큰을 갱신 저장(공통 Role)
      "ssm:DeleteParameter",
    ]
    resources = [local.ssm_param_arn]
  }

  statement {
    sid    = "UseSSMSecureString"
    effect = "Allow"
    # Decrypt는 워커가 join 커맨드를 읽을 때, Encrypt/GenerateDataKey는
    # CP가 갱신한 토큰을 SecureString으로 덮어쓸 때 필요하다.
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = ["*"]

    # SSM(join 토큰)과 S3(PKI 백업 SSE-KMS)를 경유한 호출로만 한정.
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "ssm.${local.region}.amazonaws.com",
        "s3.${local.region}.amazonaws.com",
      ]
    }
  }

  # Cluster Autoscaler: 대상 ASG 탐색(읽기)은 리소스 스코프를 지원하지 않아 "*",
  # 실제 조작(용량 변경·인스턴스 종료)은 auto-discovery 태그가 붙은 ASG로만 한정한다.
  dynamic "statement" {
    for_each = var.cluster_autoscaler_enabled ? [1] : []
    content {
      sid    = "ClusterAutoscalerDiscovery"
      effect = "Allow"
      actions = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeImages",
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.cluster_autoscaler_enabled ? [1] : []
    content {
      sid    = "ClusterAutoscalerScale"
      effect = "Allow"
      actions = [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
      ]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${local.name}"
        values   = ["owned"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.s3_enabled ? [1] : []
    content {
      sid       = "BackupBucketList"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = [var.etcd_backup_bucket_arn]

      # 복구 스크립트가 최신 백업을 찾으려면 두 prefix 모두 나열할 수 있어야 한다.
      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["etcd/*", "pki/*"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.s3_enabled ? [1] : []
    content {
      sid     = "BackupObjects"
      effect  = "Allow"
      actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]

      # etcd 스냅샷과 PKI 아카이브. 이 둘이 짝을 이뤄야 복구가 성립한다.
      resources = [
        "${var.etcd_backup_bucket_arn}/etcd/*",
        "${var.etcd_backup_bucket_arn}/pki/*",
      ]
    }
  }
}

# ── 노드 공통 Role (EC2가 assume) ────────────────────
resource "aws_iam_role" "node" {
  name = "${local.name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(local.tags, { Name = "${local.name}-node-role" })
}

# SSM Session Manager 접속(관리자 kubectl 경로)에 필요한 AWS 관리형 정책.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# join 토큰(SSM Param) + etcd 백업(S3) 접근용 인라인 정책.
resource "aws_iam_role_policy" "node_extra" {
  name   = "${local.name}-node-extra"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.node_extra.json
}

# ── Instance Profile (Role을 EC2에 붙이는 포장지) ─────
resource "aws_iam_instance_profile" "node" {
  name = "${local.name}-node-profile"
  role = aws_iam_role.node.name

  tags = merge(local.tags, { Name = "${local.name}-node-profile" })
}
