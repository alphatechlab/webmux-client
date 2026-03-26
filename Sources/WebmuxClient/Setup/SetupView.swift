import SwiftUI

struct SetupView: View {
  @Bindable var state: AppState
  @Environment(\.dismissWindow) private var dismissWindow
  @State private var isMuted = false

  var body: some View {
    VStack(spacing: 0) {
      // Splash header with mute button
      ZStack(alignment: .topTrailing) {
        splashHeader
        muteButton.padding(8)
      }

      // Scanline separator
      Rectangle().fill(KG.cyan.opacity(0.3)).frame(height: 1)

      // Step indicator
      stepBar
        .padding(.vertical, 8)
        .padding(.horizontal, 16)

      Rectangle().fill(KG.cyan.opacity(0.15)).frame(height: 1)

      // Content
      stepContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      // Footer
      Rectangle().fill(KG.cyan.opacity(0.3)).frame(height: 1)
      footer
    }
    .frame(width: 560, height: 600)
    .background(KG.bg)
    .task {
      KeygenAudio.shared.start()
      await state.bootstrap()
    }
    .onDisappear {
      KeygenAudio.shared.stop()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { n in
      if (n.object as? NSWindow)?.identifier?.rawValue == "setup" {
        if !KeygenAudio.shared.isMuted { KeygenAudio.shared.start() }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { n in
      if (n.object as? NSWindow)?.identifier?.rawValue == "setup" {
        KeygenAudio.shared.stop()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { n in
      if (n.object as? NSWindow)?.identifier?.rawValue == "setup" {
        KeygenAudio.shared.stop()
      }
    }
  }

  // MARK: - Splash

  private var splashHeader: some View {
    ZStack {
      if let img = NSImage(named: "splash") ?? loadBundleImage() {
        Image(nsImage: img)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(height: 140)
          .clipped()
          .overlay(
            LinearGradient(
              colors: [.clear, KG.bg],
              startPoint: .init(x: 0.5, y: 0.7),
              endPoint: .bottom
            )
          )
      } else {
        Rectangle().fill(KG.bg).frame(height: 140)
          .overlay(
            Text("W E B M U X")
              .font(.system(size: 36, weight: .black, design: .monospaced))
              .foregroundStyle(
                LinearGradient(colors: [KG.cyan, KG.magenta], startPoint: .leading, endPoint: .trailing)
              )
          )
      }
    }
    .frame(height: 140)
    .clipped()
    .overlay(alignment: .bottom) {
      Text("Music: \"Unreal Superhero 3\" by REZ / Rebels")
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(KG.cyan.opacity(0.35))
        .padding(.bottom, 4)
    }
  }

  private var muteButton: some View {
    Button {
      KeygenAudio.shared.toggleMute()
      isMuted = KeygenAudio.shared.isMuted
    } label: {
      Text(isMuted ? "MUTE" : "SND")
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(isMuted ? KG.cyan.opacity(0.3) : KG.cyan)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(KG.bg.opacity(0.7))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(isMuted ? KG.cyan.opacity(0.2) : KG.cyan.opacity(0.5), lineWidth: 1))
        .cornerRadius(3)
    }
    .buttonStyle(.plain)
  }

  private func loadBundleImage() -> NSImage? {
    guard let url = Bundle.module.url(forResource: "splash", withExtension: "png"),
          let img = NSImage(contentsOf: url) else { return nil }
    return img
  }

  // MARK: - Steps

  private var stepBar: some View {
    HStack(spacing: 0) {
      ForEach(AppState.SetupStep.allCases, id: \.rawValue) { step in
        HStack(spacing: 4) {
          Text(step.rawValue <= state.setupStep.rawValue ? "[x]" : "[ ]")
            .font(KG.monoSmall)
            .foregroundStyle(step == state.setupStep ? KG.cyan : KG.cyan.opacity(0.4))
          Text(step.title.uppercased())
            .font(KG.monoSmall)
            .foregroundStyle(step == state.setupStep ? KG.cyan : KG.cyan.opacity(0.4))
        }
        if step != AppState.SetupStep.allCases.last {
          Text("---")
            .font(KG.monoSmall)
            .foregroundStyle(KG.cyan.opacity(0.2))
            .padding(.horizontal, 4)
        }
      }
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch state.setupStep {
    case .check:
      StepCheckView(state: state)
    case .install:
      StepInstallView(state: state)
    case .configure:
      StepConfigView(state: state)
    case .done:
      StepDoneView(state: state)
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack {
      if state.setupStep != .check {
        Button("< BACK") {
          withAnimation {
            let raw = state.setupStep.rawValue - 1
            if let prev = AppState.SetupStep(rawValue: raw) {
              state.setupStep = prev
            }
          }
        }
        .buttonStyle(NeonButton())
        .disabled(state.isInstalling)
      }

      Spacer()

      HStack(spacing: 0) {
        Text("Released by ")
          .foregroundStyle(KG.cyan.opacity(0.3))
        Link("Farid Safi", destination: URL(string: "https://github.com/FaridSafi")!)
          .foregroundStyle(KG.cyan.opacity(0.5))
        Text(" & ")
          .foregroundStyle(KG.cyan.opacity(0.3))
        Link("Xavier Colombel", destination: URL(string: "https://github.com/XavierColombel")!)
          .foregroundStyle(KG.cyan.opacity(0.5))
        Text(" - alphatechlab (c) 2026")
          .foregroundStyle(KG.cyan.opacity(0.3))
      }
      .font(.system(size: 8, design: .monospaced))

      Spacer()

      switch state.setupStep {
      case .check:
        Button("CONTINUE >") {
          withAnimation {
            state.setupStep = .install
          }
        }
        .buttonStyle(NeonAccentButton())
        .disabled(!state.hasHomebrew || !state.hasNode || !state.hasRust || !state.hasTailscale)

      case .install:
        if !state.hasWebmux {
          Button("INSTALL") {
            Task { await state.runInstall() }
          }
          .buttonStyle(NeonAccentButton())
          .disabled(state.isInstalling)
        } else {
          Button("CONTINUE >") {
            withAnimation { state.setupStep = .configure }
          }
          .buttonStyle(NeonAccentButton())
        }

      case .configure:
        Button("FINISH") {
          withAnimation { state.setupStep = .done }
          Task { await state.finishSetup() }
        }
        .buttonStyle(NeonAccentButton())
        .disabled(state.githubDir.isEmpty)

      case .done:
        Button("CLOSE") {
          dismissWindow(id: "setup")
        }
        .buttonStyle(NeonAccentButton())
        .disabled(state.mode != .running)
      }
    }
    .padding(12)
    .background(KG.bg)
  }
}

// MARK: - Step Indicator (removed, replaced by stepBar)
