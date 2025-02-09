variable "vpc_id" {
  type        = string
  description = "Selected VPC, VPC ID"
  default     = "vpc-07afe5e5632b9cd52" # frankfort: "vpc-0c3ef762c330374a9"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private Subnet CIDR values"
  default     = ["10.10.0.128/25", "10.10.1.0/25"] # 3rd["10.10.1.128/25"]
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones"
  default     = ["eu-west-2a", "eu-west-2b"]
}
