import SwiftUI

struct MenuBarView: View {
  @Bindable var state: AppState
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if state.hasWebmux {
        separator
        servicesSection
        if state.isWorking { progressSection }
        separator
        optionsSection
      } else {
        separator
        notInstalledSection
      }
      separator
      actionsSection
    }
    .padding(10)
    .frame(width: 290)
    .background(KG.bg)
    .task { await state.checkForUpdates() }
  }

  private var separator: some View {
    Rectangle().fill(KG.cyan.opacity(0.15)).frame(height: 1).padding(.vertical, 6)
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 6) {
      Text("WEBMUX")
        .font(KG.monoBig)
        .foregroundStyle(
          LinearGradient(colors: [KG.cyan, KG.magenta], startPoint: .leading, endPoint: .trailing)
        )
      Spacer()
      if state.hasWebmux {
        updateBadge
        startStopBadge
        statusBadge
      }
    }
  }

  @ViewBuilder
  private var updateBadge: some View {
    if state.isOutdated {
      Button(state.updateSummary) { Task { await state.runUpdate() } }
      .font(.system(size: 9, weight: .bold, design: .monospaced))
      .foregroundStyle(KG.yellow)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(KG.yellow.opacity(0.15))
      .overlay(RoundedRectangle(cornerRadius: 3).stroke(KG.yellow.opacity(0.5), lineWidth: 1))
      .cornerRadius(3)
      .buttonStyle(.plain)
    } else if state.isChecking {
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.mini)
          .tint(KG.yellow)
        Text("SCANNING")
          .font(.system(size: 8, weight: .bold, design: .monospaced))
          .foregroundStyle(KG.yellow.opacity(0.7))
      }
    } else if state.isWorking {
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.mini)
          .tint(KG.cyan)
        Text(String(state.workMessage.prefix(12)))
          .font(.system(size: 8, design: .monospaced))
          .foregroundStyle(KG.cyan.opacity(0.5))
      }
    } else {
      Button("OK") { Task { await state.checkForUpdates() } }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(KG.green.opacity(0.5))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(KG.green.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(KG.green.opacity(0.2), lineWidth: 1))
        .cornerRadius(3)
        .buttonStyle(.plain)
        .help("Check for updates")
    }
  }

  private var startStopBadge: some View {
    Button(state.anyRunning ? "STOP" : "START") {
      Task {
        if state.anyRunning { await state.stopAll() }
        else { await state.startAll() }
      }
    }
    .font(.system(size: 9, weight: .bold, design: .monospaced))
    .foregroundStyle(state.anyRunning ? KG.pink : KG.green)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background((state.anyRunning ? KG.pink : KG.green).opacity(0.1))
    .overlay(RoundedRectangle(cornerRadius: 3).stroke((state.anyRunning ? KG.pink : KG.green).opacity(0.4), lineWidth: 1))
    .cornerRadius(3)
    .buttonStyle(.plain)
  }

  private var statusBadge: some View {
    let color = state.allRunning ? KG.green : state.anyRunning ? KG.yellow : KG.pink
    let text = state.allRunning ? "ONLINE" : state.anyRunning ? "PARTIAL" : "OFFLINE"
    return Text(text)
      .font(.system(size: 9, weight: .bold, design: .monospaced))
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.1))
      .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.4), lineWidth: 1))
      .cornerRadius(3)
  }

  private var notInstalledSection: some View {
    VStack(spacing: 8) {
      Text("[--] webmux not installed")
        .font(KG.monoSmall)
        .foregroundStyle(KG.pink.opacity(0.7))
      Button("INSTALL WEBMUX") {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "setup")
      }
      .buttonStyle(NeonAccentButton())
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
  }

  // MARK: - Services

  private var servicesSection: some View {
    VStack(spacing: 4) {
      ServiceRow(
        service: .webmux,
        running: state.webmuxRunning,
        onToggle: { await toggleService(.webmux) },
        onRestart: { await state.restartService(.webmux) }
      )
      ServiceRow(
        service: .whisper,
        running: state.whisperRunning,
        onToggle: { await toggleService(.whisper) },
        onRestart: { await state.restartService(.whisper) }
      )

    }
  }

  private func toggleService(_ service: ServiceLabel) async {
    if state.isRunning(service) {
      await state.stopService(service)
    } else {
      await state.startService(service)
    }
  }



  // MARK: - Options

  private var optionsSection: some View {
    HStack(spacing: 8) {
      Text("Keep awake")
        .font(KG.monoSmall)
        .foregroundStyle(state.caffeinateEnabled ? KG.green : KG.cyan.opacity(0.4))
      Spacer()
      Button {
        state.caffeinateEnabled.toggle()
      } label: {
        Text(state.caffeinateEnabled ? " ON" : "OFF")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(.black)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(state.caffeinateEnabled ? KG.green : KG.pink.opacity(0.6))
          .cornerRadius(3)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 8)
  }

  // MARK: - Progress

  private var progressSection: some View {
    HStack(spacing: 6) {
      ProgressView()
        .controlSize(.small)
        .tint(KG.cyan)
      Text(state.workMessage)
        .font(KG.monoSmall)
        .foregroundStyle(KG.cyan.opacity(0.6))
        .lineLimit(2)
      Spacer()
    }
    .padding(.top, 4)
  }

  // MARK: - Actions

  private var actionsSection: some View {
    HStack(spacing: 6) {
      Button { state.openInBrowser() } label: {
        Text("OPEN")
      }
      .buttonStyle(NeonButton(color: KG.cyan))

      Menu {
        ForEach(ServiceLabel.allCases, id: \.self) { service in
          Section(service.displayName) {
            ForEach(service.logPaths, id: \.self) { path in
              Button((path as NSString).lastPathComponent) {
                state.openLog(path)
              }
            }
          }
        }
      } label: {
        Text("LOGS")
          .font(KG.mono)
          .foregroundStyle(KG.cyan)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(KG.cyan.opacity(0.08))
          .overlay(RoundedRectangle(cornerRadius: 4).stroke(KG.cyan.opacity(0.6), lineWidth: 1))
          .cornerRadius(4)
      }
      .menuStyle(.borderlessButton)

      Spacer()

      Button {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "setup")
      } label: {
        Text("CFG")
      }
      .buttonStyle(NeonButton(color: KG.purple))

      Button {
        NSApp.terminate(nil)
      } label: {
        Text("QUIT")
      }
      .buttonStyle(NeonButton(color: KG.pink))
    }
  }
}

// MARK: - ServiceRow

struct ServiceRow: View {
  let service: ServiceLabel
  let running: Bool
  let onToggle: () async -> Void
  let onRestart: () async -> Void

  var body: some View {
    HStack(spacing: 8) {
      if running {
        Text(">")
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .foregroundStyle(KG.green)
      } else {
        Circle()
          .fill(KG.pink.opacity(0.5))
          .frame(width: 6, height: 6)
      }

      Text(service.displayName)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(running ? KG.green : KG.cyan.opacity(0.5))

      Spacer()

      Button { Task { await onRestart() } } label: {
        Text("RST")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(running ? KG.cyan.opacity(0.6) : KG.cyan.opacity(0.2))
      }
      .buttonStyle(.plain)
      .disabled(!running)
      .help("Restart")

      Button {
        Task { await onToggle() }
      } label: {
        Text(running ? " ON" : "OFF")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(.black)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(running ? KG.green : KG.pink.opacity(0.6))
          .cornerRadius(3)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(Color.black)
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .stroke(running ? KG.green.opacity(0.2) : KG.cyan.opacity(0.1), lineWidth: 1)
        )
    )
  }
}
