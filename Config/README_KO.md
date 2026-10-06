# 설정값 원칙

IOS_BUNDLE_ID와 APPLE_TEAM_ID는 저장소 파일에 넣지 않는다. GitHub Actions에서는 Secret IOS_BUNDLE_ID와 APPLE_TEAM_ID가 전달한다. 로컬 Xcode archive에는 승인받은 실제 값을 build setting 또는 환경 변수로 명시한다.

ExportOptions.plist는 배포 요구사항을 보이는 템플릿이다. CI export는 provisioning profile 내부 Name을 런타임에 읽어 fastlane에 전달하므로, template에 실제 Team ID, Bundle ID, profile 이름을 기록하지 않는다.
