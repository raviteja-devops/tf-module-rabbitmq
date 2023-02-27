resource "aws_iam_role" "role" {
  name = "${var.env}-${var.component}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(
    local.common_tags,
    { Name = "${var.env}-${var.component}-role" }
  )
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.env}-${var.component}-role"
  role = aws_iam_role.role.name
}

resource "aws_iam_policy" "policy" {
  name        = "${var.env}-${var.component}-parameter-store-policy"
  path        = "/"
  description = "${var.env}-${var.component}-parameter-store-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath",
          "ssm:GetParameters",
          "ssm:GetParameter"
        ],
        "Resource" : [
          "arn:aws:ssm:us-east-1:867319901157:parameter/${var.env}.${var.component}*"
        ]
      },
      {
        "Sid" : "VisualEditor1",
        "Effect" : "Allow",
        "Action" : "ssm:DescribeParameters",
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "role-attach" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy.arn
}


resource "aws_security_group" "rabbitmq" {
  name        = "${var.env}-rabbitmq-security-group"
  description = "${var.env}-rabbitmq-security-group"
  vpc_id      = var.vpc_id
  ingress {
    description      = "RabbitMQ"
    from_port        = 5672
    to_port          = 5672
    protocol         = "tcp"
    cidr_blocks      = var.allow_cidr
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_cidr
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  tags = merge(
    local.common_tags,
    { Name = "${var.env}-rabbitmq-security-group" }
  )
}


#resource "aws_mq_configuration" "rabbitmq" {
#  description    = "${var.env}-rabbitmq-configuration"
#  name           = "${var.env}-rabbitmq-configuration"
#  engine_type    = var.engine_type
#  engine_version = var.engine_version
#  data = ""
#}

# We moved from service to ec2 node for rabbitmq , because our app does not support it.

#resource "aws_mq_broker" "rabbitmq" {
#  broker_name        = "${var.env}-rabbitmq"
#  deployment_mode    = var.deployment_mode
#  engine_type        = var.engine_type
#  engine_version     = var.engine_version
#  host_instance_type = var.host_instance_type
#  security_groups    = [aws_security_group.rabbitmq.id]
#  subnet_ids         = var.deployment_mode == "SINGLE_INSTANCE" ? [var.subnet_ids[0]] : var.subnet_ids
## if deployment mode is single instance then [var.subnet_ids[0] is the value, ifnot take all subnet id's
#
##  configuration {
##    id       = aws_mq_configuration.rabbitmq.id
##    revision = aws_mq_configuration.rabbitmq.latest_revision
##  }
#
#  encryption_options {
#    use_aws_owned_key = false
#    kms_key_id = data.aws_kms_key.key.arn
#  }
#
#  user {
#    username = data.aws_ssm_parameter.USER.value
#    password = data.aws_ssm_parameter.PASS.value
#  }
#}


resource "aws_spot_instance_request" "rabbitmq" {
  ami                    = data.aws_ami.centos8.image_id
  instance_type          = "t3.small"
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.rabbitmq.id]
  wait_for_fulfillment   = true
  user_data              = base64encode(templatefile("${path.module}/user-data.sh", { component = "rabbitmq", env = var.env }))
  iam_instance_profile   = aws_iam_instance_profile.profile.name
# it creates the spot request and comes out, but using "wait_for_fulfillment" waits for the server to create,
# because before going to route 53 record creation, server needs to be ready to fetch privateIP
  tags = merge(
    local.common_tags,
    { Name = "${var.env}-rabbitmq" }
  )
}

resource "aws_route53_record" "rabbitmq" {
  zone_id = "Z040944033CUGWUDK9I6T"
  name    = "rabbitmq-${var.env}.raviteja.online"
  type    = "A"
  ttl     = 30
  records = [aws_spot_instance_request.rabbitmq.private_ip]
}