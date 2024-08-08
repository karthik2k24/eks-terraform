provider "aws" {
  region = "us-east-1"
}

resource "aws_eks_cluster" "terraform_cluster" {
  name     = "terraform-training-cluster"
  role_arn = aws_iam_role.terraform_cluster_role.arn
  vpc_config {
    subnet_ids = ["subnet-045c906106486c53c", "subnet-08d22b6dfa0eaf3cb", "subnet-016ad0ad7d5ebbc8d"]
  }
  depends_on = [
    aws_iam_role.terraform_cluster_role
  ]
}

resource "aws_eks_node_group" "terraform_nodegroup" {
  cluster_name    = aws_eks_cluster.terraform_cluster.name
  node_group_name = "terraform-node-group"
  node_role_arn   = aws_iam_role.terraform_node_role.arn
  subnet_ids      = ["subnet-045c906106486c53c", "subnet-08d22b6dfa0eaf3cb", "subnet-016ad0ad7d5ebbc8d"]
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }
  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }


  depends_on = [
    aws_eks_cluster.terraform_cluster,
    aws_iam_role.terraform_node_role,
    aws_iam_role_policy_attachment.terraform_cluster_role-AmazonEKSClusterPolicy
  ]
}

resource "aws_iam_role" "terraform_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
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
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_launch_template" "eks_nodes" {
  instance_type = "m5.large"
  tag_specifications {
    resource_type = "instance"
    tags = {
      "Name" = aws_eks_cluster.terraform_cluster.name
    }
  }
}


#resource "aws_iam_role_policy_attachment" "eks_role_attachment" {
#  role       = aws_iam_role.terraform_cluster_role.name
#  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
#}
#
#-----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "terraform_cluster_role-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.terraform_cluster_role.name
}


resource "aws_iam_role_policy_attachment" "terraform_cluster_role-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.terraform_node_role.name
}

#resource "aws_iam_role_policy_attachment" "terraform_cluster_role-AmazonEC2ContainerRegistryReadOnly" {
#  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#  role       = aws_iam_role.terraform_node_role.name
#}


resource "aws_iam_role_policy_attachment" "terraform_cluster_role-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.terraform_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "terraform_cluster_role-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.terraform_cluster_role.name
}



resource "aws_eks_addon" "vpc_cni_addon" {
  cluster_name = aws_eks_cluster.terraform_cluster.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns_addon" {
  cluster_name                = aws_eks_cluster.terraform_cluster.name
  addon_name                  = "coredns"
  addon_version               = "v1.11.1-eksbuild.6"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "kubeproxy_addon" {
  cluster_name       = aws_eks_cluster.terraform_cluster.name
  addon_name         = "kube-proxy"
  addon_version = "v1.29.1-eksbuild.2"
}
