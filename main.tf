provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "my_vpc" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = "my_terraform_vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my_terraform_igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public_route_table"
  }
}

resource "aws_route_table_association" "public_subnet_assoc" {
  for_each = aws_subnet.my_subnets
  subnet_id = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

locals {
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  subnet_cidrs       = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
}

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

resource "aws_security_group" "eks_cluster_sg" {
  name   = "eks-cluster-sg"
  vpc_id = aws_vpc.my_vpc.id

  # Allow DNS traffic (TCP/UDP on port 53) inbound and outbound
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "node_group_sg" {
  name   = "node-group-sg"
  vpc_id = aws_vpc.my_vpc.id

  # Allow inbound traffic from the EKS cluster security group on port 443
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
  }
 #SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP traffic from the internet
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS traffic from the internet
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow traffic on port 10250 for Kubernetes communication
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # Allow DNS traffic (TCP/UDP on port 53)
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_eks_cluster" "terraform_cluster" {
  name     = "terraform-training-cluster"
  role_arn = aws_iam_role.terraform_cluster_role.arn

  vpc_config {
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
    subnet_ids = [for subnet in aws_subnet.my_subnets : subnet.id]
  }
  version = "1.30"
  depends_on = [
    aws_iam_role.terraform_cluster_role
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
  instance_type = "t3.medium"
  image_id       = "ami-03413b57906e5c8b2"
  key_name = "eks-assignment"
  user_data = base64encode(<<-EOF
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==BOUNDARY=="

    --==BOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"
    MIME-Version: 1.0

    #!/bin/bash
    set -o xtrace
    /etc/eks/bootstrap.sh ${aws_eks_cluster.terraform_cluster.name}

    --==BOUNDARY==--
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      "Name" = "${aws_eks_cluster.terraform_cluster.name}-node"
    }
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.node_group_sg.id]
  }
}

resource "aws_iam_role_policy_attachment" "terraform_cluster_role_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.terraform_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "terraform_cluster_role_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.terraform_cluster_role.name
}
resource "aws_iam_role_policy_attachment" "terraform_node_role_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.terraform_node_role.name
}

resource "aws_iam_role_policy_attachment" "terraform_node_role_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.terraform_node_role.name
}

resource "aws_iam_role_policy_attachment" "terraform_node_role_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.terraform_node_role.name
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
    min_size     = 1
  }
  capacity_type = "SPOT"

  depends_on = [
    aws_iam_role_policy_attachment.terraform_node_role_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.terraform_node_role_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.terraform_node_role_AmazonEC2ContainerRegistryReadOnly
  ]
}

resource "aws_eks_addon" "vpc_cni_addon" {
  cluster_name = aws_eks_cluster.terraform_cluster.name
  addon_name   = "vpc-cni"

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