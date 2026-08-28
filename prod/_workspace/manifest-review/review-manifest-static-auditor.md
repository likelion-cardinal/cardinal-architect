# review: manifest-static-auditor

판정: PASS (만족도 92%)
검수자: make-agent-reviewer
라운드: 1

## 하드 요구사항 9/9 충족
tools에 Edit/NotebookEdit/Bash 없음 · model sonnet · name==파일명 ·
출력경로 findings-static.md 고정 + 배타성 명시 · WebFetch 실패 비종료 ·
kubectl/kustomize/terraform 미전제 · terraform 미열람 경계 · headless 자족 · 수정 금지

발견 스키마가 team-spec L54-61과 문자 그대로 일치(주석·플레이스홀더까지). arbiter 파싱 계약 통과.

## 수정 지시 (비차단 3건)
1. [모순] 인벤토리 범위 고정(L117)과 app-node 부재 판정(L104-107)이 충돌.
   빈 디렉토리·부재 경로는 인벤토리에 없어 사용자 핵심 관심사가 스킵될 수 있음.
   → "파일을 읽는 범위가 목록이며, 경로 존재 여부 확인(Glob)은 manifest/** 하위 목록 밖에도 허용" 예외 추가.
2. [모순] "내부 참조 일관성"은 번호가 없어 커버리지 세 형식(`축 N:`)으로 표현 불가(L231).
   → 축 9~12 중 해당 축에 산입하고 별도 커버리지 행을 만들지 않도록 명시.
3. [형식] L139 예시가 `미검사(사유: ...)`로 리터럴 접두어를 넣어 템플릿 L150 `미검사(<사유>)`와 불일치.
   → `미검사(인벤토리에 setup.txt 없음)`으로 통일.

## 작성자 재량 판단 — 3건 모두 타당
- 인벤토리 부재 시 Glob 폴백: 패턴이 team-spec L29와 문자 일치, headless 자족성 강화
- 매니페스트 0개 시 미검사 파일 작성 후 반환: 스킬 4단계 무의미 재호출 방지
- Write 실패 시 1회 재시도 후 텍스트 보고: 경로 고정 유지하며 루프 없음
