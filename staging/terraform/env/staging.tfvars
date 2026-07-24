env = "staging"

# 기본값(variables.tf)을 그대로 쓰면 아래는 생략 가능.
# instance_type    = "t3.small"
# root_volume_size = 15

# SSH는 내 공인 IP만 허용(2026-07-24 기준). IP가 바뀌면 갱신.
# ssh_ingress_cidr = "61.73.4.159/32"

# FE(3000)는 기본 0.0.0.0/0. 좁히려면 아래 주석 해제.
# fe_ingress_cidr = "0.0.0.0/0"
