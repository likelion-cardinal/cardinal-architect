module "vpc" {
  source = "./modules/vpc"

  project              = var.project
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# TODO(root wiring, nat-instance 모듈 추가 후):
#   Private 라우트 테이블의 기본 경로(0.0.0.0/0 → NAT Instance)를 여기서 추가한다.
#   resource "aws_route" "private_nat" {
#     count                  = length(module.vpc.private_route_table_ids)
#     route_table_id         = module.vpc.private_route_table_ids[count.index]
#     destination_cidr_block = "0.0.0.0/0"
#     network_interface_id   = module.nat_instance.eni_id
#   }
