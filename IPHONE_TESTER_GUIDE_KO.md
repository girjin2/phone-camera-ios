# iPhone 검증자 안내 (Mac 불필요)

준비물: TestFlight가 설치된 iPhone, 데이터 통신 가능한 USB 케이블, Windows PC, 설치 초대 링크, iproxy 실행 파일.

1. App Store에서 TestFlight를 설치한다.
2. 받은 초대 링크를 iPhone에서 열어 ChurchStudio Phone Camera를 설치한다.
3. iPhone을 USB로 Windows에 연결하고 “이 컴퓨터를 신뢰”를 승인한다.
4. 앱을 실행하고 카메라 권한을 허용한다. 기본은 후면 카메라다.
5. 앱 상단에서 카메라(BACK/FRONT), 실제 해상도, fps, TCP 상태를 확인한다. 필요하면 720p/1080p, 줌 슬라이더, 전후면 전환 버튼을 사용한다.
6. Windows에서 iproxy.exe 39877 39877 을 실행한다.
7. Windows ChurchStudio의 iPhone transport를 선택한다. 아직 READY8R5 본체에 adapter가 통합되지 않은 경우, 이 소스의 WindowsValidation/RUN-VALIDATION.bat으로 CSUV 수신만 검증한다.

앱이 백그라운드로 가거나 화면이 잠기면 iOS 정책상 TCP listener와 카메라가 중단될 수 있다. 검증 중에는 앱을 전면에 유지한다.

실제 iPhone에서 위 절차를 수행하기 전에는 카메라, VideoToolbox, USB/usbmux, READY8R5 디코더 재생을 PASS로 판정하지 않는다.
