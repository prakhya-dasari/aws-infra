
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

resource "aws_security_group" "app_security_group" {
  name_prefix = "app_security_group"

  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Add ingress rule for the port your application runs on
  ingress {
    from_port   = 3000
    to_port     = 3000
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

# Launch the EC2 instance
resource "aws_instance" "example_instance" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.app_security_group.id]
  associate_public_ip_address = true
  root_block_device {
    volume_type           = "gp2"
    volume_size           = 50
    delete_on_termination = true
  }
  iam_instance_profile = aws_iam_instance_profile.profile.name
  user_data = <<EOF
		#! /bin/bash
  echo DB_HOST=${aws_db_instance.db_instance.address} >> /etc/environment
  echo DB_USER=${aws_db_instance.db_instance.username} >> /etc/environment
  echo DB_PASSWORD=${aws_db_instance.db_instance.password} >> /etc/environment
  echo DB_NAME=${aws_db_instance.db_instance.db_name} >> /etc/environment
  echo NODE_PORT="3000" >> /etc/environment
  echo DB_PORT=${var.db_port} >> /etc/environment
  echo S3_BUCKET_NAME=${aws_s3_bucket.private_bucket.bucket} >> /etc/environment
  sudo systemctl daemon-reload
  sudo systemctl restart nodeapp
	EOF


  # Disable termination protection
  disable_api_termination = false
}

# database security group
  resource "aws_security_group" "database_security_group" {
   name        = "database-security-group"
   description = "enable mysql/aurora access on port 3306"
   vpc_id      = aws_vpc.vpc.id

   ingress {
    description     = "mysql/aurora access"
    from_port       = 3306
    to_port         = 3306
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

# create the rds instance
resource "aws_db_instance" "db_instance" {
  engine                 = "mysql"
  engine_version         = "8.0.31"
  multi_az               = "false"
  identifier             = "csye6225"
  username               = "csye6225"
  password               = "Prakhya123"//var.db_password
  instance_class         = "db.t3.micro"
  allocated_storage      = 10
  db_subnet_group_name   = aws_db_subnet_group.private_subnet.name
  vpc_security_group_ids = [aws_security_group.database_security_group.id]
  db_name                = "csye6225"
  skip_final_snapshot    = "true"
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

resource "random_id" "random_bucket_suffix" {
  byte_length = 4
}

variable "environment" {}

resource "aws_iam_policy" "webapp_s3_policy" {
  name        = "WebAppS3"
  description = "Allows EC2 instances to perform S3 actions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
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
