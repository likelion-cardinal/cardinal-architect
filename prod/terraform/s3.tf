# ═══════════════════════════════════════════════════════
#  공유 S3 버킷 (root 소유)
#  버킷을 용도별로 나누지 않고 prefix로 분리한다:
#    alb-logs/ … ALB Access Log (악성 IP 분석 → NACL deny 목록의 근거)
#    etcd/     … CP의 etcd 스냅샷 (단일 CP라 백업이 유일한 사고 대비책)
#  로컬 state를 쓰므로 이 버킷은 state 저장과 무관하다.
# ═══════════════════════════════════════════════════════
data "aws_caller_identity" "current" {}

# ALB가 Access Log를 쓸 때 사용하는 리전별 AWS 계정. 리전마다 달라 하드코딩하지 않는다.
data "aws_elb_service_account" "main" {}

locals {
  # 버킷 이름은 전역 유일해야 해서 계정 ID를 접미사로 붙인다.
  shared_bucket_name = "${var.project}-${var.env}-shared-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "shared" {
  bucket = local.shared_bucket_name

  tags = {
    Name    = local.shared_bucket_name
    Project = var.project
    Env     = var.env
  }
}

# 로그·백업 모두 외부에 노출될 이유가 없다.
resource "aws_s3_bucket_public_access_block" "shared" {
  bucket = aws_s3_bucket.shared.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3(AES256). KMS를 쓰면 ALB 로그 전달에 추가 설정이 필요하고 요청 비용도 붙는다.
resource "aws_s3_bucket_server_side_encryption_configuration" "shared" {
  bucket = aws_s3_bucket.shared.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 축제 단기 운영이라 오래된 로그·스냅샷을 쌓아둘 이유가 없다(스토리지 비용 방지).
resource "aws_s3_bucket_lifecycle_configuration" "shared" {
  bucket = aws_s3_bucket.shared.id

  rule {
    id     = "expire-alb-logs"
    status = "Enabled"

    filter {
      prefix = "alb-logs/"
    }

    expiration {
      days = var.alb_log_retention_days
    }
  }

  rule {
    id     = "expire-etcd-snapshots"
    status = "Enabled"

    filter {
      prefix = "etcd/"
    }

    expiration {
      days = var.etcd_backup_retention_days
    }
  }

  # PKI는 etcd 스냅샷과 짝이 맞아야 복구가 되므로 같은 보존 기간을 쓴다.
  rule {
    id     = "expire-pki-archives"
    status = "Enabled"

    filter {
      prefix = "pki/"
    }

    expiration {
      days = var.etcd_backup_retention_days
    }
  }

  # 중단된 멀티파트 업로드가 남아 조용히 과금되는 것을 막는다.
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ── ALB가 alb-logs/ 에 쓸 수 있게 허용 ─────────────────
# ap-northeast-2는 구형(리전별 ELB 계정) 방식을 쓰므로 서비스 프린시펄이 아니라
# aws_elb_service_account의 ARN을 Principal로 준다.
data "aws_iam_policy_document" "shared_bucket" {
  statement {
    sid    = "AllowALBAccessLogDelivery"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.shared.arn}/alb-logs/*"]
  }

  # 저장 시 암호화(SSE-S3)와 별개로, 평문 HTTP 접근 자체를 거부한다.
  # Deny는 Allow보다 우선하므로 위 ALB 로그 전달에도 동일하게 적용된다(ALB는 HTTPS로 쓴다).
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.shared.arn, "${aws_s3_bucket.shared.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "shared" {
  bucket = aws_s3_bucket.shared.id
  policy = data.aws_iam_policy_document.shared_bucket.json

  # 퍼블릭 차단 설정이 먼저 걸린 뒤 정책을 붙인다.
  depends_on = [aws_s3_bucket_public_access_block.shared]
}
