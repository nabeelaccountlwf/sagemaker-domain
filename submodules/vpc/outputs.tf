output "vpc_id" {
  value = data.aws_vpc.selected.id
}

output "subnet_ids" {
  value = aws_subnet.private_subnets[*].id
}

output "security_group_id" {
  value = aws_security_group.sagemaker_sg.id
}