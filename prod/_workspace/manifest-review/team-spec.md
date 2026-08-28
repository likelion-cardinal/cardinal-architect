# manifest-review 팀 스펙

## 목표

`prod/manifest/` 아래 system-node·app-node·test 매니페스트가 현재 `prod/terraform/`이 만들어낼
인프라 위에서 오류 없이 적용·기동될지를 **클러스터 없이 정적 대조만으로** 판정하고, 발견 사항을
치명/경고/정보로 분류한 단일 리포트 `_workspace/manifest-review/report.md`로 내놓는다.
성공 기준: 12개 검사 축이 모두 커버되고, 모든 발견에 `파일:줄` 근거가 붙어 있으며, **어떤 소스 파일도
수정되지 않았을 것.**

> 설계 판단: terraform apply 전이라 kubectl/kustomize build 실행이 불가능하다. 따라서 전 단계가
> "파일 대조"이며, 어떤 에이전트에도 클러스터 접근·`Bash` 실행 권한을 주지 않는다.

## 스킬

- **커맨드명**: `manifest-review`
- **description 초안**:
  "`prod/manifest/` 아래 쿠버네티스 매니페스트가 `prod/terraform/`이 프로비저닝할 인프라(노드 라벨,
  ASG 태그, IAM 조건, SG 포트, 인스턴스 용량)와 어긋나지 않는지 **클러스터 없이 정적으로** 검토할 때
  사용한다. '매니페스트 리뷰해줘', '이대로 apply하면 뜨냐', 'system node / app node 매니페스트가
  테라폼이랑 맞는지 봐줘' 같은 요청 시 사용. 읽기 전용이며 파일을 고치지 않고 발견 사항만 보고한다.
  매니페스트를 새로 작성하거나 고치는 일에는 쓰지 말 것(그건 직접 편집). 실제 클러스터에 붙어
  `kubectl get`으로 상태를 확인하는 일에도 쓰지 말 것."
- **model-invocation**: 허용(부작용 없는 읽기 전용 조사). `disable-model-invocation` 불필요.
- **오케스트레이션 개요**:
  1. **입력 확인.** 매니페스트 루트(기본 `${CLAUDE_PROJECT_DIR}/manifest`)와 테라폼 루트(기본
     `${CLAUDE_PROJECT_DIR}/terraform`)가 존재하는지 확인한다. 둘 중 하나라도 없으면 한 줄로
     알리고 종료.
  2. **인벤토리 작성.** 스킬이 직접 `Glob`으로 `manifest/**/*.{yaml,yml,txt}`와
     `terraform/**/*.{tf,tftpl,tfvars}` 파일 목록을 만든다. **파일로 저장하지 않고** 두 감사자
     프롬프트에 인라인으로 넣는다(검사 범위를 문자 그대로 고정해 누락·범위 이탈을 막는다).
     매니페스트 파일이 0개면 종료.
  3. **병렬 감사.** `manifest-static-auditor`와 `manifest-infra-crosschecker`를 **한 메시지에서
     동시에** 호출한다(참조 파일군이 겹치지 않아 의존성이 없다). 각각에 담당 검사 축 번호와
     공통 발견 스키마(아래 "발견 스키마")를 프롬프트에 명시한다.
  4. **산출물 확인.** `findings-static.md` / `findings-infra.md` 중 없는 것이 있으면 해당
     에이전트만 1회 재호출한다. 그래도 없으면 그 축을 "미감사"로 표기하고 5번으로 진행한다.
  5. **취합·판정.** `manifest-findings-arbiter`를 호출한다. 산출물 `report.md`와
     `판정: PASS | nonpass`를 받는다.
  6. **재감사 루프.** nonpass면 arbiter가 지정한 에이전트(`재감사 대상:` 줄)만 gap 목록을 붙여
     재호출하고 5번을 다시 돈다. **최대 2라운드.**
  7. **실패 종료.** 2라운드를 소진해도 nonpass면 그 시점의 `report.md`를 그대로 제출하되
     "커버리지 미달 — 수동 검토 필요" 경고와 arbiter가 남긴 미해결 gap 목록을 정직하게 보고한다.
     판정을 PASS로 뒤집지 않는다.
  8. **완료 보고.** 치명/경고/정보 건수, 치명 항목 제목 전부, `report.md` 절대경로를 제시한다.
     "소스 파일은 하나도 수정하지 않았다"를 명시한다.
