# READY8R5 iPhone transport 통합 계약

이 V2에는 READY8R5 전체 소스가 포함되어 있지 않으므로 production 파일을 임의 수정하지 않는다. 대신 `iphone_csuv_transport.py`가 iPhone 전용 경계까지 구현한다.

연결 순서:

1. Windows에서 `iproxy 39877 39877` 실행
2. `IPhoneCsuvClient.connect()`가 HELO/HACK/PING/PONG 수행
3. `packets()`에서 Android와 동일한 CSUV CONFIG/VIDEO/STATUS 구조를 받음
4. CONFIG/VIDEO payload를 READY8R5의 기존 phone CSUV parser/MF decoder ingress에 연결
5. MF decoder/GPU renderer 이후 공통 경로는 변경 금지

중요: READY8R5 기준 소스 없이 production 통합 완료라고 판정하지 않는다. 이 파일은 transport adapter와 통합 계약만 제공한다.
