# iOS V2 검증 체크리스트

## CI
- [ ] GitHub Actions compile job이 `macos-26`에서 Xcode 26+로 PASS
- [ ] `deploy_testflight=false`에서는 signed archive/TestFlight step이 실행되지 않음
- [ ] `deploy_testflight=true` + secret 누락 시 명확히 FAIL
- [ ] 9개 secret이 모두 있을 때 archive/IPA export/TestFlight upload 성공
- [ ] 두 번째 workflow에서도 build number가 증가하여 업로드 가능
- [ ] App Store Connect/TestFlight에서 AppIcon이 표시됨

## iPhone 카메라/인코더
- [ ] 후면 기본 / 전후면 전환
- [ ] 720p에서 지원 기기는 실제 60fps 선택, 미지원은 30fps fallback
- [ ] 1080p 선택
- [ ] 줌
- [ ] `I_CODEC`에 `hardware=1` 및 encoder ID 표시
- [ ] CONFIG가 VIDEO보다 먼저 도착
- [ ] 약 1초 주기 IDR
- [ ] `I_LAT`에서 `enc`, `capEnc`, `ptsEnc`, `q`, `wr`, `d` 확인
- [ ] `ptsEnc=-1`이면 clock domain이 host time과 맞지 않은 것이므로 센서 지연으로 해석하지 않음

## USB/usbmux
- [ ] Apple Devices/드라이버에서 iPhone 인식
- [ ] `iproxy 39877 39877` 연결
- [ ] HELO/HACK/PING/PONG PASS
- [ ] 30초 CSUV CONFIG/VIDEO/STATUS 수신
- [ ] 재연결
- [ ] 장시간 안정성

## READY8R5
- [ ] iPhone adapter가 받은 CONFIG/VIDEO를 기존 phone MF ingress에 연결
- [ ] 기존 MF decoder/GPU renderer 변경 없음
- [ ] Android V3.8.7 동작 회귀 없음

READY8R5 기준 소스가 이 ZIP에 없으므로 마지막 production 통합은 별도 검증 항목이다.
