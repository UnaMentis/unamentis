// UnaMentis - QR Code Scanner View
// Camera-based QR code scanning for manual server configuration
//
// Part of UI/Settings

import SwiftUI
import AVFoundation

/// View for scanning QR codes to configure server connection
struct QRCodeScannerView: View {
    let onScanned: (Data) -> Void
    let onManualEntry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = QRCodeScanner()
    @State private var showManualEntry = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview
                QRCodeCameraPreview(scanner: scanner)
                    .ignoresSafeArea()

                // Overlay
                VStack {
                    Spacer()

                    // Scanning frame
                    ScanningFrameView()
                        .frame(width: 250, height: 250)

                    Spacer()

                    // Instructions
                    VStack(spacing: 16) {
                        Text("Scan Server QR Code")
                            .font(.headline)

                        Text("Point your camera at the QR code displayed on your Mac's UnaMentis Server Manager")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Button {
                            onManualEntry()
                            dismiss()
                        } label: {
                            Text("Enter Manually Instead")
                                .font(.subheadline)
                        }
                        .padding(.top, 8)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Enter server address manually")
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                scanner.startScanning()
            }
            .onDisappear {
                scanner.stopScanning()
            }
            .onChange(of: scanner.scannedCode) { _, newValue in
                if let code = newValue, let data = code.data(using: .utf8) {
                    onScanned(data)
                    dismiss()
                }
            }
            .alert("Camera Access Required", isPresented: $scanner.showPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Please allow camera access in Settings to scan QR codes.")
            }
        }
    }
}

// MARK: - Scanning Frame View

struct ScanningFrameView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Corner brackets
            ForEach(0..<4, id: \.self) { index in
                CornerBracket()
                    .rotationEffect(.degrees(Double(index) * 90))
            }

            // Scanning line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .accentColor, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .offset(y: isAnimating ? 100 : -100)
                .animation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true),
                    value: isAnimating
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct CornerBracket: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: -120, y: -100))
            path.addLine(to: CGPoint(x: -120, y: -120))
            path.addLine(to: CGPoint(x: -100, y: -120))
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }
}

// MARK: - QR Code Scanner

@MainActor
class QRCodeScanner: NSObject, ObservableObject {
    @Published var scannedCode: String?
    @Published var showPermissionAlert = false

    let captureSession = AVCaptureSession()
    private var isConfigured = false

    func startScanning() {
        guard !isConfigured else {
            if !captureSession.isRunning {
                let session = captureSession
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
            return
        }

        checkCameraPermission()
    }

    func stopScanning() {
        if captureSession.isRunning {
            let session = captureSession
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.showPermissionAlert = true
                    }
                }
            }
        default:
            showPermissionAlert = true
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }

        captureSession.beginConfiguration()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            captureSession.commitConfiguration()
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            }
        } catch {
            captureSession.commitConfiguration()
            return
        }

        captureSession.commitConfiguration()
        isConfigured = true

        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
}

extension QRCodeScanner: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let stringValue = metadataObject.stringValue else {
            return
        }

        // Validate it looks like UnaMentis server config
        if stringValue.contains("host") && stringValue.contains("port") {
            Task { @MainActor [weak self] in
                self?.scannedCode = stringValue
                self?.stopScanning()
            }
        }
    }
}

// MARK: - Camera Preview

struct QRCodeCameraPreview: UIViewRepresentable {
    let scanner: QRCodeScanner

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: scanner.captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Manual Entry Sheet

struct ManualServerEntrySheet: View {
    let onAdd: (String, Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = "11400"
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Address") {
                    TextField("IP Address or Hostname", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }

                Section("Display Name (Optional)") {
                    TextField("e.g., Living Room Mac", text: $name)
                }

                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Find your Mac's IP address in System Preferences > Network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Manual Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        let portNum = Int(port) ?? 11400
                        onAdd(host, portNum, name.isEmpty ? nil : name)
                        dismiss()
                    }
                    .disabled(host.isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    QRCodeScannerView(
        onScanned: { _ in },
        onManualEntry: {}
    )
}
