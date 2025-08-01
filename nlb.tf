resource "aws_lb" "kubeingress" {
  name               = substr("${local.name_unique_id}-kubeingress", 0, 32)
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnets
  security_groups    = [aws_security_group.kubeingress.id]
  tags               = local.common_tags
  enable_cross_zone_load_balancing = var.enable_nlb_cross_az
  
  # depends_on = [
  #   null_resource.validate_domain_length
  # ]
}

resource "aws_lb_listener" "kubeapi" {
  load_balancer_arn = aws_lb.kubeingress.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kubeapi.arn
  }
  
  lifecycle {
    replace_triggered_by = [
      aws_lb_target_group.kubeapi.arn
    ]
  }
}

resource "aws_lb_target_group" "kubeapi" {
  name     = substr("${local.name_unique_id}-kubeapi", 0, 32)
  port     = 6443
  protocol = "TCP"
  vpc_id   = data.aws_subnet.private_subnet[0].vpc_id
  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 6443
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  stickiness {
    enabled = false
    type    = "source_ip"
  }
  tags = local.common_tags
}

resource "aws_route53_record" "alb_ingress" {
  count           = var.cluster_domain_external == "" ? 0 : 1
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.cluster_domain_external_zone.0.id
  name            = local.cluster_kubeapi_dns
  type            = "A"

  alias {
    name                   = aws_lb.kubeingress.dns_name
    zone_id                = aws_lb.kubeingress.zone_id
    evaluate_target_health = false
  }
}

resource "aws_lb_listener" "kubeingress_http" {
  load_balancer_arn = aws_lb.kubeingress.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kubeingress_http.arn
  }
  
  lifecycle {
    replace_triggered_by = [
      aws_lb_target_group.kubeingress_http.arn
    ]
  }
}

resource "aws_lb_target_group" "kubeingress_http" {
  name     = substr("${local.name_unique_id}-http", 0, 32)
  port     = 30080
  protocol = "TCP"
  vpc_id   = data.aws_subnet.private_subnet[0].vpc_id
  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 30080
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  stickiness {
    enabled = false
    type    = "source_ip"
  }
  tags = local.common_tags
}

resource "aws_route53_record" "kubeingress_http" {
  count           = var.cluster_domain_external == "" ? 0 : 1
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.cluster_domain_external_zone.0.id
  name            = "http.${var.cluster_name}.${var.cluster_domain_external}"
  type            = "A"

  alias {
    name                   = aws_lb.kubeingress.dns_name
    zone_id                = aws_lb.kubeingress.zone_id
    evaluate_target_health = false
  }
}

resource "aws_lb_listener" "kubeingress_tls_passthrough" {
  load_balancer_arn = aws_lb.kubeingress.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kubeingress_tls.arn
  }
  
  lifecycle {
    replace_triggered_by = [
      aws_lb_target_group.kubeingress_tls.arn
    ]
  }
}

resource "aws_lb_target_group" "kubeingress_tls" {
  name     = substr("${local.name_unique_id}-tls", 0, 32)
  port     = 30443
  protocol = "TCP"
  vpc_id   = data.aws_subnet.private_subnet[0].vpc_id
  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 30443
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  stickiness {
    enabled = false
    type    = "source_ip"
  }
  tags = local.common_tags
}

resource "aws_route53_record" "kubeingress_tls_passthrough" {
  count           = var.cluster_domain_external == "" ? 0 : 1
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.cluster_domain_external_zone.0.id
  name            = "tls.${var.cluster_name}.${var.cluster_domain_external}"
  type            = "A"

  alias {
    name                   = aws_lb.kubeingress.dns_name
    zone_id                = aws_lb.kubeingress.zone_id
    evaluate_target_health = false
  }
}