- **사용자 개입 지점**: 없음. 읽기 전용 조사이므로 승인 없이 8번까지 자동 진행한다.
- **allowed-tools 제안**: `Read, Glob, Agent`
  (스킬 자신은 아무 파일도 쓰지 않는다. 리포트 작성은 arbiter 몫.)

## 발견 스키마 (세 에이전트가 문자 그대로 공유)

```markdown
### [치명|경고|정보] <한 줄 제목>
- 근거: <파일경로:줄번호> — "<인용>"
- 대조: <상대 파일경로:줄번호> — "<인용>"   (교차 검사가 아니면 생략)
- 영향: <apply 시 실제로 무슨 일이 일어나는가>
- 확신도: 확실 | 추정
- 권고: <무엇을 어떤 값으로 바꿔야 하는지. 직접 고치지 않는다>
- 검사축: <1~12 중 해당 번호>
```

**심각도 정의(세 에이전트 공통, arbiter가 최종 판정):**
- **치명** — apply가 실패하거나, 리소스는 생기되 파드가 영구 Pending/CrashLoop이거나, 컴포넌트가
  본래 기능을 전혀 못 한다.
- **경고** — 기동은 되지만 운영 중 장애가 예상된다(용량 부족, 디스크 고갈, 권한 부족으로 일부 기능
  실패, 수동 선행 단계 의존).
- **정보** — 개선 제안, 문서·절차 부정확, 원격 확인 불가로 판정 보류한 항목.

## 공통 제약 (세 에이전트 전부에 적용)

- **`Edit` / `NotebookEdit` / `Bash`를 어떤 에이전트에도 주지 않는다.** 소스 수정 경로를 원천 차단한다.
- **`Write`는 허용하되 경로를 못박는다.** 각 에이전트는 `_workspace/manifest-review/` 아래 **자기
  담당 파일 1개에만** 쓴다. 그 외 어떤 경로에도 쓰지 않는다는 문장을 각 에이전트 본문에 명시한다.
  > 판단 근거: 3단계 파이프라인이고 3번째 에이전트가 앞 두 결과를 **소비**한다. 텍스트 반환으로
  > 넘기면 스킬이 장문 리포트를 프롬프트로 재작성해야 해서 근거 인용이 유실된다. 파일 핸드오프가
  > 상류 출력 == 하류 입력을 문자 그대로 보장한다. `_workspace/`는 소스가 아니므로 "코드를 건들지
  > 않는다"는 제약을 위반하지 않는다.
- **고치지 말고 보고만.** 권고는 쓰되 patch/diff를 만들지 않는다.
- **근거 없는 발견 금지.** 모든 항목에 `파일:줄` 인용이 있어야 한다. 없으면 arbiter가 반려한다.

## 에이전트

> 재사용 검토 결과: 기존 6개 에이전트(`make-agent`, `make-agent-reviewer`, `skill-author`,
> `skill-reviewer`, `workflow-architect`, `workflow-integration-reviewer`)는 전부 **에이전트·스킬
> 정의 파일 자체**를 다루는 메타 워크플로용이다. 쿠버네티스 매니페스트나 테라폼을 판정하는 역할은
> 하나도 없어 재사용 가능한 것이 없다. 3개 모두 신규.

### manifest-static-auditor

- **역할**: `prod/manifest/**`만 보고 **매니페스트 내부 정합성**을 감사한다. 테라폼은 열지 않는다.
  YAML 문법·kustomize·RBAC·리소스 참조·선행 조건·절차 문서의 정확성을 판정한다.
