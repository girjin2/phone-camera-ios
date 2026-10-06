import Foundation
import AVFoundation
import SwiftUI

final class CameraController: NSObject, ObservableObject {
    @Published var statusText = "준비 중"
    @Published var transportText = "USB 대기"
    @Published var zoom: CGFloat = 1.0
    @Published var selectedHeight = 720
    @Published var effectiveFPS = 30
    @Published var usingFrontCamera = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ChurchStudio.iOS.camera.session")
    private let videoQueue = DispatchQueue(label: "ChurchStudio.iOS.camera.frames", qos: .userInteractive)
    private let encoder = H264Encoder()
    private let transport = CsuvTransport()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var cachedConfig = Data()
    private var streamReady = false
    private var frames: UInt64 = 0
    private var lastDiagnosticsFrame: UInt64 = 0
    private var lastEncodeMs: Double = 0
    private var lastCaptureToEncodeMs: Double = 0
    private var lastPtsToOutputMs: Double = -1

    override init() {
        super.init()
        encoder.delegate = self
        transport.delegate = self
    }

    func start() {
        transport.start()
        requestCameraPermissionAndStart()
    }

    func stop() {
        transport.stop()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            self.encoder.stop()
        }
    }

    func setResolution(_ height: Int) {
        guard height == 720 || height == 1080 else { return }
        selectedHeight = height
        restartCamera()
    }

    func switchCamera() {
        usingFrontCamera.toggle()
        restartCamera()
    }

    func setZoom(_ newZoom: CGFloat) {
        zoom = newZoom
        sessionQueue.async { [weak self] in
            guard let self, let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = min(max(1.0, newZoom), device.activeFormat.videoMaxZoomFactor)
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                self.publishStatus("줌 설정 실패: \(error)")
            }
        }
    }

    func requestKeyframe() { encoder.requestKeyframe() }

    private func requestCameraPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            restartCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.restartCamera() }
                else { self?.publishStatus("카메라 권한이 필요합니다") }
            }
        default:
            publishStatus("설정에서 카메라 권한을 허용하세요")
        }
    }

    private func restartCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            self.encoder.stop()
            do {
                try self.configureSession()
                self.session.startRunning()
            } catch {
                self.publishStatus("카메라 시작 실패: \(error)")
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for oldInput in session.inputs { session.removeInput(oldInput) }
        for oldOutput in session.outputs { session.removeOutput(oldOutput) }

        session.sessionPreset = .inputPriority
        let position: AVCaptureDevice.Position = usingFrontCamera ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw NSError(domain: "ChurchStudio.Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "카메라를 찾을 수 없습니다"])
        }
        let selected = chooseFormat(device: device, targetHeight: selectedHeight)
        guard let selected else {
            throw NSError(domain: "ChurchStudio.Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(selectedHeight)p 형식을 찾을 수 없습니다"])
        }
        let chosenFPS = chooseFPS(format: selected, targetHeight: selectedHeight)

        try device.lockForConfiguration()
        device.activeFormat = selected
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(chosenFPS))
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(chosenFPS))
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        let maxZoom = max(1.0, selected.videoMaxZoomFactor)
        let clampedZoom = min(max(1.0, zoom), maxZoom)
        device.videoZoomFactor = clampedZoom
        device.unlockForConfiguration()

        let newInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(newInput) else { throw NSError(domain: "ChurchStudio.Camera", code: 3) }
        session.addInput(newInput)
        input = newInput

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw NSError(domain: "ChurchStudio.Camera", code: 4) }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = usingFrontCamera }
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
        }

        let dims = CMVideoFormatDescriptionGetDimensions(selected.formatDescription)
        try encoder.configure(width: Int(dims.width), height: Int(dims.height), fps: chosenFPS)
        DispatchQueue.main.async {
            self.effectiveFPS = chosenFPS
            self.zoom = clampedZoom
            self.statusText = "\(self.usingFrontCamera ? "FRONT" : "BACK") \(dims.width)x\(dims.height)@\(chosenFPS) VT-H264 ON"
        }
    }

    private func chooseFormat(device: AVCaptureDevice, targetHeight: Int) -> AVCaptureDevice.Format? {
        let targetWidth = targetHeight <= 720 ? 1280 : 1920
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width >= dims.height && Int(dims.width) * 9 == Int(dims.height) * 16
        }
        let exact = candidates.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return Int(dims.width) == targetWidth && Int(dims.height) == targetHeight
        }

        // iPhones can expose several 1280x720 formats. Prefer the exact format that
        // actually advertises 60 fps instead of accepting the first 720p format and
        // accidentally falling back to 30 fps.
        if targetHeight <= 720, let exact60 = exact.first(where: { supportsFPS($0, 60) }) {
            return exact60
        }
        if let exact30 = exact.first(where: { supportsFPS($0, 30) }) {
            return exact30
        }
        if let firstExact = exact.first { return firstExact }

        return candidates.min { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            let ld = abs(Int(l.height) - targetHeight) + abs(Int(l.width) - targetWidth)
            let rd = abs(Int(r.height) - targetHeight) + abs(Int(r.width) - targetWidth)
            if ld != rd { return ld < rd }
            if targetHeight <= 720 {
                let l60 = supportsFPS(lhs, 60)
                let r60 = supportsFPS(rhs, 60)
                if l60 != r60 { return l60 && !r60 }
            }
            return (lhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0) >
                (rhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
        }
    }

    private func supportsFPS(_ format: AVCaptureDevice.Format, _ fps: Double) -> Bool {
        format.videoSupportedFrameRateRanges.contains { range in
            range.minFrameRate <= fps && range.maxFrameRate >= fps
        }
    }

    private func chooseFPS(format: AVCaptureDevice.Format, targetHeight: Int) -> Int {
        let ranges = format.videoSupportedFrameRateRanges
        if targetHeight <= 720, supportsFPS(format, 60) { return 60 }
        if supportsFPS(format, 30) { return 30 }
        return max(1, Int(ranges.map(\.maxFrameRate).max() ?? 30))
    }

    private func publishStatus(_ text: String) {
        DispatchQueue.main.async { self.statusText = text }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let callbackNs = DispatchTime.now().uptimeNanoseconds
        encoder.encode(sampleBuffer: sampleBuffer, captureCallbackNs: callbackNs)
    }
}

