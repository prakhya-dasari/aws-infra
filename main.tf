
resource "aws_vpc" "vpc" {
  cidr_block = var.cidr_block
  tags = {
    Name = "My_VPC ${var.vpc_id}"
  }
}

data "aws_availability_zones" "all" {
  state = "available"
}

resource "aws_subnet" "public_subnet" {
  count                   = var.public_subnet
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.all.names, count.index % length(data.aws_availability_zones.all.names))
  map_public_ip_on_launch = false

  tags = {
    Name = "Public subnet ${count.index + 1} - VPC ${var.vpc_id}"
  }
}

resource "aws_subnet" "private_subnet" {
  count                   = var.private_subnet
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.cidr_block, 4, count.index + 1)
  availability_zone       = element(data.aws_availability_zones.all.names, count.index % length(data.aws_availability_zones.all.names))
  map_public_ip_on_launch = false

  tags = {
    Name = "Private subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "Internet gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "Public route table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "Private route table"
  }
}

resource "aws_route_table_association" "aws_public_route_table_association" {
  count          = var.public_subnet
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "aws_private_route_table_association" {
  count          = var.private_subnet
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}



#app security group
resource "aws_security_group" "app_security_group" {
  name_prefix = "app_security_group"

  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer_security_group.id]
  }

  ingress {
    from_port       = var.server_port
    to_port         = var.server_port
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer_security_group.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}




# database security group
resource "aws_security_group" "database_security_group" {
  name        = "database-security-group"
  description = "enable mysql/aurora access on port 3306"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "mysql/aurora access"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app_security_group.id]
  }

  tags = {
    Name = "database security group"
  }
}

resource "aws_db_subnet_group" "private_subnet" {
  subnet_ids = aws_subnet.private_subnet[*].id
  name       = "database"
}
resource "aws_kms_key" "b" {
  description             = "RDS key 1"
  deletion_window_in_days = 10
}
# create the rds instance
resource "aws_db_instance" "db_instance" {
  engine                 = "mysql"
  engine_version         = "8.0.31"
  multi_az               = "false"
  identifier             = "csye6225"
  username               = var.db_username
  password               = var.db_password
  instance_class         = "db.t3.micro"
  allocated_storage      = 10
  db_subnet_group_name   = aws_db_subnet_group.private_subnet.name
  vpc_security_group_ids = [aws_security_group.database_security_group.id]
  parameter_group_name   = aws_db_parameter_group.db.name
  db_name                = var.DB_NAME
  skip_final_snapshot    = "true"
  storage_encrypted      = "true"
  kms_key_id             = aws_kms_key.b.arn
}

