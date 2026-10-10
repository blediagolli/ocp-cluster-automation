# ── API Load Balancer (NLB) ──

resource "aws_lb" "api" {
  name               = "${var.cluster_name}-api"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-api-nlb"
  })
}

resource "aws_lb_target_group" "api" {
  name     = "${var.cluster_name}-api"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.cluster.id

  health_check {
    protocol            = "HTTPS"
    port                = 6443
    path                = "/readyz"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_lb_target_group_attachment" "api" {
  count            = var.master_count
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.master[count.index].id
  port             = 6443
}

# Machine config server target group (bootstrap phase)
resource "aws_lb_target_group" "mcs" {
  name     = "${var.cluster_name}-mcs"
  port     = 22623
  protocol = "TCP"
  vpc_id   = aws_vpc.cluster.id

  health_check {
    protocol            = "HTTPS"
    port                = 22623
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "mcs" {
  load_balancer_arn = aws_lb.api.arn
  port              = 22623
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcs.arn
  }
}

resource "aws_lb_target_group_attachment" "mcs" {
  count            = var.master_count
  target_group_arn = aws_lb_target_group.mcs.arn
  target_id        = aws_instance.master[count.index].id
  port             = 22623
}

# ── Ingress Load Balancer (NLB) ──

resource "aws_lb" "ingress" {
  name               = "${var.cluster_name}-ingress"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ingress-nlb"
  })
}

# Ingress targets: workers if we have them, otherwise masters (compact)
locals {
  ingress_targets = var.worker_count > 0 ? aws_instance.worker[*].id : aws_instance.master[*].id
  ingress_count   = var.worker_count > 0 ? var.worker_count : var.master_count
}

resource "aws_lb_target_group" "https" {
  name     = "${var.cluster_name}-https"
  port     = 443
  protocol = "TCP"
  vpc_id   = aws_vpc.cluster.id

  health_check {
    protocol            = "TCP"
    port                = 443
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

resource "aws_lb_target_group_attachment" "https" {
  count            = local.ingress_count
  target_group_arn = aws_lb_target_group.https.arn
  target_id        = local.ingress_targets[count.index]
  port             = 443
}

resource "aws_lb_target_group" "http" {
  name     = "${var.cluster_name}-http"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.cluster.id

  health_check {
    protocol            = "TCP"
    port                = 80
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_target_group_attachment" "http" {
  count            = local.ingress_count
  target_group_arn = aws_lb_target_group.http.arn
  target_id        = local.ingress_targets[count.index]
  port             = 80
}
