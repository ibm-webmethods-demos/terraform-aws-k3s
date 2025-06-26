data "aws_subnet" "private_subnet" {
  count = length(var.private_subnet)
  id    = var.private_subnet[count.index]
}

resource "aws_ec2_tag" "private_subnet_tag_cluster" {
  count       = length(var.private_subnet)
  resource_id = data.aws_subnet.private_subnet[count.index].id
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "owned"
}

resource "aws_ec2_tag" "private_subnet_tag_elb" {
  count       = length(var.private_subnet)
  resource_id = data.aws_subnet.private_subnet[count.index].id
  key         = "kubernetes.io/role/elb"
  value       = "1"
}