resource "aws_s3_bucket_lifecycle_configuration" "s3" {
  bucket = aws_s3_bucket.private_bucket.id

  rule {
    id     = "transition-to-standard-ia"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_s3_bucket" "private_bucket" {
  bucket        = "private-bucket-${var.environment}-${random_id.random_bucket_suffix.hex}"
  acl           = "private"
  force_destroy = true

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.private_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "random_id" "random_bucket_suffix" {
  byte_length = 4
}

resource "aws_iam_policy" "webapp_s3_policy" {
  name        = "WebAppS3"
  description = "Allows EC2 instances to perform S3 actions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.private_bucket.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.private_bucket.bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_db_parameter_group" "db" {
  name_prefix = "db-"
  family      = "mysql8.0"
  description = "Parameter group for MySQL 8.0"
}
resource "aws_iam_role" "ec2_csye6225_role" {
  name = "EC2-CSYE6225"

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

resource "aws_iam_role_policy_attachment" "webapp_s3_policy_attachment" {
  policy_arn = aws_iam_policy.webapp_s3_policy.arn
  role       = aws_iam_role.ec2_csye6225_role.name
}

resource "aws_iam_instance_profile" "profile" {
  name = "profile"
  role = aws_iam_role.ec2_csye6225_role.name
}

resource "aws_route53_record" "example_record" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.webapp_lb.dns_name
    zone_id                = aws_lb.webapp_lb.zone_id
    evaluate_target_health = "true"
  }
}

#cloud watch
data "aws_iam_policy" "CloudWatchAgentServerPolicy" {
  arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "EC2-CW" {
  role       = aws_iam_role.ec2_csye6225_role.name
  policy_arn = data.aws_iam_policy.CloudWatchAgentServerPolicy.arn
}

resource "aws_cloudwatch_log_group" "csye" {
  name = "csye6225"
}

resource "aws_cloudwatch_log_stream" "webapp" {
  name           = "webapp"
  log_group_name = aws_cloudwatch_log_group.csye.name
}

# Load Balancer security group
resource "aws_security_group" "load_balancer_security_group" {
  name        = "load_balancer_security_group"
  description = "Security group for the load balancer"
  vpc_id      = aws_vpc.vpc.id
  # ingress {
  #   from_port   = 80
  #   to_port     = 80
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "load_balancer_security_group_id" {
  value = aws_security_group.load_balancer_security_group.id
}

resource "aws_lb_target_group" "target_group" {
  name     = "webapp-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

  health_check {
    enabled             = "true"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    path                = "/healthz"
    matcher             = "200"
    port                = var.server_port
  }
}

resource "aws_lb" "webapp_lb" {
  name               = "webapp-lb"
  internal           = false
  load_balancer_type = "application"

  subnets         = aws_subnet.public_subnet.*.id
  security_groups = [aws_security_group.load_balancer_security_group.id]

  tags = {
    Name = "webapp-lb"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.webapp_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = "arn:aws:acm:us-east-1:777316955194:certificate/0fc133b4-5bac-4689-982c-44fe76b22217"

  default_action {
    target_group_arn = aws_lb_target_group.target_group.arn
    type             = "forward"
  }
}

locals {
  user_data_ec2 = <<EOF
		#! /bin/bash
  echo DB_HOST=${aws_db_instance.db_instance.address} >> /etc/environment
  echo DB_USER=${aws_db_instance.db_instance.username} >> /etc/environment
  echo DB_PASSWORD=${aws_db_instance.db_instance.password} >> /etc/environment
  echo DB_NAME=${aws_db_instance.db_instance.db_name} >> /etc/environment
  echo NODE_PORT=${var.server_port} >> /etc/environment
  echo DB_PORT=${var.db_port} >> /etc/environment
  echo S3_BUCKET_NAME=${aws_s3_bucket.private_bucket.bucket} >> /etc/environment
  sudo systemctl daemon-reload
  sudo systemctl restart nodeapp
	EOF
}
resource "aws_kms_key" "a" {
  description             = "EBS key 1"
  deletion_window_in_days = 10
}
resource "aws_kms_key_policy" "example" {
  key_id = aws_kms_key.a.id
  policy = jsonencode({
    Id = "key-consolepolicy-1"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          "AWS" : "arn:aws:iam::777316955194:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key",
        Effect = "Allow",
        Principal = {
          "AWS" : "arn:aws:iam::777316955194:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow attachment of persistent resources",
        Effect = "Allow",
        Principal = {
          "AWS" : "arn:aws:iam::777316955194:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        },
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        Resource = "*",
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
    Version = "2012-10-17"
  })
}

# Create a launch template
resource "aws_launch_template" "webapp_launch_template" {
  name          = "webapp-launch-template"
  image_id      = var.ami_id
  instance_type = "t2.micro"
  key_name      = "ssh"
  # here
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app_security_group.id]
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 50
      volume_type           = "gp2"
      delete_on_termination = true
      //here changee
      encrypted  = "true"
      kms_key_id = aws_kms_key.a.arn
    }
  }
  # network_interfaces {
  #   associate_public_ip_address = true
  #   security_groups             = [aws_security_group.app_security_group.id]
  # }
  # block_device_mappings {
  #   device_name = "/dev/xvda"
  #   ebs {
  #     volume_size           = 50
  #     volume_type           = "gp2"
  #     delete_on_termination = true
  #   }
  # }
  user_data = base64encode(local.user_data_ec2)

  iam_instance_profile {
    name = aws_iam_instance_profile.profile.name
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "web-app-instance"
    }
  }
}

resource "aws_autoscaling_group" "webapp-autoscaling-group" {
  name                = "webapp-autoscaling-group"
  min_size            = 1
  max_size            = 3
  desired_capacity    = 1
  default_cooldown    = 60
  vpc_zone_identifier = aws_subnet.public_subnet.*.id
  target_group_arns   = [aws_lb_target_group.target_group.arn]
  launch_template {
    id      = aws_launch_template.webapp_launch_template.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "web-server"
    propagate_at_launch = true
  }
  tag {
    key                 = "AutoScalingGroup"
    value               = "true"
    propagate_at_launch = true
  }
}

# AutoScaling Policies
resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale_up_policy"
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.webapp-autoscaling-group.name
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "scale_down_policy"
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.webapp-autoscaling-group.name
}


# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_scale_up" {
  alarm_name          = "cpu-utilization-scale-up"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "This metric monitors EC2 CPU utilization and scales up when the threshold is exceeded"
  alarm_actions       = [aws_autoscaling_policy.scale_up_policy.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webapp-autoscaling-group.name
  }
}


resource "aws_cloudwatch_metric_alarm" "cpu_utilization_scale_down" {
  alarm_name          = "cpu-utilization-scale-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "3"
  alarm_description   = "This metric monitors EC2 CPU utilization and scales down when the threshold is below"
  alarm_actions       = [aws_autoscaling_policy.scale_down_policy.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webapp-autoscaling-group.name
  }
}

# Application Load Balancer

# Target Group Attachment
resource "aws_autoscaling_attachment" "webapp-autoscaling-group_attachment" {
  autoscaling_group_name = aws_autoscaling_group.webapp-autoscaling-group.name
  alb_target_group_arn   = aws_lb_target_group.target_group.arn
}

output "load_balancer_dns_name" {
  value = aws_lb.webapp_lb.dns_name
}