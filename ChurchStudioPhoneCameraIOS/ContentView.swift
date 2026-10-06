import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraController()

    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .background(Color.black)

            VStack(spacing: 8) {
                HStack {
                    Text(camera.statusText)
                    Spacer()
                    Text(camera.transportText)
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(8)
                .background(.black.opacity(0.58))
                .foregroundStyle(.white)

                Spacer()

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button(camera.selectedHeight == 720 ? "720p ✓" : "720p") { camera.setResolution(720) }
                        Button(camera.selectedHeight == 1080 ? "1080p ✓" : "1080p") { camera.setResolution(1080) }
                        Button(camera.usingFrontCamera ? "후면" : "전면") { camera.switchCamera() }
                        Button("IDR") { camera.requestKeyframe() }
                    }
                    .buttonStyle(.borderedProminent)

                    HStack {
                        Text("줌 \(camera.zoom, specifier: "%.1f")x")
                            .frame(width: 90, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(camera.zoom) },
                            set: { camera.setZoom(CGFloat($0)) }
                        ), in: 1...8)
                    }
                    .foregroundStyle(.white)
                }
                .padding(12)
                .background(.black.opacity(0.58))
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}
