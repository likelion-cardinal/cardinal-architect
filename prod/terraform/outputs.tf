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

output "control_plane_instance_id" {
  value = module.control_plane.instance_id
}

output "control_plane_private_ip" {
  value = module.control_plane.private_ip
}

output "system_node_instance_id" {
  value = module.system_node.instance_id
}

output "system_node_private_ip" {
  value = module.system_node.private_ip
}

# dns 모듈은 domain_name이 비면 생성되지 않으므로 셋 다 null이 된다.
# 도메인 구매 후 apply하면 name_servers를 등록기관(가비아 등) 콘솔에 그대로 입력한다.
output "route53_name_servers" {
  value = one(module.dns[*].name_servers)
}

output "acm_certificate_arn" {
  value = one(module.dns[*].certificate_arn)
}

output "acm_certificate_status" {
  value = one(module.dns[*].certificate_status)
}

output "app_asg_name" {
  value = module.app_asg.asg_name
}

output "app_launch_template_id" {
  value = module.app_asg.launch_template_id
}

# CP가 이 이름으로 join 커맨드를 SecureString 저장해야 신규 노드가 붙는다.
output "kubeadm_join_parameter_name" {
  value = module.app_asg.join_parameter_name
}
