# Android V3.8.7 → iOS V2 mapping

- Camera2 → AVFoundation / AVCaptureSession
- MediaCodec AVC surface encoder → VideoToolbox VTCompressionSession
- `KEY_MAX_B_FRAMES=0` / low latency → `RealTime=true`, `AllowFrameReordering=false`
- 1-second IDR → MaxKeyFrameInterval/Duration = 1s
- AOA UsbOutputWriter MAX_VIDEO_QUEUE=1 → CsuvTransport latest-one application queue
- AOA control loop → TCP control loop with identical HELO/HACK/PING/PONG messages
- CsuvProtocol.kt → CsuvProtocol.swift, byte-for-byte compatible header layout
- Android CONFIG from csd-0/csd-1 → iOS SPS/PPS from CMVideoFormatDescription
- Android AVCC→Annex-B → iOS AVCC length prefixes rewritten to Annex-B start codes

Apple/Qualcomm vendor-specific knobs are intentionally not copied. QTI's `vendor.qti-ext-enc-low-latency.enable` is Android Qualcomm-specific; iOS uses VideoToolbox's real-time encoder controls instead.


V2 추가 원칙:

- VideoToolbox H.264는 hardware encoder를 필수로 요청하고 실제 사용 여부를 확인한다.
- Apple의 `EnableLowLatencyRateControl`은 infinite GOP/High profile 동작을 강제하므로, Android/CSUV의 약 1초 IDR recovery 계약을 보존하기 위해 V2에서는 사용하지 않는다.
- `I_LAT enc`는 encode submit→output, `capEnc`는 AVCapture callback→output, `ptsEnc`는 camera sample PTS→output의 진단값이다. `ptsEnc=-1`이면 clock domain 불일치로 해석하지 않는다.
