import Foundation
import AVFoundation
import VideoToolbox

protocol H264EncoderDelegate: AnyObject {
    func encoder(_ encoder: H264Encoder, didProduceConfig annexB: Data)
    func encoder(
        _ encoder: H264Encoder,
        didProduceFrame annexB: Data,
        ptsUs: UInt64,
        keyframe: Bool,
        encodeMs: Double,
        captureToEncodeMs: Double,
        ptsToOutputMs: Double
    )
    func encoder(_ encoder: H264Encoder, didChangeStatus text: String)
}

final class H264Encoder {
    weak var delegate: H264EncoderDelegate?

    private var session: VTCompressionSession?
    private var width = 1280
    private var height = 720
    private var fps = 60
    private var bitrate = 6_000_000
    private var cachedConfig = Data()
    private var frameCount: UInt64 = 0
    private var forceKeyframeNext = false
    private let callbackQueue = DispatchQueue(label: "ChurchStudio.iOS.encoder.callback")

    private final class FrameContext {
        let captureCallbackNs: UInt64
        let encodeSubmitNs: UInt64
        let sourcePTS: CMTime

        init(captureCallbackNs: UInt64, encodeSubmitNs: UInt64, sourcePTS: CMTime) {
            self.captureCallbackNs = captureCallbackNs
            self.encodeSubmitNs = encodeSubmitNs
            self.sourcePTS = sourcePTS
        }
    }

