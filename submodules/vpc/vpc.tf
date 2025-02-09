data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# VPC - Use existing
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# To ensure subnets are created withour errors. Defaults SG have no egress/ingress permissions
resource "aws_default_security_group" "default" {
  vpc_id = data.aws_vpc.selected.id
}


# --------------------------------------------------------------------------------------------
# Private Subnets
# --------------------------------------------------------------------------------------------
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = data.aws_vpc.selected.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)
  tags = {
    Name = "SageMaker Private Subnet ${count.index + 1}"
  }
}

# --------------------------------------------------------------------------------------------
# Private route Table and its associated subnets
# --------------------------------------------------------------------------------------------
resource "aws_route_table" "private_subnets_rt" {
  vpc_id = data.aws_vpc.selected.id

  tags = {
    Name = "SageMaker Private Subnet Route Table"
  }
}

resource "aws_route_table_association" "private_rt_associations" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
  route_table_id = aws_route_table.private_subnets_rt.id
}


# --------------------------------------------------------------------------------------------
# Private subnet Security Group for SageMaker
# --------------------------------------------------------------------------------------------
resource "aws_security_group" "sagemaker_sg" {
  name        = "sagemaker_sg"
  description = "Allow certain NFS and TCP inbound traffic"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description = "NFS traffic over TCP on port 2049 between the domain and EFS volume"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "TCP traffic between JupyterServer app and the KernelGateway apps"
    from_port   = 8192
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "SageMaker sg"
  }
}


# --------------------------------------------------------------------------------------------
# Security Group VPC Interface Endpoints
# --------------------------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "vpc_endpoint_sg"
  description = "Allow incoming connections on port 443 from VPC"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description = "Allow incoming connections on port 443 from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "VPC endpoint sg"
  }
}


# --------------------------------------------------------------------------------------------
# Interface Endpoints: SageMaker 
# --------------------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "interface_endpoints" {
  for_each = toset([
    "com.amazonaws.${data.aws_region.current.name}.sagemaker.api",
    "com.amazonaws.${data.aws_region.current.name}.sagemaker.runtime",
    "com.amazonaws.${data.aws_region.current.name}.sagemaker.featurestore-runtime",
    "com.amazonaws.${data.aws_region.current.name}.servicecatalog"
  ])

  vpc_id              = data.aws_vpc.selected.id
  service_name        = each.key
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_subnets[*].id
  private_dns_enabled = true

  security_group_ids = [
    aws_security_group.vpc_endpoint_sg.id
  ]
}


# --------------------------------------------------------------------------------------------
# Gateway Endpoint: S3
# --------------------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.selected.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
}

resource "aws_vpc_endpoint_route_table_association" "s3_vpce_route_table_association" {
  route_table_id  = aws_route_table.private_subnets_rt.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

