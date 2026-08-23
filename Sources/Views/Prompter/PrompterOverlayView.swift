import SwiftUI

/// The expanded prompter: smooth pixel-level scrolling driven by speech position.
///
/// Uses NSTextView under the hood for exact word-position mapping.
/// Text scrolls smoothly to keep the current reading position centered.
struct PrompterOverlayView: View {
    let sections: [ScriptSection]
    let scrollPosition: Double
    let totalWords: Int
    let settings: AppSettings
    let slideIndex: Int
    let totalSlides: Int
    let elapsedTime: TimeInterval
    let isListening: Bool
    let isPaused: Bool
    let wordsHeard: Int
    let lastHeardWords: String
    let speechError: String?
    let onCollapse: () -> Void
    let onTogglePause: () -> Void

    private let notchHeight: CGFloat = 32
    private let notchWidth: CGFloat = 180

    var body: some View {
        ZStack(alignment: .top) {
            // Main content
            VStack(spacing: 0) {
                // Space for the notch cutout + ear area
                Spacer()
                    .frame(height: notchHeight)

                // Script area with gradient fade masks
                GeometryReader { geo in
                    PrompterTextView(
                        sections: sections,
                        scrollPosition: scrollPosition,
                        totalWords: totalWords,
                        settings: settings,
                        viewportHeight: geo.size.height,
                        isPaused: isPaused
                    )
                    .mask(
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [.clear, .white], startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 60)
                            Color.white
                            LinearGradient(
                                colors: [.white, .clear], startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 60)
                        }
                    )
                }

                // Status bar
                statusBar
            }

            // Ear controls overlaid at the top, flanking the notch
            earControls
        }
        .background(Color.black)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    // MARK: - Subviews

    /// Controls positioned in the "ears" flanking the notch cutout.
    private var earControls: some View {
        GeometryReader { geo in
            let earWidth = (geo.size.width - notchWidth) / 2

            // Left ear: collapse button + mic dot + slide counter
            HStack(spacing: 8) {
                Spacer()

                Button(action: onCollapse) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))

                        Circle()
                            .fill(
                                isListening && !isPaused
                                    ? CueColors.micActive : Color.gray.opacity(0.5)
                            )
                            .frame(width: 7, height: 7)

                        if totalSlides > 0 {
                            Text("\(slideIndex + 1)/\(totalSlides)")
                                .font(CueFont.mono(11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 12)
            .frame(width: earWidth, height: notchHeight)
            .position(x: earWidth / 2, y: notchHeight / 2)

            // Right ear: pause button
            HStack(spacing: 8) {
                Button(action: onTogglePause) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.leading, 12)
            .frame(width: earWidth, height: notchHeight)
            .position(x: geo.size.width - earWidth / 2, y: notchHeight / 2)
        }
        .frame(height: notchHeight)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if isPaused {
                Text("PAUSED")
                    .font(CueFont.mono(11, weight: .semibold))
                    .foregroundStyle(CueColors.warning)
            } else if let error = speechError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(CueColors.warning)
                    .lineLimit(1)
            } else if !lastHeardWords.isEmpty {
                Text(lastHeardWords)
                    .font(CueFont.mono(11))
                    .foregroundStyle(CueColors.micActive.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            if wordsHeard > 0 {
                Text("\(wordsHeard)w")
                    .font(CueFont.mono(11))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Text(formattedTime(elapsedTime))
                .font(CueFont.mono(12))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func formattedTime(_ seconds: TimeInterval) -> String {
        AppConstants.formatTime(seconds)
    }
}
