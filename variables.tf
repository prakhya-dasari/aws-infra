variable "region" {
  type = string
}

variable "cidr_block" {
  type = string
}

variable "public_subnet" {
  type = list(string)
}

variable "private_subnet" {
  type = list(string)
}

variable "public_availability_zones" {
  type = list(string)
}

variable "private_availability_zones" {
  type = list(string)
}