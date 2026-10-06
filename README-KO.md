# ChurchStudioPhoneCamera-iOS V2

기준 Android 앱은 V3.8.7이며 Android V3.8.7, Windows READY8R5를 수정하지 않는 별도 iPhone 프로젝트다. READY8R5R1은 폐기본으로 사용하지 않는다.

## V2 변경

- GitHub Actions runner를 `macos-26`으로 변경하고 Xcode 26+ 확인
- 서명 secret을 GitHub `if:`에서 직접 검사하지 않음
- push/PR에서는 무서명 compile만 수행
- TestFlight는 `workflow_dispatch`에서 `deploy_testflight=true`를 명시한 경우만 시도
- 배포 요청 시 9개 secret이 하나라도 없으면 명확히 FAIL
- GitHub run number를 `CURRENT_PROJECT_VERSION`으로 사용해 build number 자동 증가
- compile 전용 Bundle ID를 command line으로만 주입하여 프로젝트 Bundle ID 계약을 유지
- AppIcon asset 추가
- 720p에서 실제 60fps 지원 format을 우선 선택
- VideoToolbox hardware H.264를 필수로 요구하고 사용 여부/encoder ID를 `I_CODEC`로 보고
- `I_LAT`에 `capEnc`, `ptsEnc`를 추가
- Windows용 reusable iPhone CSUV transport adapter 추가

## 중요 상태

이 환경은 macOS/Xcode/iPhone이 아니므로 실제 Xcode compile, TestFlight 업로드, iPhone 카메라/VideoToolbox/usbmux 실물 동작은 아직 PASS가 아니다. GitHub Actions macOS runner와 실제 iPhone 검증 결과로 판정해야 한다.
