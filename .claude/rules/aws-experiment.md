---
paths:
  - "**/*.sh"
  - "**/validation/**"
  - "**/attack_scripts/**"
---

# AWS CLI 실험 규칙

## 명령어 형식

- 항상 `--output json` 사용 (파싱 가능한 형태)
- 항상 `--region` 명시
- 에러 출력도 반드시 기록 (`2>&1`)
- 자격증명은 환경변수로 설정 (프로필이 아닌)

## 실험 전 확인

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="us-east-1"
aws sts get-caller-identity
```

## 실험 기록 형식

```markdown
## Experiment: [실험 ID]-[짧은 제목]
### 가설: [어떤 조건에서 어떤 결과를 기대하는지]
### 실행: [정확한 명령어와 출력 결과 전문]
### 결과: 성공/실패 + 에러 메시지 전문
### 발견: [새로 알게 된 사실]
### 다음 단계: [이 결과를 바탕으로 할 것]
```
