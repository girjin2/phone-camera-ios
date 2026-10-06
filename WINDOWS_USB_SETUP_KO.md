# Windows USB / iPhone transport 준비

이 프로젝트는 Android AOA를 사용하지 않는다. iPhone 앱이 TCP 39877을 listen하고, Windows의 usbmux/iproxy가 USB를 통해 127.0.0.1:39877로 전달한다.

1. Windows에 Apple Devices 또는 Apple Mobile Device Support를 설치하고 iPhone이 탐색기/장치 관리자에서 인식되는지 확인한다.
2. 신뢰할 수 있는 배포본의 iproxy.exe(libusbmuxd)를 준비하고 PowerShell 또는 명령 프롬프트에서 실행한다: iproxy.exe 39877 39877
3. iPhone에서 ChurchStudio Phone Camera를 전면으로 열고 카메라 권한을 허용한다.
4. 연결 검증은 WindowsValidation/RUN-VALIDATION.bat으로 수행한다.
5. 출력에 handshake PASS, CONFIG, VIDEO, I_LAT가 보이면 USB 터널과 CSUV 전송까지 성공이다. 생성된 iphone_capture.h264는 검증 산출물일 뿐 READY8R5 수정은 아니다.

READY8R5 통합 원칙:

- Android Phone Camera의 AOA 경로는 유지한다.
- iPhone용 adapter는 127.0.0.1:39877 TCP client만 담당하고 HELO/HACK, PING/PONG, CSUV header를 처리한다.
- adapter가 낸 Annex-B H.264 CONFIG/VIDEO를 기존 MF decoder 입력 경계로 전달한다.
- 기존 MF decoder, GPU renderer 및 그 이후 경로는 재사용하며 변경하지 않는다.
- 이 저장소에는 READY8R5 코드나 바이너리가 포함되지 않았고 수정하지 않았다. READY8R5R1은 사용하지 않는다.
