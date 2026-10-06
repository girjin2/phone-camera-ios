# TestFlight 설정 V2

## 먼저 알아둘 점

- push/PR은 무서명 compile만 한다.
- TestFlight 업로드는 Actions의 **Run workflow**에서 `deploy_testflight=true`를 선택한 때만 시도한다.
- deploy를 요청했는데 secret이 하나라도 없으면 workflow는 실패하며 배포 성공으로 표시하지 않는다.
- 2026년 App Store Connect 업로드용 iOS 앱은 Xcode 26+ / iOS 26 SDK로 빌드해야 하므로 CI는 `macos-26`을 사용한다.
- 빌드 번호는 GitHub `run_number`로 자동 증가한다.

## Apple/GitHub 준비 순서

1. Apple Developer Program 가입 확인
2. App ID 및 실제 Bundle ID 생성
3. App Store Connect에서 동일 Bundle ID 앱 생성
4. Apple Distribution 인증서 생성 후 `.p12` 내보내기
5. App Store 배포용 provisioning profile 생성
6. App Store Connect API Key 생성 후 Key ID / Issuer ID / `.p8` 보관
7. GitHub 저장소 Settings → Secrets and variables → Actions에 아래 9개 Secret 등록

| Secret | 값 |
|---|---|
| APP_STORE_CONNECT_KEY_ID | API Key ID |
| APP_STORE_CONNECT_ISSUER_ID | Issuer ID |
| APP_STORE_CONNECT_API_KEY_BASE64 | `.p8` 전체 파일의 base64 |
| APPLE_TEAM_ID | Developer Team ID |
| IOS_BUNDLE_ID | App ID의 Bundle ID |
| IOS_DISTRIBUTION_CERT_BASE64 | `.p12` 파일의 base64 |
| IOS_DISTRIBUTION_CERT_PASSWORD | `.p12` 암호 |
| IOS_PROVISIONING_PROFILE_BASE64 | `.mobileprovision` base64 |
| KEYCHAIN_PASSWORD | CI 임시 keychain용 랜덤 암호 |

PowerShell base64 예: `[Convert]::ToBase64String([IO.File]::ReadAllBytes('파일경로'))`

8. Actions → `iOS build and TestFlight` → `Run workflow`
9. 먼저 `deploy_testflight=false`로 compile PASS 확인
10. 9개 secret 등록 후 `deploy_testflight=true`로 실행
11. App Store Connect → TestFlight에서 build 처리 확인
12. 테스터 그룹/초대 링크 설정 후 iPhone TestFlight에서 설치

credential 원본 파일과 secret 값은 저장소에 커밋하지 않는다.
