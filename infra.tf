resource "aws_launch_template" "master" {
  count         = var.master_node_count
  name_prefix   = substr("${local.name}-master-${count.index}", 0, 32)
  image_id      = data.aws_ami.default_ami.id
  instance_type = var.master_instance_type
  user_data     = data.template_cloudinit_config.init-master[count.index].rendered
  key_name      = var.key_name
  
  iam_instance_profile {
    name = aws_iam_instance_profile.master_profile.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      encrypted   = true
      volume_type = "gp2"
      volume_size = var.master_root_volume_size
    }
  }

  credit_specification {
    cpu_credits = "standard"
  }

  network_interfaces {
    delete_on_termination = true
    associate_public_ip_address = false
    security_groups       = concat([aws_security_group.master.id], var.master_security_group_ids)
    subnet_id     = data.aws_subnet.private_subnet[count.index%length(data.aws_subnet.private_subnet)].id
  }
  
  tags = local.common_tags
}

resource "aws_launch_template" "worker" {
  for_each      = local.worker_groups_map
  name_prefix   = substr("${local.name}-worker-${each.key}", 0, 32)
  image_id      = data.aws_ami.default_ami.id
  instance_type = each.value.instance_type
  user_data     = data.template_cloudinit_config.init-worker[each.key].rendered
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.worker_profile.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      encrypted   = true
      volume_type = "gp2"
      volume_size = each.value.root_volume_size
    }
  }

  network_interfaces {
    delete_on_termination = true
    security_groups       = concat([aws_security_group.worker.id], each.value.additional_security_group_ids)
  }

  tags = local.common_tags
}

resource "aws_autoscaling_group" "master" {
  count               = var.enable_asg_master_nodes ? var.master_node_count : 0
  name_prefix         = substr("${local.name}-master-${count.index}", 0, 32)
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  vpc_zone_identifier = var.private_subnets

  target_group_arns = [
    aws_lb_target_group.kubeapi.arn
  ]

  launch_template {
    id      = aws_launch_template.master[count.index].id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = local.master_tags_asg
    content {
      key                 = tag.value.key
      propagate_at_launch = tag.value.propagate_at_launch
      value               = tag.value.value
    }
  }
  depends_on = [
    aws_lb.kubeapi
  ]
}

resource "aws_instance" "master" {
  count         = var.enable_asg_master_nodes ? 0 : var.master_node_count 

  launch_template {
    id      = aws_launch_template.master[count.index].id
    version = "$Latest"
  }

  tags = local.master_tags
  
  depends_on = [
    aws_lb.kubeapi,
    aws_security_group.master
  ]
}

resource "aws_lb_target_group_attachment" "master" {
  count         = var.enable_asg_master_nodes ? 0 : var.master_node_count 
  
  target_group_arn = aws_lb_target_group.kubeapi.arn
  target_id        = aws_instance.master[count.index].id
}

resource "aws_autoscaling_group" "worker" {
  for_each = local.worker_groups_map
  name_prefix         = substr("${local.name}-worker-${each.key}", 0, 32)
  max_size            = each.value.max_size
  min_size            = each.value.min_size
  desired_capacity    = each.value.desired_capacity
  vpc_zone_identifier = var.private_subnets

  launch_template {
    id      = aws_launch_template.worker[each.key].id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = each.value.tags
    content {
      key                 = tag.value.key
      propagate_at_launch = tag.value.propagate_at_launch
      value               = tag.value.value
    }
  }

  depends_on = [
    aws_lb.kubeapi,
    aws_autoscaling_group.master,
    aws_instance.master
  ]
}

resource "aws_autoscaling_schedule" "worker_daily_shutdown" {
  for_each = local.worker_groups_map_with_schedule
  scheduled_action_name  = substr("${local.name}-worker-${each.key}-shutdown", 0, 32)
  min_size               = 0
  max_size               = 0
  desired_capacity       = 0
  recurrence             = "0 0 * * *"

  # the logic is: if time mentionned is in the future compared to current time, use that. if not, add 24h to that time
  start_time             = timecmp("${local.current_day}T${each.value.daily_shutdown_utc}Z",local.current_time) == 1 ? "${local.current_day}T${each.value.daily_shutdown_utc}Z" : timeadd("${local.current_day}T${each.value.daily_shutdown_utc}Z", "24h") 
  autoscaling_group_name = aws_autoscaling_group.worker[each.key].name
}