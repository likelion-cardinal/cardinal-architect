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

output "security_group_ids" {
  value = {
    alb           = module.security.alb_sg_id
    nat           = module.security.nat_sg_id
    control_plane = module.security.control_plane_sg_id
    system        = module.security.system_sg_id
    app           = module.security.app_sg_id
  }
}

output "nat_asg_name" {
  value = module.nat_instance.asg_name
}

output "nat_ami_id" {
  value = module.nat_instance.ami_id
}

output "ssm_endpoint_ids" {
  value = module.endpoints.endpoint_ids
}
