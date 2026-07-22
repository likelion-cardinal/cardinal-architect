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

module "security" {
  source = "./modules/security"

  project           = var.project
  env               = var.env
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr
  public_subnet_ids = module.vpc.public_subnet_ids

  # ALB Access Log 분석으로 악성 IP를 찾으면 여기에 추가 → NACL deny
  blocked_cidrs = var.blocked_cidrs
}

module "endpoints" {
  source = "./modules/endpoints"

  project  = var.project
  env      = var.env
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = module.vpc.vpc_cidr

  # 비용상 compute_az(첫 AZ=2a) private 서브넷 한 곳에만 배치.
  subnet_ids = [module.vpc.private_subnet_ids[0]]
}

module "nat_instance" {
  source = "./modules/nat-instance"

  project           = var.project
  env               = var.env
  subnet_id         = module.vpc.public_subnet_ids[0] # compute_az(첫 AZ=2a)의 public 서브넷
  security_group_id = module.security.nat_sg_id

  # Private 라우트(0.0.0.0/0 → NAT)는 NAT의 user_data가 부팅 시 직접 갱신한다.
  # ASG가 인스턴스를 교체하면 새 인스턴스가 자기 자신으로 라우트를 재지정(자동 복구).
  # 따라서 root에 aws_route를 두지 않고, 라우트 테이블 ID만 모듈에 넘긴다.
  private_route_table_ids = module.vpc.private_route_table_ids
}

module "control_plane" {
  source = "./modules/control-plane"

  project               = var.project
  env                   = var.env
  subnet_id             = module.vpc.private_subnet_ids[0] # compute_az(첫 AZ=2a) private
  security_group_id     = module.security.control_plane_sg_id
  instance_profile_name = module.iam.instance_profile_name

  # etcd 백업은 공유 S3 버킷 생성 후 버킷 이름을 주입하면 cron 활성화.
  # etcd_backup_bucket = aws_s3_bucket.shared.bucket
}
