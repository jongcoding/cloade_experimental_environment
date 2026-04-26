# 배포 가이드 (운영용)

- 벡터 DB: Qdrant 단일 인스턴스.
- 초기 인덱싱: 공개 정책 99건 + `intern_leak.txt` 1건 (민감, ACL 메타 태그).
- 경계 결함: LangChain-style retriever가 메타데이터 필터를 post-filter로만 적용.
  ACL:restricted 문서도 retrieve 되어 LLM 컨텍스트에 포함.
- 출제자 메모: 본 문제가 영감이 되어 우리 팀이 `bedrock_knowledge_poisoning`
  실험 시나리오를 별도로 제작 중(내부 PoC 단계).
