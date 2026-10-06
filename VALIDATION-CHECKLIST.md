# 실물 검증 체크리스트

검증자는 코드를 수정하지 말고 결과와 로그만 전달해도 됩니다.

1. Xcode build 성공 여부 / Xcode 버전 / iOS 버전 / iPhone 모델
2. 앱 실행 후 카메라 권한 허용
3. 후면 카메라 미리보기 정상
4. 720p에서 상태가 1280x720@60 또는 기기 지원 fallback fps로 표시되는지
5. 줌 슬라이더 작동
6. 전면/후면 전환 작동
7. Windows에서 iPhone USB 인식
8. `iproxy.exe 39877 39877` 연결 유지
9. `RUN-VALIDATION.bat`에서 `handshake PASS`
10. CONFIG 최소 1개 후 VIDEO 수신
11. STATUS의 `I_CODEC`, `I_LAT` 값 기록
12. `iphone_capture.h264`를 ffplay/VLC 등으로 열었을 때 영상 정상
13. 5분 연결 유지
14. 케이블 분리 후 재연결 시험
15. 체감 지연: 손동작/시계 등을 iPhone 화면과 PC 화면에서 동시 촬영하여 비교

실패 시 필요한 자료:
- Xcode build error 전체
- iPhone 앱 화면 캡처
- `iproxy` 콘솔
- `RUN-VALIDATION.bat` 콘솔 전체
- 생성된 `iphone_capture.h264`가 있다면 그 파일