- **담당 검사 축**: 9(RBAC 완결성), 10(Namespace 존재 전제·순서 의존), 11(YAML 멀티도큐먼트 문법,
  kustomize `patches.target` 실제 매칭 여부, JSON6902 `op: add` 경로 유효성, 이미지 태그 존재),
  12(setup.txt 절차 — `-k` vs `-f`, 상대경로, 단계 번호), 그리고 매니페스트 내부 참조 일관성:
  - Service `selector` ↔ Pod template `labels`
  - Deployment `serviceAccountName` ↔ ServiceAccount `metadata.name`/`namespace`
  - (Cluster)RoleBinding `subjects` ↔ SA, `roleRef` ↔ 실제 (Cluster)Role 이름
  - `volumeMounts.name` ↔ `volumes.name`, ConfigMap 참조 ↔ 실제 ConfigMap 존재
  - `containerPort`/`port`/`targetPort` 이름·번호 연쇄
  - prometheus ConfigMap의 scrape target ↔ 실제 Service/네임스페이스
  - **ArgoCD `application.yaml`의 `source.path` ↔ 실제 리포 구조** — `manifest/app-node/`가
    현재 비어 있는 점을 반드시 판정할 것(사용자의 핵심 관심사)
  - `cluster-autoscaler.yaml` `ssl-certs` hostPath `/etc/ssl/certs/ca-bundle.crt`가 AMI 배포판에
    존재하는 경로인지(Amazon Linux 계열 vs Ubuntu 계열 차이) — 확신도 `추정`으로 표기
- **입력**: (프롬프트) 매니페스트 파일 인벤토리 목록, 담당 검사 축 번호, 발견 스키마, 출력 경로.
  재감사 시에는 arbiter의 gap 목록이 추가로 붙는다.
- **출력**: `_workspace/manifest-review/findings-static.md` — 발견 스키마 항목의 나열.
  파일 맨 위에 `## 커버리지` 절을 두고 담당 축별로 `축 N: 검사함(발견 k건) | 검사함(이상 없음) |
  미검사(사유)`를 적는다. 최종 텍스트로는 축별 건수 요약만 반환한다.
- **상류/하류**: `manifest-review` 스킬(3단계)이 호출 → `manifest-findings-arbiter`가 파일을 읽음.
- **tools 제안**: `Read, Glob, Grep, WebFetch, Write`
  - `WebFetch`는 **두 용도로만**: (a) `kustomization.yaml`이 참조하는 argo-cd v3.4.5 원격
    `install.yaml` URL이 살아 있는지, (b) 이미지 태그(`cluster-autoscaler:v1.34.5` 등) 존재 여부.
    네트워크 실패 시 `[정보] 원격 확인 불가`로 남기고 진행한다(실패로 종료하지 않는다).
  - `Bash` 미부여 — kubectl/kustomize를 실행할 수 없고(클러스터 부재·원격 fetch 필요), 파일 조사는
    `Glob`/`Grep`으로 충분하며, 부작용 경로를 없애기 위함.
  - `Write`는 `findings-static.md` 전용.
- **model 제안**: **sonnet** — 규칙 대조와 이름 일치 검사가 대부분이라 추론 깊이보다 꼼꼼함이
  중요하고, 대상 파일량이 중간 규모다.

### manifest-infra-crosschecker

- **역할**: `prod/manifest/**`와 `prod/terraform/**`를 **양방향 대조**해, 매니페스트가 전제하는
  인프라 사실과 테라폼이 실제로 만들 인프라가 어긋나는 지점을 찾는다. 매니페스트 내부 문법은
  보지 않는다(그건 static-auditor 몫).
