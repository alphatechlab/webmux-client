import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
final class AppState {

  // MARK: - Setup state

  enum AppMode { case setup, running }
  enum SetupStep: Int, CaseIterable {
    case check = 0, install, configure, done
    var title: String {
      switch self {
      case .check: "Check"
      case .install: "Install"
      case .configure: "Configure"
      case .done: "Done"
      }
    }
  }

  var mode: AppMode = .setup
  var setupStep: SetupStep = .check

  var hasHomebrew = false
  var hasNode = false
  var hasRust = false
  var hasPython = false
  var hasFfmpeg = false
  var hasTailscale = false
  var hasWebmux = false
  var hasWhisper = false
  var hasServices = false
  var nodeVersion = ""
  var rustVersion = ""
  var tailscaleHostname = ""
  var webmuxVersion = ""

  var installLog = ""
  var isInstalling = false
  var installFailed = false

  var githubDir = ""
  var installWhisperOption = true

  var needsInstall: Bool {
    !hasWebmux || (installWhisperOption && hasPython && !hasWhisper)
  }

  // MARK: - Runtime state

  var webmuxRunning = false
  var whisperRunning = false
  var backendOutdated = false
  var clientOutdated = false
  var latestClientVersion = ""
  var isOutdated: Bool { backendOutdated || clientOutdated }
  var isWorking = false
  var workMessage = ""
  var lastCheckMessage = ""
  var isChecking = false

