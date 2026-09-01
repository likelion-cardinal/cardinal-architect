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

  # 노드 Role이 etcd/ prefix에만 접근하도록 스코프된다(s3.tf 참고).
  etcd_backup_bucket_arn = aws_s3_bucket.shared.arn
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

  # 사설 IP를 고정한다. CP를 교체해도 controlPlaneEndpoint와 인증서 SAN이 유지돼야
  # 워커들이 그대로 붙고, etcd 스냅샷 복구가 의미를 가진다.
  private_ip = var.control_plane_private_ip

  # 부팅과 동시에 kubeadm init → Calico apply → join 토큰 발행까지 무인 수행.
  ssm_parameter_path  = local.kubeadm_ssm_path
  join_parameter_name = local.join_parameter_name

  # 파드 대역은 VPC(10.20.0.0/16)와 겹치지 않아야 하고, Calico 기본 풀과도 맞아야 한다.
  # pod_subnet         = "192.168.0.0/16"
  # kubernetes_version = "v1.34.9"  # AMI 프리풀 태그와 일치

  # 버킷 이름이 들어가면 user_data가 매일 03:00 etcd 스냅샷 cron을 등록한다.
  etcd_backup_bucket = aws_s3_bucket.shared.bucket
}

module "system_node" {
  source = "./modules/system-node"

  project               = var.project
  env                   = var.env
  ami_id                = var.node_ami_id
  subnet_id             = module.vpc.private_subnet_ids[0] # compute_az(첫 AZ=2a) private
  security_group_id     = module.security.system_sg_id
  instance_profile_name = module.iam.instance_profile_name

  # CP가 발행한 join 커맨드를 읽어 부팅 시 클러스터에 붙는다.
  ssm_parameter_path  = local.kubeadm_ssm_path
  join_parameter_name = local.join_parameter_name

  # 영속 데이터용 정적 EBS. 노드 AZ에 생성·부착 후 data_mount_point에 마운트하고
  # MySQL·Prometheus·Grafana가 하위 디렉토리를 hostPath로 나눠 쓴다.
  #   /mnt/data/mysql /mnt/data/prometheus /mnt/data/grafana
  # 루트 EBS는 인스턴스 교체(= node_ami_id 변경)와 함께 삭제되므로, 살아남아야 할
  # 데이터를 루트에 두면 AMI를 다시 굽는 순간 메트릭과 대시보드가 전소한다.
  # 백업(mysqldump)은 클러스터 CronJob으로 별도.
  data_volume_size = 20
  # data_mount_point = "/mnt/data"  # 기본값
}

module "dns" {
  source = "./modules/dns"

  # 도메인을 아직 안 샀으면 통째로 건너뛴다. tfvars에 domain_name을 채우는 순간 생성된다.
  count = var.domain_name != "" ? 1 : 0

  project     = var.project
  env         = var.env
  domain_name = var.domain_name

  # 가비아 네임서버를 Route53 NS로 바꾸기 전에는 검증이 끝날 수 없다.
  # NS 전파를 확인한 뒤 true로 올려 apply하면 발급 완료를 보장받는다.
  wait_for_validation = var.wait_for_certificate_validation
}

module "alb" {
  source = "./modules/alb"

  project           = var.project
  env               = var.env
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.public_subnet_ids # 2 AZ 필수
  security_group_id = module.security.alb_sg_id
  access_log_bucket = aws_s3_bucket.shared.bucket

  # 인증서가 "발급 완료"된 뒤에만 443을 연다. PENDING_VALIDATION 상태로 리스너를
  # 만들면 실패하기 때문이다. 그전까지는 80이 Target Group으로 그대로 forward한다.
  enable_https    = var.domain_name != "" && var.wait_for_certificate_validation
  certificate_arn = one(module.dns[*].certificate_arn)

  # Ingress Controller가 열 NodePort. 배포 후 실제 포트에 맞춰야 한다.
  # target_port = 30080
}

# 도메인 → ALB. dns 모듈과 alb 모듈이 서로를 참조하지 않도록 wiring은 root에 둔다.
resource "aws_route53_record" "apex" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = one(module.dns[*].zone_id)
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.alb.dns_name
    zone_id                = module.alb.zone_id
    evaluate_target_health = false
  }
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

  # Target Group을 붙이면 ASG 헬스체크가 EC2에서 ELB로 바뀐다.
  # Ingress Controller가 뜨기 전에 붙이면 헬스체크가 계속 실패해 ASG가 노드를
  # 5분마다 교체한다. 그래서 클러스터에 Ingress를 올린 뒤 이 값을 true로 바꾼다.
  target_group_arns = var.register_app_nodes_to_alb ? [module.alb.target_group_arn] : []
}

# 개발팀이 database 네임스페이스(mysql/rabbitmq/redis)에 붙기 위한 접속 경로.
# CP에 SSM으로 들어가되 root가 아닌 devops 계정으로 떨어지고, 그 계정의
# kubeconfig가 database 네임스페이스로만 스코프된다.
#   개발자 IAM 유저 생성 → 이 모듈이 만든 그룹에 추가 (콘솔)
#   CP 쪽 준비(devops 계정 + kubeconfig)는 manifest/all/dev-access/setup.txt
module "dev_access" {
  source = "./modules/dev-access"

  project = var.project
  env     = var.env
}
