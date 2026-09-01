locals {
  name = "${var.project}-${var.env}"
  tags = merge(var.tags, {
    Project = var.project
    Env     = var.env
  })

  doc_name = "${local.name}-cp-devops"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ═══════════════════════════════════════════════════════
#  커스텀 세션 문서
#  기본 문서(SSM-SessionManagerRunShell)를 주면 ssm-user로 붙는데, SSM Agent가
#  /etc/sudoers.d/ssm-agent-users로 ssm-user에 NOPASSWD ALL을 깔아둔다.
#  즉 "셸만 줬다"고 생각해도 실제로는 root이고, root면 /etc/kubernetes/admin.conf로
#  cluster-admin이다. 그래서 실행할 명령을 문서에 못박아 devops 계정으로 떨어뜨린다.
# ═══════════════════════════════════════════════════════
resource "aws_ssm_document" "cp_devops" {
  name            = local.doc_name
  document_type   = "Session"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "1.0"
    description   = "cardinal ${var.env}: dev team shell on control plane as ${var.session_linux_user}"
    sessionType   = "InteractiveCommands"
    properties = {
      linux = {
        # runAsElevated로 root에서 시작해 곧바로 대상 계정으로 내려간다.
        # 로그인 셸(-i)이라 devops의 ~/.kube/config를 그대로 집는다.
        commands      = "/usr/bin/sudo -iu ${var.session_linux_user}"
        runAsElevated = true
      }
    }
  })

  tags = merge(local.tags, { Name = local.doc_name })
}

# ═══════════════════════════════════════════════════════
#  개발팀 IAM 그룹
#  유저 생성·액세스 키 발급은 콘솔에서 하고, 이 그룹에 넣기만 하면 된다.
# ═══════════════════════════════════════════════════════
resource "aws_iam_group" "dev" {
  name = "${local.name}-dev-db-access"
}

data "aws_iam_policy_document" "dev" {
  # CP 인스턴스를 ID가 아니라 태그로 잡는다. AMI 교체로 CP가 replacement되면
  # ID가 바뀌는데, 그때마다 정책을 고치기로 하면 반드시 잊는다.
  statement {
    sid       = "StartSessionOnControlPlane"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Role"
      values   = [var.control_plane_role_tag]
    }
  }

  # 세션에 쓸 수 있는 문서는 위에서 만든 것 하나뿐. 기본 문서를 여기 넣지 않는
  # 것이 핵심이다(넣는 순간 root 셸이 된다).
  statement {
    sid       = "UseDevopsSessionDocumentOnly"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = [aws_ssm_document.cp_devops.arn]
  }

  # 자기가 연 세션만 끊고 재개한다.
  statement {
    sid     = "ManageOwnSession"
    effect  = "Allow"
    actions = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:session/$${aws:username}-*",
    ]
  }
}

resource "aws_iam_group_policy" "dev" {
  name   = "${local.name}-dev-db-access"
  group  = aws_iam_group.dev.name
  policy = data.aws_iam_policy_document.dev.json
}
