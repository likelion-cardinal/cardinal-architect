module "vpc" {
  source = "./modules/vpc"

  project              = var.project
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "iam" {
  source = "./modules/iam"

  project = var.project
  env     = var.env

  # etcd 백업 버킷은 공유 S3 버킷(모듈 0) 생성 후 여기서 ARN을 주입한다.
  # etcd_backup_bucket_arn = aws_s3_bucket.shared.arn
}

# TODO(root wiring, nat-instance 모듈 추가 후):
#   Private 라우트 테이블의 기본 경로(0.0.0.0/0 → NAT Instance)를 여기서 추가한다.
#   resource "aws_route" "private_nat" {
#     count                  = length(module.vpc.private_route_table_ids)
#     route_table_id         = module.vpc.private_route_table_ids[count.index]
#     destination_cidr_block = "0.0.0.0/0"
#     network_interface_id   = module.nat_instance.eni_id
#   }
