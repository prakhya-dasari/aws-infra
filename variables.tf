variable "region" {
  type        = string
  description = "The region in which to create the infrastructure."

}

variable "cidr_block" {
  type        = string
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet" {
  type        = number
  description = "The CIDR prefix for the public subnets."
  default     = 3
}

variable "private_subnet" {
  type        = number
  description = "The CIDR prefix for the private subnets."
  default     = 3
}

variable "public_availability_zones" {
  type    = number
  default = 3
}

variable "private_availability_zones" {
  type    = number
  default = 3
}

variable "vpc_id" {
  type = number
  //default = 1
}

variable "profile" {
  type = string
  //default = "dev"
}

variable "ami_id" {
  type = string
  //default = ""
  description = "The AMI used for instance"
}
variable "db_port" {
  type        = number
  description = "The port to use for the database"
  default     = 3306
}

variable "db_username" {
  type        = string
  description = "Database Username "
}

variable "db_password" {
  type        = string
  description = "Database Password "
}
variable "DB_NAME" {
  type        = string
  description = "Database Name "
}
variable "server_port" {
  type        = number
  description = "Port for Webapp "
}
variable "environment" {
  type        = string
  description = "bucket env"
}
variable "hosted_zone_id" {
  type        = string
  description = "zone id"

}
variable "domain_name" {
  type        = string
  description = "domain name"
}