- **담당 검사 축**:
  1. **노드 라벨** — 매니페스트 `nodeSelector: cardinal.io/role=system` / nodeAffinity
     `cardinal.io/role Exists` ↔ `modules/system-node/variables.tf:83`(`cardinal.io/role=system`),
     `modules/app-asg/variables.tf:113`(`cardinal.io/role=application`) ↔ 각 `user_data.sh.tftpl`의
     `KUBELET_EXTRA_ARGS --node-labels=${node_labels}` 전파 경로. **app 노드 라벨 값이
     `application`인 점**과 향후 app-node 매니페스트가 쓸 값의 불일치 가능성을 짚을 것.
  2. **CP 테인트** — `modules/control-plane/user_data.sh.tftpl`이 커스텀 라벨/테인트를 넣지 않아
     kubeadm 기본 `node-role.kubernetes.io/control-plane:NoSchedule`만 있는 상태 ↔ node-exporter
     DaemonSet에 해당 toleration이 있는지 → CP에 뜨는지 여부 판정.
  3. **Cluster Autoscaler 3중 정합** — 매니페스트
     `--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/cardinal-prod`
     ↔ `modules/app-asg/main.tf:21-23`의 `autoscaler_tags`(`k8s.io/cluster-autoscaler/${local.name}`)
     ↔ `modules/iam/main.tf:91`의 조건 키
     `autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${local.name}`.
     **`local.name`이 `${var.project}-${var.env}`로 조립되는 실제 값**을 `variables.tf`/`prod.tfvars`
     까지 따라가 `cardinal-prod`와 문자 그대로 같은지 확인할 것. 셋 중 하나만 어긋나도 스케일아웃이
     조용히 실패하므로 치명 후보.
     추가로 CA가 IRSA 없이 **노드 인스턴스 프로파일**로 AWS를 호출하는 구조인지(=system 노드
     인스턴스 롤에 autoscaling 권한이 붙어 있는지) 확인한다.
  4. **리전 하드코딩** — CA Deployment `AWS_REGION: ap-northeast-2` ↔ terraform `variables.tf`의
     region 기본값·`env/prod.tfvars`.
  5. **버전 정합** — CA 이미지 마이너(`v1.34.x`) ↔ AMI에 구운 k8s 버전(`prod.tfvars` 주석의 1.34.9),
     argo-cd v3.4.5의 k8s 지원 범위.
  6. **hostPath 경로** — prometheus `/mnt/prometheus-data`, grafana `/mnt/grafana-data` ↔
     `modules/system-node`의 EBS 볼륨·마운트 설정(`mysql_data_volume_size`/`mysql_mount_point`)과
     루트 볼륨 30GiB. 디렉토리를 만들어 주는 주체가 없으면(user_data에 mkdir 없음) 기동 실패 또는
     루트 디스크 고갈로 판정.
  7. **리소스 총량** — 각 노드 그룹에 스케줄될 파드의 `requests.cpu`/`requests.memory` 합계 ↔
     instance_type 용량(m7i-flex.large = 2 vCPU / 8 GiB)에서 kubelet 예약분을 뺀 allocatable.
     system 노드에 argocd(전체 컴포넌트) + prometheus + grafana + CA가 전부 몰리는 점을 정량 계산할 것.
  8. **네트워크** — NodePort(`whoami` 30080 등) ↔ `modules/security/main.tf`의
     `nodeport_from`/`nodeport_to` 범위, ALB `target_port`/타깃 그룹, 노드 간 SG mesh,
     CNI(Calico VXLAN) 필요 포트(4789/UDP, 179/TCP), NACL.
- **입력**: (프롬프트) 매니페스트·테라폼 파일 인벤토리 목록, 담당 검사 축 번호, 발견 스키마,
  출력 경로. 재감사 시 arbiter의 gap 목록 추가.
- **출력**: `_workspace/manifest-review/findings-infra.md` — static-auditor와 **동일한 발견 스키마**.
  맨 위에 동일 형식의 `## 커버리지` 절. 최종 텍스트로는 축별 건수 요약만 반환.
- **상류/하류**: `manifest-review` 스킬(3단계)이 호출 → `manifest-findings-arbiter`가 파일을 읽음.
  static-auditor와 **병렬**이며 서로 의존하지 않는다.
