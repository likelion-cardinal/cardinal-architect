locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  # 기본은 와일드카드 1장. apex(cardinal.kr)는 와일드카드가 커버하지 않으므로
  # domain_name과 *.domain_name을 함께 넣어야 둘 다 TLS가 된다.
  sans = var.subject_alternative_names != null ? var.subject_alternative_names : ["*.${var.domain_name}"]
}

# ── Public Hosted Zone ───────────────────────────────
# 가비아 관리 콘솔의 네임서버를 이 Zone의 NS 4개로 바꿔야 위임이 성립한다.
# (name_servers 출력값 참고. 전파에 보통 수십 분~수 시간)
resource "aws_route53_zone" "this" {
  name = var.domain_name

  tags = merge(local.tags, { Name = "${local.name}-zone" })
}

# ═══════════════════════════════════════════════════════
#  ACM 인증서 (DNS 검증)
#  ALB에 붙일 것이므로 ALB와 같은 리전에 발급한다.
# ═══════════════════════════════════════════════════════
resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = local.sans
  validation_method         = "DNS"

  tags = merge(local.tags, { Name = "${local.name}-cert" })

  # 인증서 교체 시 리스너가 참조하는 동안 삭제되지 않도록 새 것을 먼저 만든다.
  lifecycle {
    create_before_destroy = true
  }
}

# 검증용 CNAME.
# apex(cardinal.kr)와 와일드카드(*.cardinal.kr)는 ACM이 요구하는 검증 레코드가 완전히 동일하다.
# 그대로 for_each를 돌리면 같은 CNAME 하나를 두 리소스가 소유해 destroy 때 충돌하므로,
# apex의 와일드카드만 제외한다(다른 SAN은 각자 고유한 레코드를 가지므로 남긴다).
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
    if dvo.domain_name != "*.${var.domain_name}"
  }

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  # 인증서를 다시 만들면 같은 이름의 레코드가 이미 있을 수 있다.
  allow_overwrite = true
}

# 발급 완료를 기다리는 "게이트". 리소스를 만드는 게 아니라 상태를 확인할 뿐이다.
# NS 위임 전에 켜면 timeout까지 apply가 멈추므로 기본은 비활성.
resource "aws_acm_certificate_validation" "this" {
  count = var.wait_for_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]

  timeouts {
    create = var.validation_timeout
  }
}
