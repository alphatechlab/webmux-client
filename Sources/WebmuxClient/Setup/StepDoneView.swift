import SwiftUI
import CoreImage.CIFilterBuiltins

struct StepDoneView: View {
  @Bindable var state: AppState
  @State private var glowPhase = false

  var body: some View {
    VStack(spacing: 12) {
      if state.mode == .running {
        Text("READY")
          .font(.system(size: 28, weight: .black, design: .monospaced))
          .foregroundStyle(
            LinearGradient(colors: [KG.cyan, KG.magenta], startPoint: .leading, endPoint: .trailing)
          )
          .shadow(color: KG.cyan.opacity(glowPhase ? 0.6 : 0.2), radius: glowPhase ? 12 : 4)
          .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
              glowPhase = true
            }
          }

        Text("webmux is running")
          .font(KG.mono)
          .foregroundStyle(KG.green)

        VStack(spacing: 8) {
          let qrURL = state.tailscaleHostname.isEmpty
            ? "https://tailscale.com/download"
            : state.webmuxURL

          Text(state.tailscaleHostname.isEmpty
            ? "Install Tailscale on your phone, then scan again:"
            : "Scan to open webmux on your phone:")
            .font(KG.monoSmall)
            .foregroundStyle(KG.cyan.opacity(0.5))

          if let qrImage = generateQR(for: qrURL) {
            Image(nsImage: qrImage)
              .interpolation(.none)
              .resizable()
              .scaledToFit()
              .frame(width: 140, height: 140)
              .background(Color.white)
              .cornerRadius(6)
          }

          Text(qrURL)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(KG.cyan.opacity(0.4))
            .textSelection(.enabled)
        }

        Button("OPEN BROWSER") {
          state.openInBrowser()
        }
        .buttonStyle(NeonAccentButton())
        .padding(.top, 8)

      } else {
        ProgressView()
          .tint(KG.cyan)
        Text("INITIALIZING...")
          .font(KG.mono)
          .foregroundStyle(KG.cyan)

        Text(state.hasServices ? "Starting services..." : "Creating services...")
          .font(KG.monoSmall)
          .foregroundStyle(KG.cyan.opacity(0.4))
      }

    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private func generateQR(for string: String) -> NSImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let ciImage = filter.outputImage else { return nil }
    let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
  }
}
