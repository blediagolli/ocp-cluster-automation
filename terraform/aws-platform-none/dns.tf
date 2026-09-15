# ── Route53 DNS Records ──

resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.base.zone_id
  name    = "api.${var.cluster_name}.${var.base_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.api.dns_name
    zone_id                = aws_lb.api.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_int" {
  zone_id = data.aws_route53_zone.base.zone_id
  name    = "api-int.${var.cluster_name}.${var.base_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.api.dns_name
    zone_id                = aws_lb.api.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apps" {
  zone_id = data.aws_route53_zone.base.zone_id
  name    = "*.apps.${var.cluster_name}.${var.base_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ingress.dns_name
    zone_id                = aws_lb.ingress.zone_id
    evaluate_target_health = false
  }
}
