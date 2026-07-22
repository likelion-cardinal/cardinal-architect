locals {
  # join 토큰이 오가는 SSM 경로. iam(권한 부여)·control-plane(발행)·app-asg(수신)
  # 세 모듈이 같은 값을 봐야 하므로 root에서 한 번만 정한다.
  kubeadm_ssm_path    = "kubeadm"
  join_parameter_name = "join-command"
}

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

  project            = var.project
  env                = var.env
  ssm_parameter_path = local.kubeadm_ssm_path

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
  ami_id                = var.node_ami_id
  subnet_id             = module.vpc.private_subnet_ids[0] # compute_az(첫 AZ=2a) private
  security_group_id     = module.security.control_plane_sg_id
  instance_profile_name = module.iam.instance_profile_name

  # 부팅과 동시에 kubeadm init → Calico apply → join 토큰 발행까지 무인 수행.
  ssm_parameter_path  = local.kubeadm_ssm_path
  join_parameter_name = local.join_parameter_name

  # 파드 대역은 VPC(10.20.0.0/16)와 겹치지 않아야 하고, Calico 기본 풀과도 맞아야 한다.
  # pod_subnet         = "192.168.0.0/16"
  # kubernetes_version = "v1.34.9"  # AMI 프리풀 태그와 일치

  # etcd 백업은 공유 S3 버킷 생성 후 버킷 이름을 주입하면 cron 활성화.
  # etcd_backup_bucket = aws_s3_bucket.shared.bucket
}

module "system_node" {
  source = "./modules/system-node"

  project               = var.project
  env                   = var.env
  ami_id                = var.node_ami_id
  subnet_id             = module.vpc.private_subnet_ids[0] # compute_az(첫 AZ=2a) private
  security_group_id     = module.security.system_sg_id
  instance_profile_name = module.iam.instance_profile_name

  # MySQL 데이터용 정적 EBS. 크기 지정 시 노드 AZ에 생성·부착 후 mysql_mount_point에 마운트.
  # 파드는 이 디렉토리를 hostPath PV로 사용. 백업(mysqldump)은 클러스터 CronJob으로 별도.
  # mysql_data_volume_size = 20
  # mysql_mount_point      = "/mnt/mysql-data"
}

module "app_asg" {
  source = "./modules/app-asg"

  project               = var.project
  env                   = var.env
  ami_id                = var.node_ami_id
  security_group_id     = module.security.app_sg_id
  instance_profile_name = module.iam.instance_profile_name

  # CP가 발행한 join 커맨드를 읽을 파라미터 (경로가 어긋나면 노드가 join하지 못한다).
  ssm_parameter_path  = local.kubeadm_ssm_path
  join_parameter_name = local.join_parameter_name

  # 현재는 compute_az(첫 AZ=2a) 한 곳. NAT·CP·System과 같은 AZ에 두어 AZ 간 전송요금을 피한다.
  # 진짜 AZ 장애 내성이 필요해지면 여기에 두 번째 private 서브넷을 추가한다.
  subnet_ids = [module.vpc.private_subnet_ids[0]]

  # 스케일 폭. desired는 Cluster Autoscaler가 조정하므로 모듈이 무시한다.
  min_size = 1
  max_size = 3

  # ALB Target Group 등록은 alb 모듈 생성 후 주입 (그전엔 EC2 헬스체크).
  # target_group_arns = [module.alb.target_group_arn]
}
