import SwiftUI

struct StepCheckView: View {
  @Bindable var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("SYSTEM CHECK")
        .font(KG.monoBig)
        .foregroundStyle(KG.cyan)

      Text("Scanning for required dependencies...")
        .font(KG.monoSmall)
        .foregroundStyle(KG.green.opacity(0.6))

      VStack(spacing: 2) {
        DepRow(name: "Homebrew", detail: "package manager", installed: state.hasHomebrew, required: true)
        DepRow(name: "Node.js", detail: state.nodeVersion.isEmpty ? "javascript runtime" : state.nodeVersion, installed: state.hasNode, required: true)
        DepRow(name: "Rust", detail: state.rustVersion.isEmpty ? "sidecar compiler" : state.rustVersion, installed: state.hasRust, required: true)
        DepRow(name: "Tailscale", detail: state.hasTailscale ? (state.tailscaleHostname.isEmpty ? "connected" : state.tailscaleHostname) : "remote access", installed: state.hasTailscale, required: true)
        DepRow(name: "Python3", detail: "whisper (optional)", installed: state.hasPython, required: false)
        DepRow(name: "ffmpeg", detail: "audio decode (whisper)", installed: state.hasFfmpeg, required: false)

        Rectangle().fill(KG.cyan.opacity(0.15)).frame(height: 1).padding(.vertical, 4)

        DepRow(name: "webmux", detail: state.hasWebmux ? "installed" : "not found", installed: state.hasWebmux, required: true)
        DepRow(name: "Whisper", detail: "voice input (optional)", installed: state.hasWhisper, required: false)
      }
      .padding(10)
      .background(KG.bgCard)
      .neonBorder()

      if !state.hasHomebrew || !state.hasNode || !state.hasRust || !state.hasTailscale {
        HStack(spacing: 6) {
          Text("!")
            .font(KG.mono)
            .foregroundStyle(.black)
            .frame(width: 18, height: 18)
            .background(KG.yellow)
            .cornerRadius(2)
          Text("Missing required deps. Install them first.")
            .font(KG.monoSmall)
            .foregroundStyle(KG.yellow.opacity(0.8))
          Spacer()
          Button("RECHECK") {
            Task { await state.checkDependencies() }
          }
          .buttonStyle(NeonButton(color: KG.yellow))
        }
      }

      Spacer()
    }
    .padding(16)
  }
}

struct DepRow: View {
  let name: String
  let detail: String
  let installed: Bool
  let required: Bool

  var body: some View {
    HStack(spacing: 8) {
      Text(installed ? "[OK]" : "[--]")
        .font(KG.monoSmall)
        .foregroundStyle(installed ? KG.green : required ? KG.pink : KG.cyan.opacity(0.3))

      Text(name)
        .font(KG.mono)
        .foregroundStyle(installed ? KG.green : required ? KG.pink : KG.cyan.opacity(0.5))
        .frame(width: 90, alignment: .leading)

      Text(detail)
        .font(KG.monoSmall)
        .foregroundStyle(KG.cyan.opacity(0.4))

      Spacer()

      if !required {
        Text("OPT")
          .font(.system(size: 8, weight: .bold, design: .monospaced))
          .foregroundStyle(KG.cyan.opacity(0.3))
          .padding(.horizontal, 4)
          .padding(.vertical, 1)
          .overlay(RoundedRectangle(cornerRadius: 2).stroke(KG.cyan.opacity(0.2), lineWidth: 1))
      }
    }
    .padding(.vertical, 3)
  }
}
