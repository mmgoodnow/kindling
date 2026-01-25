import SwiftUI

struct LocalPlaybackView: View {
  @ObservedObject var player: AudioPlayerController
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 24) {
      Text(player.title)
        .font(.title2)
        .multilineTextAlignment(.center)
        .lineLimit(3)

      Slider(
        value: Binding(
          get: { min(player.currentTime, max(player.duration, 0)) },
          set: { player.seek(to: $0) }
        ),
        in: 0...max(player.duration, 1)
      )

      HStack {
        Text(formatTime(player.currentTime))
        Spacer()
        Text(formatTime(player.duration))
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      Button(action: player.togglePlayback) {
        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 52))
      }
      .buttonStyle(.plain)

      Button("Done") {
        dismiss()
      }
    }
    .padding()
    .frame(minWidth: 320, minHeight: 320)
    .onDisappear {
      player.pause()
    }
  }

  private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "--:--" }
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }
}

#Preview {
  LocalPlaybackView(player: AudioPlayerController())
}