  var currentClientVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  }

  var allRunning: Bool { webmuxRunning && whisperRunning }
  var anyRunning: Bool { webmuxRunning || whisperRunning }

  private var pollTimer: Timer?
  private var updateTimer: Timer?
  private var didBootstrap = false

  // MARK: - Init

  func bootstrap() async {
    guard !didBootstrap else {
      await checkDependencies()
      return
    }
    didBootstrap = true

    await checkDependencies()

    let ready = hasWebmux && hasServices
    mode = ready ? .running : .setup

    if mode == .running {
      await ServiceManager.startAll()
      try? await Task.sleep(for: .seconds(2))
      refreshServices()
      startPolling()
      // Auto-check for updates now + every 6h
      Task { await checkForUpdates() }
      startUpdatePolling()
    }

    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated {
        self.pollTimer?.invalidate()
        ServiceManager.stopAllSync()
      }
    }
  }

  // MARK: - Dependency checks

  func checkDependencies() async {
    // FileManager checks (instant, no shell)
    hasHomebrew = BrewManager.isBrewInstalled()
    hasWhisper = BrewManager.isWhisperInstalled()
    hasServices = ServiceManager.allPlistsExist()

    // Shell checks (run off main thread via Shell.runAsync)
    let nodeR = await Shell.runAsync("which node", login: true)
    hasNode = nodeR.exitCode == 0

    let rustR = await Shell.runAsync("which rustc", login: true)
    hasRust = rustR.exitCode == 0

    let pythonR = await Shell.runAsync("which python3", login: true)
    hasPython = pythonR.exitCode == 0

    let ffmpegR = await Shell.runAsync("which ffmpeg", login: true)
    hasFfmpeg = ffmpegR.exitCode == 0

    let tsR = await Shell.runAsync("/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json 2>/dev/null")
    hasTailscale = tsR.exitCode == 0
    if hasTailscale {
      let json = tsR.output
      if let selfRange = json.range(of: "\"Self\""),
         let dnsRange = json[selfRange.upperBound...].range(of: "\"DNSName\""),
         let colonQuote = json[dnsRange.upperBound...].range(of: "\""),
         let endQuote = json[colonQuote.upperBound...].firstIndex(of: "\"") {
        var raw = String(json[colonQuote.upperBound..<endQuote])
        if raw.hasSuffix(".") { raw = String(raw.dropLast()) }
        tailscaleHostname = raw
      }
    }

    let brewPrefix = BrewManager.brewPrefix()
    let brewInstalled = FileManager.default.fileExists(atPath: "\(brewPrefix)/Cellar/webmux")
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let manualInstalled = FileManager.default.fileExists(atPath: "\(home)/GitHub/webmux/dist/server/index.js")
    hasWebmux = brewInstalled || manualInstalled

    if hasNode {
      let nv = await Shell.runAsync("node --version", login: true)
      nodeVersion = nv.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if hasRust {
      let rv = await Shell.runAsync("rustc --version", login: true)
      rustVersion = rv.output.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "rustc ", with: "")
    }

    if githubDir.isEmpty {
      let defaultDir = "\(home)/GitHub"
      if FileManager.default.fileExists(atPath: defaultDir) {
        githubDir = defaultDir
      }
    }
  }

  func checkVersions() async {
    if hasWebmux {
      let r = await Shell.runAsync("\(BrewManager.brewPrefix())/bin/brew info \(BrewManager.formulaName) --json=v2 2>/dev/null")
      if r.exitCode == 0, let range = r.output.range(of: "\"stable\":\""),
         let end = r.output[range.upperBound...].firstIndex(of: "\"") {
        webmuxVersion = "v" + String(r.output[range.upperBound..<end])
      }
      backendOutdated = await BrewManager.checkOutdated()
    }
  }

  // MARK: - Install flow

  func runInstall() async {
    isInstalling = true
    installFailed = false
    installLog = ""

    // --- Homebrew ---
    if !hasHomebrew {
      appendLog("Installing Homebrew...\n")
      let r = await BrewManager.installBrew()
      if r.exitCode != 0 {
        appendLog("Homebrew installation failed.\n\(r.output)\n")
        installFailed = true
        isInstalling = false
        return
      }
      hasHomebrew = true
    }

    // --- Webmux ---
    if !hasWebmux {
      appendLog("Installing webmux via Homebrew...\n")
      appendLog("$ brew tap \(BrewManager.tapName) && brew install \(BrewManager.formulaName)\n\n")

      let code = await BrewManager.tapAndInstall { [weak self] line in
        Task { @MainActor [weak self] in
          self?.appendLog(line)
        }
      }

      if code != 0 {
        appendLog("\nInstallation failed (exit \(code)).\n")
        installFailed = true
        isInstalling = false
        return
      }

      hasWebmux = true
      appendLog("\nWebmux installed successfully!\n")
    }

    // --- Whisper ---
    if installWhisperOption && hasPython && !hasWhisper {
      appendLog("\nInstalling Whisper...\n")
      let wCode = await BrewManager.installWhisper { [weak self] line in
        Task { @MainActor [weak self] in
          self?.appendLog(line)
        }
      }
      if wCode == 0 {
        hasWhisper = true
        appendLog("Whisper installed!\n")
      } else {
        appendLog("Whisper installation failed (non-critical).\n")
      }
    }

    isInstalling = false
  }

  private func appendLog(_ text: String) {
    installLog += text
  }

  // MARK: - Configure & finish

  func finishSetup() async {
    let configPath = BrewManager.configPath()
    if !FileManager.default.fileExists(atPath: configPath) {
      let config = """
        module.exports = {
          githubDir: '\(githubDir)',
          whisper: {
            primary: { url: 'http://localhost:8000/transcribe', label: 'Local' },
            secondary: { url: '', label: '' },
          },
          terminal: {
            fontSize: 20,
            fontFamily: 'Menlo, monospace',
            scrollback: 10000,
            cursorBlink: false,
            theme: { background: '#15191F', foreground: '#e0e0e0', cursor: '#e0e0e0', selectionBackground: '#0f346080' },
          },
          projects: {},
        };
        """
      try? config.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    // Generate Tailscale HTTPS certificate if available
    if hasTailscale && !tailscaleHostname.isEmpty {
      let certsDir = BrewManager.libexecDir() + "/certs"
      let certFile = certsDir + "/tailscale.crt"
      let keyFile = certsDir + "/tailscale.key"
      if !FileManager.default.fileExists(atPath: certFile) {
        _ = await Shell.runAsync("mkdir -p '\(certsDir)' && /Applications/Tailscale.app/Contents/MacOS/Tailscale cert --cert-file '\(certFile)' --key-file '\(keyFile)' '\(tailscaleHostname)' 2>&1")
      }
    }

    let whisperDir = installWhisperOption && hasWhisper ? BrewManager.whisperDir : nil
    await ServiceManager.createPlists(
      webmuxBinary: BrewManager.webmuxBinary(),
      whisperDir: whisperDir
    )
    hasServices = true

    await ServiceManager.startAll()
    try? await Task.sleep(for: .seconds(2))
    refreshServices()

    mode = .running
    startPolling()
  }

  // MARK: - Runtime

  func refreshServices() {
    Task {
      let uid = "\(getuid())"
      let wR = await Shell.runAsync("launchctl print gui/\(uid)/\(ServiceLabel.webmux.rawValue) 2>/dev/null")
      let whR = await Shell.runAsync("launchctl print gui/\(uid)/\(ServiceLabel.whisper.rawValue) 2>/dev/null")
      webmuxRunning = parsePid(wR.output)
      whisperRunning = parsePid(whR.output)
    }
  }

  private func parsePid(_ output: String) -> Bool {
    for line in output.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("pid = ") {
        let pidStr = trimmed.replacingOccurrences(of: "pid = ", with: "")
        return (Int(pidStr) ?? 0) > 0
      }
    }
    return false
  }

  private func startPolling() {
    pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.refreshServices()
      }
    }
  }

  private func startUpdatePolling() {
    let sixHours: TimeInterval = 6 * 60 * 60
    updateTimer = Timer.scheduledTimer(withTimeInterval: sixHours, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        await self?.checkForUpdates()
      }
    }
  }

  func startService(_ service: ServiceLabel) async {
    setRunning(service, true)
    await ServiceManager.start(service)
    try? await Task.sleep(for: .seconds(1))
    refreshServices()
  }

  func stopService(_ service: ServiceLabel) async {
    setRunning(service, false)
    await ServiceManager.stop(service)
    try? await Task.sleep(for: .seconds(1))
    refreshServices()
  }

  func restartService(_ service: ServiceLabel) async {
    await ServiceManager.restart(service)
    try? await Task.sleep(for: .seconds(2))
    refreshServices()
  }

  func startAll() async {
    await ServiceManager.startAll()
    try? await Task.sleep(for: .seconds(2))
    refreshServices()
  }

  func stopAll() async {
    await ServiceManager.stopAll()
    try? await Task.sleep(for: .seconds(1))
    refreshServices()
  }

  func isRunning(_ service: ServiceLabel) -> Bool {
    switch service {
    case .webmux: webmuxRunning
    case .whisper: whisperRunning
    }
  }

  private func setRunning(_ service: ServiceLabel, _ value: Bool) {
    switch service {
    case .webmux: webmuxRunning = value
    case .whisper: whisperRunning = value
    }
  }

  // MARK: - Updates

  func checkForUpdates() async {
    isChecking = true
    lastCheckMessage = ""

    // Check backend (brew)
    backendOutdated = await BrewManager.checkOutdated()

    // Check client (GitHub API)
    clientOutdated = false
    let apiUrl = "https://api.github.com/repos/alphatechlab/webmux-client/releases/latest"
    let r = await Shell.runAsync("curl -sf '\(apiUrl)' 2>/dev/null")
    if r.exitCode == 0 {
      // Parse tag_name from JSON
      if let range = r.output.range(of: "\"tag_name\":\""),
         let end = r.output[range.upperBound...].firstIndex(of: "\"") {
        let remote = String(r.output[range.upperBound..<end]).replacingOccurrences(of: "v", with: "")
        latestClientVersion = remote
        clientOutdated = remote != currentClientVersion && remote > currentClientVersion
      }
    }

    lastCheckMessage = isOutdated ? "" : "Up to date"
    isChecking = false
  }

  var updateSummary: String {
    if backendOutdated && clientOutdated { return "SERVER+APP" }
    if backendOutdated { return "SERVER" }
    if clientOutdated { return "APP" }
    return ""
  }

  func runUpdate() async {
    isWorking = true

    if backendOutdated {
      workMessage = "Stopping services..."
      await ServiceManager.stopAll()

      workMessage = "Upgrading server..."
      let code = await BrewManager.upgrade { [weak self] line in
        Task { @MainActor [weak self] in
          self?.workMessage = String(line.prefix(80))
        }
      }

      if code != 0 {
        workMessage = "Server upgrade failed"
        try? await Task.sleep(for: .seconds(3))
      } else {
        backendOutdated = false
        workMessage = "Restarting services..."
        await ServiceManager.startAll()
      }
    }

    if clientOutdated {
      workMessage = "Downloading client v\(latestClientVersion)..."
      let tag = "v\(latestClientVersion)"
      let downloadUrl = "https://github.com/alphatechlab/webmux-client/releases/download/\(tag)/Webmux.app.tar.gz"
      let tmpDir = "/tmp/webmux-client-update"
      let cmd = """
        rm -rf '\(tmpDir)' && mkdir -p '\(tmpDir)' && \
        curl -fSL '\(downloadUrl)' -o '\(tmpDir)/Webmux.app.tar.gz' && \
        tar -xzf '\(tmpDir)/Webmux.app.tar.gz' -C '\(tmpDir)' && \
        cp -r '\(tmpDir)/Webmux.app' /Applications/ && \
        rm -rf '\(tmpDir)'
        """
      let r = await Shell.runAsync(cmd, login: true)
      if r.exitCode == 0 {
        clientOutdated = false
        workMessage = "App updated! Restart to apply."
        try? await Task.sleep(for: .seconds(3))
      } else {
        workMessage = "Client download failed"
        try? await Task.sleep(for: .seconds(3))
      }
    }

    if !backendOutdated && !clientOutdated {
      workMessage = "All updated!"
      try? await Task.sleep(for: .seconds(1))
    }

    isWorking = false
    refreshServices()
  }

  // MARK: - Actions

  var webmuxURL: String {
    tailscaleHostname.isEmpty
      ? "https://localhost:3030"
      : "https://\(tailscaleHostname):3030"
  }

  func openInBrowser() {
    if let url = URL(string: webmuxURL) {
      NSWorkspace.shared.open(url)
    }
  }

  func openLog(_ path: String) {
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
  }
}
