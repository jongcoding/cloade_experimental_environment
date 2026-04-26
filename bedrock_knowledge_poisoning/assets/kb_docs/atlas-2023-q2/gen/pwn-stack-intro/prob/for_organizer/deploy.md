# 배포 가이드 (운영용)

- 바이너리 컴파일: `gcc -m32 -fno-stack-protector -no-pie chal.c -o chal`
- xinetd 설정으로 9001 포트에 연결 당 새 프로세스 생성.
- flag는 컨테이너 안 `/flag` (읽기 전용, win() 만 읽을 수 있게 chmod 740).
