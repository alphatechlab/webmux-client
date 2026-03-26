import AVFoundation
import Foundation

@MainActor
final class KeygenAudio: @unchecked Sendable {
  static let shared = KeygenAudio()

  private var player: AVAudioPlayer?
  private(set) var isMuted: Bool = UserDefaults.standard.bool(forKey: "audioMuted")

  func start() {
    guard player == nil else { return }
    guard let url = Bundle.module.url(forResource: "keygen", withExtension: "mp3") else { return }
    do {
      player = try AVAudioPlayer(contentsOf: url)
      player?.numberOfLoops = -1 // loop forever
      player?.volume = 0.5
      if !isMuted { player?.play() }
    } catch {
      print("Audio error: \(error)")
    }
  }

  func toggleMute() {
    isMuted.toggle()
    UserDefaults.standard.set(isMuted, forKey: "audioMuted")
    if isMuted {
      player?.pause()
    } else {
      player?.play()
    }
  }

  func stop() {
    player?.stop()
    player = nil
  }
}
