provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "my_vpc"
  }
}

# List of availability zones and corresponding CIDR blocks
locals {
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  subnet_cidrs       = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
}

# Subnets in each availability zone
resource "aws_subnet" "my_subnets" {
  for_each          = zipmap(local.availability_zones, local.subnet_cidrs)
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "subnet-${each.key}"
  }
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

resource "aws_eks_cluster" "terraform_cluster" {
  name     = "terraform-training-cluster"
  role_arn = aws_iam_role.terraform_cluster_role.arn
  vpc_config {
    subnet_ids = [for subnet in aws_subnet.my_subnets : subnet.id]
  }

  depends_on = [
    aws_iam_role.terraform_cluster_role
  ]
}

resource "aws_eks_node_group" "terraform_nodegroup" {
  cluster_name    = aws_eks_cluster.terraform_cluster.name
  node_group_name = "terraform-node-group"
  node_role_arn   = aws_iam_role.terraform_node_role.arn
  subnet_ids      = [for subnet in aws_subnet.my_subnets : subnet.id]
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 2
  }

  depends_on = [
    aws_eks_cluster.terraform_cluster,
    aws_iam_role.terraform_node_role,
    aws_iam_role_policy_attachment.terraform_cluster_role_AmazonEKSClusterPolicy
  ]
}

resource "aws_iam_role" "terraform_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "terraform_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_launch_template" "eks_nodes" {
  instance_type = "t2.micro"

  tag_specifications {
    resource_type = "instance"
    tags = {
      "Name" = "${aws_eks_cluster.terraform_cluster.name}-node"
    }
  }
}

resource "aws_iam_role_policy_attachment" "terraform_cluster_role_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.terraform_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "terraform_cluster_role_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.terraform_node_role.name
}

resource "aws_iam_role_policy_attachment" "terraform_cluster_role_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.terraform_node_role.name
}

resource "aws_iam_role_policy_attachment" "terraform_cluster_role_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.terraform_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "terraform_cluster_role_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.terraform_node_role.name
}

resource "aws_eks_addon" "vpc_cni_addon" {
  cluster_name = aws_eks_cluster.terraform_cluster.name
  addon_name   = "vpc-cni"

  depends_on = [
    aws_eks_cluster.terraform_cluster
  ]
}

resource "aws_eks_addon" "coredns_addon" {
  cluster_name                = aws_eks_cluster.terraform_cluster.name
  addon_name                  = "coredns"
  addon_version               = "v1.11.1-eksbuild.9"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_cluster.terraform_cluster
  ]
}

resource "aws_eks_addon" "kubeproxy_addon" {
  cluster_name  = aws_eks_cluster.terraform_cluster.name
  addon_name    = "kube-proxy"
  addon_version = "v1.30.0-eksbuild.3"

  depends_on = [
    aws_eks_cluster.terraform_cluster
  ]
}
