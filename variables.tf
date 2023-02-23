variable "region" {
  type        = string
  description = "The region in which to create the infrastructure."
  default     = "us-east-1"
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
  type    = string
  default = "demo"
}

variable "ami_id" {
  type = string
  //default = ""
  description = "The AMI used for instance"
}