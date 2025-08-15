locals {
  tags = {
    environment = "dev"
    project     = var.project_name
  }
  region           = var.region
  eks_cluster_name = "${var.project_name}-eks"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.default.token
}
provider "helm" {
  kubernetes = {
    host = module.eks.cluster_endpoint

    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.default.token
  }
}

data "aws_eks_cluster_auth" "default" {
  name = module.eks.cluster_name
  depends_on = [
    module.eks.eks_managed_node_groups,
  ]
}
data "aws_eks_cluster" "default" {
  name = module.eks.cluster_name
  depends_on = [
    module.eks.eks_managed_node_groups,
  ]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.1"

  name                 = "${var.project_name}-eks-vpc"
  cidr                 = "10.${var.eks_network_prefix}.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.${var.eks_network_prefix}.0.0/20", "10.${var.eks_network_prefix}.16.0/20", "10.${var.eks_network_prefix}.32.0/20"]
  public_subnets       = ["10.${var.eks_network_prefix}.48.0/20"]
  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"                 = "1"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                          = "1"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
  }
  tags = local.tags
}


module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0"

  role_name             = "${local.eks_cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name                         = local.eks_cluster_name
  kubernetes_version           = var.kubernetes_version
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["${var.eks_public_endpoint_cidr}/32"]

  addons = {
    kube-proxy = {}
    coredns    = {}
    aws-ebs-csi-driver = {
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  eks_managed_node_groups = {
    default_node_group = {
      ami_type      = var.eks_ami_type
      instance_type = var.eks_node_type
      min_size      = var.eks_min_nodes
      max_size      = var.eks_max_nodes
      desired_size  = var.eks_asg_desired_capacity
    }
  }

  tags = local.tags
}

resource "null_resource" "delete_aws_cni" {
  provisioner "local-exec" {
    command = "curl -s -k -XDELETE -H 'Authorization: Bearer ${data.aws_eks_cluster_auth.default.token}' -H 'Accept: application/json' -H 'Content-Type: application/json' '${data.aws_eks_cluster.default.endpoint}/apis/apps/v1/namespaces/kube-system/daemonsets/aws-node'"
  }
  depends_on = [module.eks]
}

resource "null_resource" "delete_kube_proxy" {
  provisioner "local-exec" {
    command = "curl -s -k -XDELETE -H 'Authorization: Bearer ${data.aws_eks_cluster_auth.default.token}' -H 'Accept: application/json' -H 'Content-Type: application/json' '${data.aws_eks_cluster.default.endpoint}/apis/apps/v1/namespaces/kube-system/daemonsets/kube-proxy'"
  }
  depends_on = [module.eks, null_resource.delete_aws_cni]
}


resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  namespace  = "kube-system"
  version    = "1.17.4"

  values = [
    yamlencode({
      eni = {
        enabled = true
      }
      ipam = {
        mode = "eni"
      }
      egressMasqueradeInterfaces = "eth+"
      routingMode                = "native"
      kubeProxyReplacement       = true
      k8sServiceHost             = trim(data.aws_eks_cluster.default.endpoint, "https://")
      k8sServicePort             = 443
      hubble = {
        relay = {
          enabled = true
        }
        ui = {
          enabled = true
        }
      }
    })
  ]

  depends_on = [
    module.eks,
    null_resource.delete_aws_cni,
    null_resource.delete_kube_proxy
  ]
}

resource "aws_kms_key" "eks" {
  description             = "eks cluster key for secret encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(
    local.tags
  )
}

resource "aws_kms_alias" "eks" {
  name          = "alias/eks-${local.eks_cluster_name}"
  target_key_id = aws_kms_key.eks.key_id
}