locals {
  create_role       = local.enabled && length(var.node_role_arn) == 0
  aws_policy_prefix = format("arn:%s:iam::aws:policy", join("", data.aws_partition.current.*.partition))
  node_role_arn     = format("arn:aws:iam::%s:role/%s", join("", data.aws_caller_identity.current.*.account_id), module.label.id)
}

data "aws_partition" "current" {
  count = local.create_role ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = local.enabled ? 1 : 0
}

data "aws_iam_policy_document" "assume_role" {
  count = local.create_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }

  dynamic "statement" {
    for_each = var.node_role_explicit_self_trust ? [1] : []
    content {
      sid = "AllowSelfAssume"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = [local.node_role_arn]
      }
    }
  }
}

data "aws_iam_policy_document" "amazon_eks_worker_node_autoscale_policy" {
  count = (local.create_role && var.worker_role_autoscale_iam_enabled) ? 1 : 0
  statement {
    sid = "AllowToScaleEKSNodeGroupAutoScalingGroup"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "amazon_eks_worker_node_autoscale_policy" {
  count  = (local.create_role && var.worker_role_autoscale_iam_enabled) ? 1 : 0
  name   = "${module.label.id}-autoscale"
  policy = join("", data.aws_iam_policy_document.amazon_eks_worker_node_autoscale_policy.*.json)
}

resource "aws_iam_role" "default" {
  count                = local.create_role ? 1 : 0
  name                 = module.label.id
  assume_role_policy   = join("", data.aws_iam_policy_document.assume_role.*.json)
  permissions_boundary = var.permissions_boundary
  tags                 = module.label.tags
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  count      = local.create_role ? 1 : 0
  policy_arn = format("%s/%s", local.aws_policy_prefix, "AmazonEKSWorkerNodePolicy")
  role       = join("", aws_iam_role.default.*.name)
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_autoscale_policy" {
  count      = (local.create_role && var.worker_role_autoscale_iam_enabled) ? 1 : 0
  policy_arn = join("", aws_iam_policy.amazon_eks_worker_node_autoscale_policy.*.arn)
  role       = join("", aws_iam_role.default.*.name)
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  count      = local.create_role ? 1 : 0
  policy_arn = format("%s/%s", local.aws_policy_prefix, "AmazonEKS_CNI_Policy")
  role       = join("", aws_iam_role.default.*.name)
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  count      = local.create_role ? 1 : 0
  policy_arn = format("%s/%s", local.aws_policy_prefix, "AmazonEC2ContainerRegistryReadOnly")
  role       = join("", aws_iam_role.default.*.name)
}

resource "aws_iam_role_policy_attachment" "existing_policies_for_eks_workers_role" {
  for_each   = local.create_role ? toset(var.existing_workers_role_policy_arns) : []
  policy_arn = each.value
  role       = join("", aws_iam_role.default.*.name)
}
