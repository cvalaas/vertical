module "worker" {
  source       = "github.com/nubisproject/nubis-terraform//worker?ref=v2.1.0"
  region       = "${var.region}"
  environment  = "${var.environment}"
  account      = "${var.account}"
  service_name = "${var.service_name}"
  purpose      = "database"
  ami          = "${var.ami}"
  elb          = "${module.load_balancer_vsql.name}"

  min_instances = 3

  health_check_type         = "ELB"
  wait_for_capacity_timeout = "30m"
  health_check_grace_period = "1200"

  instance_type     = "m4.4xlarge"
  root_storage_size = "1024"

  security_group        = "${aws_security_group.vertical.id}"
  security_group_custom = true
}

# This one is for vsql
module "load_balancer_vsql" {
  source       = "github.com/nubisproject/nubis-terraform//load_balancer?ref=v2.1.0"
  region       = "${var.region}"
  environment  = "${var.environment}"
  account      = "${var.account}"
  service_name = "${var.service_name}-vsql"

  backend_port_http  = "5433"
  backend_port_https = "5433"

  backend_protocol = "https"
  internal         = true

  health_check_target = "TCP:5433"
}

module "dns_vsql" {
  source       = "github.com/nubisproject/nubis-terraform//dns?ref=v2.1.0"
  region       = "${var.region}"
  environment  = "${var.environment}"
  account      = "${var.account}"
  service_name = "${var.service_name}-vsql"
  target       = "${module.load_balancer_vsql.address}"
}

module "rpms" {
  source       = "github.com/nubisproject/nubis-terraform//bucket?ref=v2.1.0"
  region       = "${var.region}"
  environment  = "${var.environment}"
  account      = "${var.account}"
  service_name = "${var.service_name}"
  purpose      = "rpms"
  role         = "${module.worker.role}"
}

provider "aws" {
  region = "${var.region}"
}

module "info" {
  source      = "github.com/nubisproject/nubis-terraform//info?ref=v2.1.0"
  region      = "${var.region}"
  environment = "${var.environment}"
  account     = "${var.account}"
}

resource "tls_private_key" "vertical" {
  algorithm = "RSA"
}

# And a special role to be able to talk to AWS a little
resource "aws_iam_role_policy" "vertical" {
  name   = "vertical-${var.region}-${var.arena}-${var.environment}"
  role   = "${module.worker.role}"
  policy = "${data.aws_iam_policy_document.vertical.json}"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "vertical" {
  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeAddresses",
      "ec2:DescribeVolumes",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeAutoScalingGroups",
    ]

    resources = [
      "*",
    ]
  }
}

# And a custom vertica security group from the world
resource "aws_security_group" "vertical_clients" {
  name_prefix = "${var.service_name}-${var.arena}-${var.environment}-vertical-clients-"

  vpc_id = "${module.info.vpc_id}"

  tags = {
    Name        = "${var.service_name}-${var.arena}-${var.environment}-vertical-clients"
    Arena       = "${var.arena}"
    Region      = "${var.region}"
    Environment = "${var.environment}"
    Backup      = "true"
    Shutdown    = "never"
  }

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    self      = true

    security_groups = [
      "${module.info.ssh_security_group}",
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# And a custom vertica security group from the world
resource "aws_security_group" "vertical" {
  name_prefix = "${var.service_name}-${var.arena}-${var.environment}-vertical-"

  vpc_id = "${module.info.vpc_id}"

  tags = {
    Name        = "${var.service_name}-${var.arena}-${var.environment}-vertical"
    Arena       = "${var.arena}"
    Region      = "${var.region}"
    Environment = "${var.environment}"
    Backup      = "true"
    Shutdown    = "never"
  }

  # HP Vertica client (vsql, ODBC, JDBC, etc) port.
  ingress {
    from_port = 5433
    to_port   = 5433
    protocol  = "tcp"
    self      = true

    security_groups = [
      "${module.load_balancer_vsql.source_security_group_id}",
      "${aws_security_group.vertical_clients.id}",
    ]
  }

  # Intra-cluster communication
  ingress {
    from_port = 5434
    to_port   = 5434
    protocol  = "tcp"
    self      = true
  }

  # HP Vertica spread monitoring.
  ingress {
    from_port = 5433
    to_port   = 5433
    protocol  = "udp"
    self      = true
  }

  # MC-to-node and node-to-node (agent)
  ingress {
    from_port = 5444
    to_port   = 5444
    protocol  = "tcp"
    self      = true
  }

  # Port used to connect to MC from a web browser
  ingress {
    from_port = 5450
    to_port   = 5450
    protocol  = "tcp"
    self      = true

    security_groups = [
      "${aws_security_group.vertical_clients.id}",
      "${module.info.sso_security_group}",
    ]
  }

  # Client connections.
  ingress {
    from_port = 4803
    to_port   = 4803
    protocol  = "tcp"
    self      = true
  }

  # Daemon to Daemon connections.
  ingress {
    from_port = 4803
    to_port   = 4804
    protocol  = "udp"
    self      = true
  }

  # Monitor to Daemon connection.
  ingress {
    from_port = 6543
    to_port   = 6543
    protocol  = "udp"
    self      = true
  }

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    self      = true

    security_groups = [
      "${module.info.ssh_security_group}",
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_availability_zones" "available" {}

resource "aws_ebs_volume" "storage" {
  count             = "${length(data.aws_availability_zones.available.names)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  size              = 1024
  type              = "gp2"

  tags {
    Name             = "${var.service_name}-${var.arena}-${var.environment}-storage-${count.index}"
    Project          = "${var.service_name}"
    Arena            = "${var.arena}"
    Region           = "${var.region}"
    Environment      = "${var.environment}"
    Purpose          = "database"
    AvailabilityZone = "${data.aws_availability_zones.available.names[count.index]}"
  }
}
