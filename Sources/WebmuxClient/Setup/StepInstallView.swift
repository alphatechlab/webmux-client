import SwiftUI

struct StepInstallView: View {
  @Bindable var state: AppState
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("INSTALL")
        .font(KG.monoBig)
        .foregroundStyle(KG.cyan)

      Text("Review components to install or update.")
        .font(KG.monoSmall)
        .foregroundStyle(KG.green.opacity(0.6))

      // Component list
      VStack(spacing: 2) {
        componentRow(
          name: "webmux",
          detail: state.hasWebmux ? (state.webmuxVersion.isEmpty ? "installed" : state.webmuxVersion) : "not installed",
          installed: state.hasWebmux,
          outdated: state.backendOutdated
        )

        if state.hasPython {
          HStack(spacing: 8) {
            Toggle("", isOn: $state.installWhisperOption)
              .toggleStyle(NeonToggleStyle())
              .labelsHidden()

            Text("Whisper")
              .font(KG.mono)
              .foregroundStyle(whisperColor)
              .frame(width: 90, alignment: .leading)

            Text(whisperDetail)
              .font(KG.monoSmall)
              .foregroundStyle(KG.cyan.opacity(0.4))

            Spacer()

            Text("OPT")
              .font(.system(size: 8, weight: .bold, design: .monospaced))
              .foregroundStyle(KG.cyan.opacity(0.3))
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .overlay(RoundedRectangle(cornerRadius: 2).stroke(KG.cyan.opacity(0.2), lineWidth: 1))
          }
          .padding(.vertical, 3)
        }
      }
      .padding(10)
      .background(KG.bgCard)
      .neonBorder()

      if !state.needsInstall {
        HStack(spacing: 6) {
          Text("[OK]")
            .font(KG.mono)
            .foregroundStyle(KG.green)
          Text("All components are installed and up to date.")
            .font(KG.monoSmall)
            .foregroundStyle(KG.green.opacity(0.7))
        }
      }

      // Terminal log (only shown during/after install)
      if state.isInstalling || !state.installLog.isEmpty {
        ZStack(alignment: .topTrailing) {
          logArea
          if !state.installLog.isEmpty {
            logActions.padding(6)
          }
        }
        .frame(maxHeight: .infinity)
      } else {
        Spacer()
      }

      // Status bar
      statusBar
    }
    .padding(16)
    .task {
      await state.checkVersions()
    }
  }

  // MARK: - Component row

  private func componentRow(name: String, detail: String, installed: Bool, outdated: Bool) -> some View {
    HStack(spacing: 8) {
      Text(installed ? (outdated ? "[UP]" : "[OK]") : "[--]")
        .font(KG.monoSmall)
        .foregroundStyle(installed ? (outdated ? KG.yellow : KG.green) : KG.pink)

      Text(name)
        .font(KG.mono)
        .foregroundStyle(installed ? (outdated ? KG.yellow : KG.green) : KG.pink)
        .frame(width: 90, alignment: .leading)

      Text(detail + (outdated ? " — update available" : ""))
        .font(KG.monoSmall)
        .foregroundStyle(KG.cyan.opacity(0.4))

      Spacer()
    }
    .padding(.vertical, 3)
  }

  private var whisperColor: Color {
    if !state.installWhisperOption { return KG.cyan.opacity(0.3) }
    return state.hasWhisper ? KG.green : KG.pink
  }

  private var whisperDetail: String {
    if !state.installWhisperOption { return "skipped" }
    return state.hasWhisper ? "installed" : "not installed"
  }

  // MARK: - Log area

  @ViewBuilder
  private var logArea: some View {
    ScrollViewReader { proxy in
      ScrollView {
        Text(state.installLog)
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(KG.green)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .padding(.top, 20)
        Color.clear.frame(height: 1).id("bottom")
      }
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.black)
          .overlay(RoundedRectangle(cornerRadius: 4).stroke(KG.green.opacity(0.3), lineWidth: 1))
      )
      .onChange(of: state.installLog) {
        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
      }
    }
  }

  private var logActions: some View {
    HStack(spacing: 4) {
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.installLog, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
      } label: {
        Text(copied ? "OK" : "CP")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
      }
      .buttonStyle(NeonButton(color: KG.green))
      .help("Copy logs")

      Button {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "webmux-install.log"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
          try? state.installLog.write(to: url, atomically: true, encoding: .utf8)
        }
      } label: {
        Text("SAVE")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
      }
      .buttonStyle(NeonButton(color: KG.green))
      .help("Save logs to file")
    }
  }

  // MARK: - Status bar

  private var statusBar: some View {
    HStack(spacing: 6) {
      if state.isInstalling {
        ProgressView()
          .controlSize(.small)
          .tint(KG.cyan)
        Text("INSTALLING...")
          .font(KG.monoSmall)
          .foregroundStyle(KG.cyan)
      } else if state.installFailed {
        Text("[FAIL]")
          .font(KG.mono)
          .foregroundStyle(KG.pink)
        Text("Installation failed.")
          .font(KG.monoSmall)
          .foregroundStyle(KG.pink.opacity(0.7))
        Spacer()
        Button("RETRY") { Task { await state.runInstall() } }
          .buttonStyle(NeonButton(color: KG.pink))
      }
      Spacer()
    }
  }
}