- **tools 제안**: `Read, Glob, Grep, Write`
  - `WebFetch` 미부여 — 대조 대상이 전부 로컬 파일이다.
  - `Bash` 미부여 — `terraform plan`은 apply 전 자격증명·상태 문제로 신뢰할 수 없고 부작용 위험이
    있다. HCL은 `Read`/`Grep`으로 정적으로만 읽는다.
  - `Write`는 `findings-infra.md` 전용.
- **model 제안**: **opus** — HCL 변수 조립(`local.name = "${var.project}-${var.env}"`)을
  `prod.tfvars`까지 추적해 최종 문자열을 손으로 전개하고, 라벨→user_data→kubelet→스케줄러로 이어지는
  값 전파 사슬을 양방향으로 추론해야 한다. 이 워크플로에서 가장 무거운 추론 단계다.

### manifest-findings-arbiter

- **역할**: 두 감사 리포트를 읽어 **거짓 양성을 걸러내고, 중복·충돌을 조정하고, 심각도를 최종
  확정해** 단일 리포트를 쓴다. 동시에 두 감사자의 **커버리지 품질을 판정**하는 게이트 역할을 한다.
- **입력**:
  - `_workspace/manifest-review/findings-static.md`
  - `_workspace/manifest-review/findings-infra.md`
  - (프롬프트) 12개 검사 축 전체 목록, 현재 라운드 번호와 최대 라운드(2)
- **하는 일**:
  1. **근거 검증** — 각 발견의 `근거:`/`대조:` 인용을 `Read`/`Grep`으로 실제 파일에서 확인한다.
     인용이 실제와 다르면 그 발견을 **기각**하고 기각 사유를 남긴다.
  2. **충돌 조정** — 한쪽이 "문제"라 한 것을 다른 쪽 근거가 해소하는 경우(예: static이 지적한
     `nodeSelector` 전제를 infra가 라벨 일치로 확인) 병합해 심각도를 낮춘다. 반대 경우 올린다.
  3. **중복 병합** — 같은 원인의 발견을 하나로 합치고 근거를 모두 보존한다.
  4. **심각도 확정** — 위 "심각도 정의"를 유일한 기준으로 재판정한다. 감사자가 매긴 등급을
     그대로 승계하지 않는다.
  5. **커버리지 판정** — 12개 축이 모두 `검사함`인지, 모든 채택 발견에 `파일:줄` 근거가 있는지 확인.
- **판정 규칙**:
  - **PASS** = 12개 축 전부 `검사함`(발견 0건도 포함) **그리고** 채택된 모든 발견에 검증된
    `파일:줄` 근거가 있음.
  - **nonpass** = 미검사 축이 있거나, 근거 없는 발견이 남아 있음. 이때 `재감사 대상:`으로
    에이전트 이름 하나 이상과 각각의 gap 목록을 반드시 명시한다.
  - **주의**: 판정은 **감사 품질**에 대한 것이지 매니페스트 건강 상태에 대한 것이 아니다.
    치명 발견이 많아도 커버리지가 충분하면 PASS다.
- **출력**:
  - 파일 `_workspace/manifest-review/report.md`. 라운드마다 덮어쓴다. 구조:
    ```markdown
    # manifest-review 리포트
    ## 요약
    - 치명 N건 / 경고 N건 / 정보 N건 · 라운드 R/2 · 판정 PASS|nonpass
    - 한 문단 총평: 지금 apply하면 무엇이 먼저 깨지는가
    ## 치명
    <발견 스키마 항목들>
    ## 경고
    ## 정보
    ## 기각된 발견
    - <제목> — 기각 사유(인용 불일치 등)
    ## 커버리지
    | 축 | 담당 | 상태 | 발견 |
    ## 미해결 gap
    ```
  - 최종 텍스트(스킬이 분기에 사용):
    ```
    판정: PASS | nonpass
    집계: 치명 N / 경고 N / 정보 N
    재감사 대상: <에이전트명> — <gap 목록>   (nonpass일 때만)
    ```
- **상류/하류**: `manifest-review` 스킬(5단계)이 호출 → 결과가 사용자에게 보고됨.
  nonpass면 스킬이 지정된 감사자를 재호출한 뒤 이 에이전트를 다시 부른다.
