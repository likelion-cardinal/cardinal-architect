output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "private_route_table_ids" {
  value = module.vpc.private_route_table_ids
}

output "node_instance_profile_name" {
  value = module.iam.instance_profile_name
}

output "node_role_arn" {
  value = module.iam.role_arn
}