extension CameraController: H264EncoderDelegate {
    func encoder(_ encoder: H264Encoder, didProduceConfig annexB: Data) {
        cachedConfig = annexB
        if streamReady { _ = transport.sendConfig(annexB: annexB) }
    }

    func encoder(
        _ encoder: H264Encoder,
        didProduceFrame annexB: Data,
        ptsUs: UInt64,
        keyframe: Bool,
        encodeMs: Double,
        captureToEncodeMs: Double,
        ptsToOutputMs: Double
    ) {
        frames &+= 1
        lastEncodeMs = encodeMs
        lastCaptureToEncodeMs = captureToEncodeMs
        lastPtsToOutputMs = ptsToOutputMs
        guard streamReady else { return }
        _ = transport.sendVideo(ptsUs: ptsUs, keyframe: keyframe, annexB: annexB)
        let fps = UInt64(max(1, effectiveFPS))
        if frames - lastDiagnosticsFrame >= fps {
            lastDiagnosticsFrame = frames
            let text = String(
                format: "I_LAT f=%llu fps=%d enc=%.2f capEnc=%.2f ptsEnc=%.2f q=%.2f wr=%.2f d=%llu depth=%d",
                frames, effectiveFPS, lastEncodeMs, lastCaptureToEncodeMs, lastPtsToOutputMs,
                Double(transport.lastQueueWaitUs) / 1000.0,
                Double(transport.lastWriteUs) / 1000.0,
                transport.videoDrops, 0
            )
            _ = transport.sendStatus(text)
        }
    }

    func encoder(_ encoder: H264Encoder, didChangeStatus text: String) {
        publishStatus(text)
        if streamReady { _ = transport.sendStatus("I_CODEC \(text)") }
    }
}

extension CameraController: CsuvTransportDelegate {
    func transportDidBecomeVideoReady(_ transport: CsuvTransport) {
        streamReady = false
        if !cachedConfig.isEmpty, transport.sendConfig(annexB: cachedConfig) {
            streamReady = true
            encoder.requestKeyframe()
        } else {
            // Encoder will send CONFIG as soon as VideoToolbox exposes SPS/PPS.
            streamReady = true
            encoder.requestKeyframe()
        }
    }

    func transportDidDisconnect(_ transport: CsuvTransport) {
        streamReady = false
    }

    func transport(_ transport: CsuvTransport, didChangeStatus text: String) {
        transportText = text
    }
}