    func configure(width: Int, height: Int, fps: Int) throws {
        stop()
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = {
            if height >= 1080 && fps >= 60 { return 12_000_000 }
            if height >= 1080 { return 8_000_000 }
            if fps >= 60 { return 6_000_000 }
            return 4_000_000
        }()

        // For ChurchStudio this must stay on the hardware path. If hardware H.264
        // cannot be allocated, fail loudly instead of silently falling back to a
        // software encoder with much higher and less predictable latency.
        let encoderSpecification = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any
        ] as CFDictionary

        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpecification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: Self.outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &created
        )
        guard status == noErr, let created else {
            throw NSError(domain: "ChurchStudio.H264", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "VT hardware H.264 session creation failed \(status)"])
        }
        session = created

        set(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        set(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        set(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        set(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        set(created, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        set(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: max(1, fps)))
        set(created, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1.0))
        let bytesPerSecond = max(1, bitrate / 8)
        set(created, key: kVTCompressionPropertyKey_DataRateLimits, value: [NSNumber(value: bytesPerSecond), NSNumber(value: 1)] as CFArray)

        let prepare = VTCompressionSessionPrepareToEncodeFrames(created)
        guard prepare == noErr else {
            stop()
            throw NSError(domain: "ChurchStudio.H264", code: Int(prepare), userInfo: [NSLocalizedDescriptionKey: "VT prepare failed \(prepare)"])
        }

        let usingHardware = copyBoolProperty(created, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder)
        let encoderID = copyStringProperty(created, key: kVTCompressionPropertyKey_EncoderID) ?? "unknown"
        guard usingHardware == true else {
            stop()
            throw NSError(domain: "ChurchStudio.H264", code: -2, userInfo: [NSLocalizedDescriptionKey: "VideoToolbox did not confirm hardware encoding"])
        }

        frameCount = 0
        cachedConfig.removeAll(keepingCapacity: true)
        delegate?.encoder(
            self,
            didChangeStatus: "VT H.264 ON \(width)x\(height)@\(fps) bitrate=\(bitrate) hardware=1 encoder=\(encoderID) realTime=1 reorder=0"
        )
    }

    func stop() {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
        cachedConfig.removeAll()
    }

    func requestKeyframe() {
        forceKeyframeNext = true
    }

    func encode(sampleBuffer: CMSampleBuffer, captureCallbackNs: UInt64) {
        guard let session, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let submitNs = DispatchTime.now().uptimeNanoseconds
        let context = Unmanaged.passRetained(
            FrameContext(captureCallbackNs: captureCallbackNs, encodeSubmitNs: submitNs, sourcePTS: pts)
        ).toOpaque()

        let properties: CFDictionary?
        if forceKeyframeNext {
            forceKeyframeNext = false
            properties = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        } else {
            properties = nil
        }

        var infoFlags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: pts,
            duration: duration.isValid ? duration : CMTime(value: 1, timescale: CMTimeScale(max(1, fps))),
            frameProperties: properties,
            sourceFrameRefcon: context,
            infoFlagsOut: &infoFlags
        )
        if status != noErr {
            Unmanaged<FrameContext>.fromOpaque(context).release()
            delegate?.encoder(self, didChangeStatus: "VT encode submit failed \(status)")
        }
    }

    private func set(_ session: VTCompressionSession, key: CFString, value: CFTypeRef) {
        let status = VTSessionSetProperty(session, key: key, value: value)
        if status != noErr {
            delegate?.encoder(self, didChangeStatus: "VT property \(key) failed \(status)")
        }
    }

    private func copyBoolProperty(_ session: VTCompressionSession, key: CFString) -> Bool? {
        var value: CFTypeRef?
        let status = VTSessionCopyProperty(session, key: key, allocator: kCFAllocatorDefault, valueOut: &value)
        guard status == noErr, let value else { return nil }
        return value as? Bool
    }

    private func copyStringProperty(_ session: VTCompressionSession, key: CFString) -> String? {
        var value: CFTypeRef?
        let status = VTSessionCopyProperty(session, key: key, allocator: kCFAllocatorDefault, valueOut: &value)
        guard status == noErr, let value else { return nil }
        return value as? String
    }

    private static let outputCallback: VTCompressionOutputCallback = { refcon, sourceRefcon, status, _, sampleBuffer in
        guard let refcon else { return }
        let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        let context: FrameContext? = sourceRefcon.map { Unmanaged<FrameContext>.fromOpaque($0).takeRetainedValue() }
        guard status == noErr, let sampleBuffer, CMSampleBufferDataIsReady(sampleBuffer) else {
            encoder.delegate?.encoder(encoder, didChangeStatus: "VT output failed \(status)")
            return
        }
        encoder.handleOutput(sampleBuffer, frameContext: context)
    }

    private func handleOutput(_ sampleBuffer: CMSampleBuffer, frameContext: FrameContext?) {
        callbackQueue.async { [weak self] in
            guard let self else { return }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
            let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            let keyframe = !notSync

            if keyframe,
               let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let config = self.makeConfig(format),
               config != self.cachedConfig {
                self.cachedConfig = config
                self.delegate?.encoder(self, didProduceConfig: config)
            }
            guard let payload = self.makeAnnexB(sampleBuffer) else { return }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let ptsUs: UInt64 = {
                guard pts.isValid, pts.timescale != 0 else { return 0 }
                let seconds = CMTimeGetSeconds(pts)
                return seconds.isFinite && seconds > 0 ? UInt64(seconds * 1_000_000.0) : 0
            }()

            let nowNs = DispatchTime.now().uptimeNanoseconds
            let encodeMs = frameContext.map { Double(nowNs &- $0.encodeSubmitNs) / 1_000_000.0 } ?? -1
            let captureToEncodeMs = frameContext.map { Double(nowNs &- $0.captureCallbackNs) / 1_000_000.0 } ?? -1
            let ptsToOutputMs = frameContext.map { self.hostClockDeltaMs(from: $0.sourcePTS) } ?? -1

            self.frameCount &+= 1
            self.delegate?.encoder(
                self,
                didProduceFrame: payload,
                ptsUs: ptsUs,
                keyframe: keyframe,
                encodeMs: encodeMs,
                captureToEncodeMs: captureToEncodeMs,
                ptsToOutputMs: ptsToOutputMs
            )
        }
    }

    /// AVCaptureVideoDataOutput presentation timestamps are normally expressed on
    /// the host-time timeline. Keep this value diagnostic-only: if a device returns
    /// a different clock domain, reject unreasonable/negative deltas instead of
    /// reporting them as sensor latency.
    private func hostClockDeltaMs(from sourcePTS: CMTime) -> Double {
        guard sourcePTS.isValid, sourcePTS.timescale != 0 else { return -1 }
        let hostNow = CMClockGetTime(CMClockGetHostTimeClock())
        let delta = CMTimeGetSeconds(CMTimeSubtract(hostNow, sourcePTS)) * 1000.0
        guard delta.isFinite, delta >= 0, delta < 10_000 else { return -1 }
        return delta
    }

    private func makeConfig(_ format: CMFormatDescription) -> Data? {
        var parameterCount = 0
        let countStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format as! CMVideoFormatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterCount,
            nalUnitHeaderLengthOut: nil
        )
        guard countStatus == noErr, parameterCount > 0 else { return nil }
        var out = Data()
        let startCode: [UInt8] = [0, 0, 0, 1]
        for index in 0..<parameterCount {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            var count = 0
            var headerLength: Int32 = 0
            let st = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format as! CMVideoFormatDescription,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: &headerLength
            )
            guard st == noErr, let pointer, size > 0 else { continue }
            out.append(contentsOf: startCode)
            out.append(pointer, count: size)
        }
        return out.isEmpty ? nil : out
    }

    /// VideoToolbox H.264 samples are AVCC. iOS normally uses a 4-byte NAL length field,
    /// exactly the same width as the Annex-B start code, so copy once and rewrite each
    /// length prefix in place.
    private func makeAnnexB(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let copyStatus = data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return kCMBlockBufferBadLengthParameterErr }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        guard copyStatus == kCMBlockBufferNoErr else { return nil }

        var valid = true
        data.withUnsafeMutableBytes { raw in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { valid = false; return }
            var offset = 0
            while offset + 4 <= length {
                let nalLength = (Int(bytes[offset]) << 24) |
                    (Int(bytes[offset + 1]) << 16) |
                    (Int(bytes[offset + 2]) << 8) |
                    Int(bytes[offset + 3])
                guard nalLength > 0, offset + 4 + nalLength <= length else { valid = false; return }
                bytes[offset] = 0
                bytes[offset + 1] = 0
                bytes[offset + 2] = 0
                bytes[offset + 3] = 1
                offset += 4 + nalLength
            }
            if offset != length { valid = false }
        }
        return valid ? data : nil
    }
}
