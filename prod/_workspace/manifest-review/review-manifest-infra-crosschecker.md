# review: manifest-infra-crosschecker

판정: PASS (만족도 94%)
검수자: make-agent-reviewer
라운드: 1

## 하드 요구사항 10개 — 8 충족 / 2 부분충족
tools 정확히 Read,Glob,Grep,Write (Edit/NotebookEdit/Bash/WebFetch 없음) · model opus ·
name==파일명 · 출력경로 findings-infra.md 고정 + 배타성 · 축 1~8 전부 존재 ·
plan/kubectl 미전제 · headless 자족 · 수정 금지

세부 지시 반영 확인: 축1 root main.tf 오버라이드 / 축3 local.name 수동 전개 + IRSA /
축6 mkdir 주체 + DirectoryOrCreate / 축7 정량 합산 / 축8 4789·179

발견 스키마 team-spec L54-60과 문자 그대로 일치(후행 공백·주석까지).

## 수정 지시 (비차단 3건)
1. [경계, 권장반영] 경계 절이 static-auditor 영역을 내용으로만 열거하고 축 번호(9~12)를 안 씀.
   특히 축 10(Namespace 존재 전제)이 열거에서 누락 → 침범 여지.
   → 축 번호를 명시하고 열거에 Namespace 전제·이미지 태그 존재 추가.
   → 축 5 절에 "이미지 태그 존재=static / 버전 마이너 정합=내 몫" 경계 한 줄 추가.
2. [작업원칙] "근거:와 (사실상 항상) 대조:" 의 완충어가 생략 가능으로 읽힘.
   축 1~8은 전부 교차 검사라 생략 여지 없음. 단정문으로 교체.
   ※ 스키마 블록 안의 "(교차 검사가 아니면 생략)"은 절대 수정 금지 — arbiter 파싱 계약.
3. [예시, 선택] 커버리지 예시가 `미검사`로 끝나 기본 출력 형태로 모방될 위험.
   → `검사함(발견 2건)`으로 바꾸고 미검사 형식은 에러 핸들링 절에만.

## 작성자 재량 판단 — 3건 모두 타당
- 인벤토리 부재 시 Glob 폴백: 대안이 되묻기라 정합성 포인트 8 준수에 필요
- 축 7 인스턴스 타입 "테라폼 실제 값 우선": team-spec 값 하드코딩보다 우수, 거짓양성 방지
- 축 5 argo-cd 지원범위 확신도 추정: WebFetch 미보유 + 정보 등급 정의와 정합, arbiter 병합에 위임
