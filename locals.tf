
locals {
  name                   = var.cluster_name
  name_unique_id         = random_id.uniquename.id
  cluster_domain_basedns   = var.cluster_domain_internal
  cluster_domain_validate =  "${var.cluster_name}.${var.cluster_domain_external}"
  cluster_kubeapi_dns = var.cluster_domain_external == "" ? aws_lb.kubeingress.dns_name : "kubeapi.${var.cluster_name}.${var.cluster_domain_external}"
  s3_kubeconfig_filename = "kubeconfig"
  common_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    KubernetesCluster                           = var.cluster_name
  }
  default_worker_instance_type    = "t3.medium"
  default_worker_root_volume_size = 50
  default_worker_node_labels = [
    #  "node-role.kubernetes.io/worker=true"
  ]
  default_master_node_taints = var.enable_scheduling_on_master == true ? [] : ["node-role.kubernetes.io/master:NoSchedule"]
  worker_groups_map = {
    for idx, node_group_config in var.worker_node_groups :
    join("-",[node_group_config.name,idx]) => {
      name                          = node_group_config.name
      index                         = idx
      
      # Use sort() function to make sure the variable is a list.
      node_taints = join(" ",
        [for taint in sort(lookup(node_group_config, "node_taints", [])) :
          "--node-taint \"${taint}\""
      ])
      node_labels = join(" ",
        [for label in concat(sort(lookup(node_group_config, "node_labels", [])), local.default_worker_node_labels) :
          "--node-label \"${label}\""
      ])
      
      min_size                      = node_group_config.min_size
      max_size                      = node_group_config.max_size
      desired_capacity              = lookup(node_group_config, "desired_capacity", node_group_config.min_size)
      root_volume_size              = lookup(node_group_config, "root_volume_size", local.default_worker_root_volume_size)
      instance_type                 = lookup(node_group_config, "instance_type", local.default_worker_instance_type)
      additional_security_group_ids = sort(lookup(node_group_config, "additional_security_group_ids", []))
      daily_shutdown_utc            = lookup(node_group_config, "daily_shutdown_utc", "")
       
      tags = [
        for tag_key, tag_val in merge(lookup(node_group_config, "tags", {}), local.common_tags, { Name = join("-", [var.cluster_name,node_group_config.name]), Description = join("-", [var.cluster_name,node_group_config.name]) }) :
        {
          key                 = tag_key
          value               = tag_val
          propagate_at_launch = true
        }
      ]
    }
  }
  
  worker_groups_map_with_schedule = {
    for worker_group_name, worker_group in local.worker_groups_map : worker_group_name => worker_group if worker_group.daily_shutdown_utc != ""
  }

  master_tags = merge(var.master_additional_tags, local.common_tags, { Name = join("-", [var.cluster_name,"master"]), Description = join("-", [var.cluster_name,"master"]) })
  
  master_tags_asg = [
    for tag_key, tag_val in local.master_tags : {
      key                 = tag_key
      value               = tag_val
      propagate_at_launch = true
    }
  ]

  master_node_labels = join(" ",
    [for label in var.master_node_labels :
      "--node-label \"${label}\""
  ])
  master_node_taints = join(" ",
    [for taint in concat(var.master_node_taints, local.default_master_node_taints) :
      "--node-taint \"${taint}\""
  ])
  extra_api_args = join(" ",
    [for key, value in var.extra_api_args :
      "--kube-apiserver-arg \"${key}=${value}\""
  ])
  custom_args = join(" ", var.extra_args)

  master_iam_policy_default = file("${path.module}/policies/master.json")
  worker_iam_policy_default = file("${path.module}/policies/worker.json")
  asg_list = join(",", [for key, value in aws_autoscaling_group.worker :
    value.name
  ])
  
  # useful for the scheduling actions
  current_time_utc = timestamp()
  current_day_utc = formatdate("YYYY-MM-DD", local.current_time_utc)

  # the cloudinit_config template files
  cloudinit_config_master = [
    for index in range(var.master_node_count) : 
      base64gzip(
        templatefile(
                "${path.module}/files/k3s.tpl.sh",
                {
                  instance_role    = "master"
                  instance_index   = index
                  k3s_server_token = random_password.k3s_server_token.result
                  k3s_version      = var.k3s_version
                  cluster_name     = var.cluster_name
                  cluster_domain_basedns   = local.cluster_domain_basedns
                  cluster_kubeapi_dns      = local.cluster_kubeapi_dns
                  s3_bucket        = var.s3_bucket
                  node_labels      = local.master_node_labels
                  node_taints      = local.master_node_taints
                  extra_args       = "${local.custom_args} ${local.extra_api_args}"
                  kubeconfig_name  = local.s3_kubeconfig_filename
                }
        )
      )
  ]

  cloudinit_config_workers = {
    for worker_group_name, worker_group in local.worker_groups_map : 
    worker_group_name => base64gzip(
        templatefile(
                "${path.module}/files/k3s.tpl.sh",
                {
                  instance_role    = "worker"
                  instance_index   = "null"
                  k3s_server_token = random_password.k3s_server_token.result
                  k3s_version      = var.k3s_version
                  cluster_name     = var.cluster_name
                  cluster_domain_basedns   = local.cluster_domain_basedns
                  cluster_kubeapi_dns      = local.cluster_kubeapi_dns
                  node_labels      = worker_group.node_labels
                  node_taints      = worker_group.node_taints
                  s3_bucket        = ""
                  extra_args       = ""
                  kubeconfig_name  = ""
                }
              )
    )
  }
}

resource "null_resource" "validate_domain_length" {
  provisioner "local-exec" {
    command = var.cluster_domain_external == "" ? "exit 0" : "if [ ${length(local.cluster_domain_validate)} -ge 38 ]; then echo \"ERR: \nThe length of the domain for kubeapi (domain:${local.cluster_domain_validate}, length:${length(local.cluster_domain_validate)}) must not exceed 37 characters.\nDomain name includes variables 'var.cluster_name' (${var.cluster_name}) and 'var.cluster_domain_external' (${var.cluster_domain_external}).\nCheck the length of these variables.\" ; exit 1; fi"
  }
}
