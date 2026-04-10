# 보안 제약조건

## 절대 하지 말 것

- 실제 프로덕션 AWS 계정에서 실험하지 마라
- 자격증명을 git에 커밋하지 마라
- 다른 사람의 AWS 리소스에 접근하지 마라
- 실험이 끝나면 반드시 `terraform destroy`를 실행해라

## 반드시 할 것

- 전용 실험 계정 사용
- 실험 시작/종료 시 `aws sts get-caller-identity`로 확인
- 비용 알림 설정 ($10/$50/$100 threshold)
- CloudTrail 활성화 (실험 로그 자체도 학습 자료)
- `terraform destroy` 후 잔여 리소스 확인 필수
