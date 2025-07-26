resource "aws_launch_template" "master" {
  count         = var.master_node_count
  name_prefix   = substr("${local.name_unique_id}-master-${count.index}", 0, 32)
  image_id      = data.aws_ami.default_ami.id
  instance_type = var.master_instance_type
  user_data     = local.cloudinit_config_master[count.index]
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
  
  tag_specifications {
    resource_type = "instance"
    tags =  local.master_tags
  }
  
  tags = local.common_tags
}

resource "aws_launch_template" "worker" {
  for_each      = local.worker_groups_map
  name_prefix   = substr("${local.name_unique_id}-worker-${each.key}", 0, 32)
  image_id      = data.aws_ami.default_ami.id
  instance_type = each.value.instance_type
  user_data     = local.cloudinit_config_workers[each.key]
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

  credit_specification {
    cpu_credits = "standard"
  }

  network_interfaces {
    delete_on_termination = true
    security_groups       = concat([aws_security_group.worker.id], each.value.additional_security_group_ids)
  } 
  
  tag_specifications {
    resource_type = "instance"
    tags = each.value.tags
  }

  tags = local.common_tags
}

resource "aws_autoscaling_group" "master" {
  count               = var.enable_asg_master_nodes ? var.master_node_count : 0
  name_prefix         = substr("${local.name_unique_id}-master-${count.index}", 0, 32)
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
    aws_lb.kubeingress
  ]
}

resource "aws_instance" "master" {
  count         = var.enable_asg_master_nodes ? 0 : var.master_node_count 

  launch_template {
    id      = aws_launch_template.master[count.index].id
    version = "1"
  }

  tags = local.master_tags
  
  depends_on = [
    aws_lb.kubeingress,
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
  name_prefix         = substr("${local.name_unique_id}-worker-${each.key}", 0, 32)
  max_size            = each.value.max_size
  min_size            = each.value.min_size
  desired_capacity    = each.value.desired_capacity
  vpc_zone_identifier = var.private_subnets

  target_group_arns = [
    aws_lb_target_group.kubeingress_http.arn,
    aws_lb_target_group.kubeingress_tls.arn
  ]

  launch_template {
    id      = aws_launch_template.worker[each.key].id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = each.value.tags_asg
    content {
      key                 = tag.value.key
      propagate_at_launch = tag.value.propagate_at_launch
      value               = tag.value.value
    }
  }

  depends_on = [
    aws_lb.kubeingress,
    aws_autoscaling_group.master,
    aws_instance.master
  ]
}

resource "aws_autoscaling_schedule" "worker_daily_shutdown" {
  for_each = local.worker_groups_map_with_daily_shutdown_schedule
  scheduled_action_name  = substr("shutdown-${each.key}-${local.name_unique_id}", 0, 32)
  min_size               = 0
  max_size               = 0
  desired_capacity       = 0
  recurrence             = each.value.cron_shutdown_utc
  time_zone              = "Etc/UTC"
  start_time             = timeadd(local.current_time_utc, "5m")
  autoscaling_group_name = aws_autoscaling_group.worker[each.key].name
}

resource "aws_autoscaling_schedule" "worker_daily_startup" {
  for_each = local.worker_groups_map_with_daily_startup_schedule
  scheduled_action_name  = substr("startup-${each.key}-${local.name_unique_id}", 0, 32)
  max_size               = each.value.max_size
  min_size               = each.value.min_size
  desired_capacity       = each.value.desired_capacity
  recurrence             = each.value.cron_startup_utc
  time_zone              = "Etc/UTC"
  start_time             = timeadd(local.current_time_utc, "5m")
  autoscaling_group_name = aws_autoscaling_group.worker[each.key].name
}