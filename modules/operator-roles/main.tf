data "rhcs_rosa_operator_roles" "operator_roles" {
  operator_role_prefix = var.operator_role_prefix
  account_role_prefix  = var.account_role_prefix

  lifecycle {
    # The operator_iam_roles should contains 6 elements 
    postcondition {
      condition     = length(self.operator_iam_roles) == 6
      error_message = "The list of operator roles should contains 6 elements."
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "operator_role" {
  count = 6

  name                 = data.rhcs_rosa_operator_roles.operator_roles.operator_iam_roles[count.index].role_name
  path                 = var.path
  permissions_boundary = var.permissions_boundary

  assume_role_policy = data.aws_iam_policy_document.custom_trust_policy[count.index].json

  tags = merge(var.tags, {
    red-hat-managed = true
    // TODO nargaman always empty?
    rosa_cluster_id    = var.cluster_id
    operator_namespace = data.rhcs_rosa_operator_roles.operator_roles.operator_iam_roles[count.index].operator_namespace
    operator_name      = data.rhcs_rosa_operator_roles.operator_roles.operator_iam_roles[count.index].operator_name
  })
}

resource "aws_iam_role_policy_attachment" "operator_role_policy_attachment" {
  count = 6

  role       = aws_iam_role.operator_role[count.index].name
  policy_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${data.rhcs_rosa_operator_roles.operator_roles.operator_iam_roles[count.index].policy_name}"
}

data "aws_iam_policy_document" "custom_trust_policy" {
  count = 6

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.oidc_endpoint_url}"]
    }
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "${var.oidc_endpoint_url}:sub"
      values   = data.rhcs_rosa_operator_roles.operator_roles.operator_iam_roles[count.index].service_accounts
    }
  }
}

# Wait 20 seconds after the operator role is created in order to avoid error in cluster create
resource "time_sleep" "role_resources_propagation" {
  create_duration = "20s"

  triggers = {
    operator_role_prefix = var.operator_role_prefix
    operator_role_arns   = "[ ${join(", ", aws_iam_role.operator_role[*].arn)} ]"
  }
}
