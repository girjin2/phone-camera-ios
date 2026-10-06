# V2 변경 감사

V1 검토에서 확인한 배포/코드 문제를 수정한 후보.

수정됨:
1. GitHub Actions secret을 job-level `if`에서 직접 참조하던 구조 제거
2. macOS 26 / Xcode 26+ compile 및 archive 구조
3. AppIcon asset 추가
4. GitHub run number 기반 build number 자동 증가
5. 무서명 compile에서 CI 전용 Bundle ID를 command line으로 주입
6. reusable Windows iPhone CSUV transport adapter 추가(READY8R5 production patch는 기준 소스 부재로 미실행)
7. `I_LAT` 의미를 확장: enc=encode submit→output, capEnc=capture callback→output, ptsEnc=camera sample PTS→output 진단값
8. VideoToolbox hardware encoder 필수 + 실제 hardware 사용 확인/encoder ID 보고
9. 720p60 지원 format 우선 선택

미검증:
- 실제 Xcode compile
- Apple signing/TestFlight
- iPhone AVFoundation/VideoToolbox
- usbmux/iproxy 실물
- READY8R5 production integration