- **tools 제안**: `Read, Glob, Grep, Write`
  - `Read`/`Grep`은 인용 검증(1번)에 반드시 필요하다. 리포트만 합치는 게 아니다.
  - `Write`는 `report.md` 전용.
- **model 제안**: **opus** — 두 리포트의 충돌 조정, 거짓 양성 판별, 심각도 재판정은 이 팀에서
  유일하게 "판단을 뒤집는" 단계다. 여기서 틀리면 사용자가 잘못된 우선순위로 인프라를 고친다.

## 파이프라인

```
manifest-review 스킬
  ├─ (인벤토리 Glob, 파일 저장 없음)
  ├─ manifest-static-auditor      ──→ findings-static.md ─┐
  └─ manifest-infra-crosschecker  ──→ findings-infra.md  ─┤   (둘은 병렬)
                                                          ↓
                                          manifest-findings-arbiter ──→ report.md
                                                          │
                        ┌───(nonpass: 재감사 대상 지정)────┘
                        ↓
        지정된 감사자만 gap 목록과 함께 재호출 → arbiter 재호출   [최대 2라운드]
                        │
                        └─(2라운드 소진 시)→ report.md 그대로 제출 + "커버리지 미달, 수동 검토 필요" 경고
```

## 정합성 포인트

integration-reviewer가 확인할 것:

1. **에이전트 이름 일치** — 스킬 본문이 `Agent`로 부르는 이름 3개가 `.claude/agents/<name>.md`의
   `name` 및 파일명과 정확히 같은가: `manifest-static-auditor`, `manifest-infra-crosschecker`,
   `manifest-findings-arbiter`. 기존 6개 에이전트와 이름 충돌이 없는가.
2. **경로 문자 일치** — 상류 출력과 하류 입력이 같은 문자열인가.
   - static-auditor 출력 == arbiter 입력 == `_workspace/manifest-review/findings-static.md`
   - crosschecker 출력 == arbiter 입력 == `_workspace/manifest-review/findings-infra.md`
   - arbiter 출력 == 스킬 보고 대상 == `_workspace/manifest-review/report.md`
3. **발견 스키마 동일** — 두 감사자 본문의 발견 항목 필드(`근거/대조/영향/확신도/권고/검사축`)와
   심각도 3등급 명칭이 arbiter가 읽는 형식과 문자 그대로 같은가.
4. **판정 문자열 일치** — arbiter가 내는 `판정: PASS | nonpass`, `재감사 대상:` 라인 형식이
   스킬 본문의 분기 조건과 같은가.
5. **읽기 전용 제약** — 세 에이전트 frontmatter `tools`에 `Edit`·`NotebookEdit`·`Bash`가 **없는가**.
   `Write`가 있는 에이전트는 본문에 "`_workspace/manifest-review/<지정 파일>` 외에는 쓰지 않는다"가
   명시돼 있는가. 스킬 `allowed-tools`에 `Write`/`Edit`가 없는가.
6. **검사 축 분할 무결성** — 1~12번 축이 두 감사자에게 **빠짐없이, 중복 없이** 배정됐는가
   (static: 9·10·11·12 + 매니페스트 내부 참조 / infra: 1~8). arbiter의 커버리지 표가 12축 전부를 덮는가.
7. **루프 종료 보장** — 스킬 본문에 최대 2라운드와 소진 시 실패 종료가 명시돼 있는가.
   arbiter 본문에 "치명 건수는 판정에 영향을 주지 않는다"가 명시돼 커버리지 게이트가 무한 루프를
   만들지 않는가.
8. **headless 자족성** — 세 에이전트 본문 어디에도 사용자에게 되묻는 전제가 없는가.
   특히 static-auditor의 `WebFetch` 실패가 종료가 아니라 `[정보]` 기록으로 처리되는가.
9. **클러스터 의존 없음** — 어떤 에이전트 본문도 `kubectl`·`kustomize build`·`terraform plan` 실행을
   전제하지 않는가.
