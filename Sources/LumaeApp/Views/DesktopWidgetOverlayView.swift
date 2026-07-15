import AppKit
import SwiftUI
import LumaeCore

struct DesktopWidgetOverlayView: View {
    let widgets: [DesktopWidget]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(widgets.filter(\.isEnabled)) { widget in
                    DesktopWidgetContentView(widget: widget)
                        .position(
                            x: proxy.size.width * widget.position.x,
                            y: proxy.size.height * widget.position.y
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct DesktopWidgetContentView: View {
    let widget: DesktopWidget

    var body: some View {
        switch widget.kind {
        case .digitalClock:
            DigitalClockWidgetView(widget: widget)
        case .nowPlaying:
            NowPlayingWidgetView(widget: widget)
        }
    }
}

struct DigitalClockWidgetView: View {
    let widget: DesktopWidget

    var body: some View {
        TimelineView(
            .periodic(
                from: .now,
                by: widget.digitalClock.showsSeconds ? 1 : 30
            )
        ) { context in
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(mainTime(for: context.date))
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .tracking(-1.2)

                if widget.digitalClock.showsSeconds {
                    Text(seconds(for: context.date))
                        .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }

                if !widget.digitalClock.uses24HourTime {
                    Text(period(for: context.date))
                        .font(.system(size: secondaryFontSize * 0.82, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .textCase(.uppercase)
                }
            }
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                if widget.digitalClock.showsBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.10),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: cornerRadius,
                                    style: .continuous
                                )
                            )
                        }
                }
            }
            .overlay {
                if widget.digitalClock.showsBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
            }
        }
    }

    private var fontSize: CGFloat {
        switch widget.size {
        case .small: return 34
        case .medium: return 50
        case .large: return 72
        }
    }

    private var secondaryFontSize: CGFloat {
        switch widget.size {
        case .small: return 16
        case .medium: return 21
        case .large: return 29
        }
    }

    private var horizontalPadding: CGFloat {
        switch widget.size {
        case .small: return 17
        case .medium: return 22
        case .large: return 28
        }
    }

    private var verticalPadding: CGFloat {
        switch widget.size {
        case .small: return 10
        case .medium: return 13
        case .large: return 17
        }
    }

    private var cornerRadius: CGFloat {
        switch widget.size {
        case .small: return 16
        case .medium: return 20
        case .large: return 25
        }
    }

    private func mainTime(for date: Date) -> String {
        formatted(date, format: widget.digitalClock.uses24HourTime ? "HH:mm" : "h:mm")
    }

    private func seconds(for date: Date) -> String {
        formatted(date, format: "ss")
    }

    private func period(for date: Date) -> String {
        formatted(date, format: "a")
    }

    private func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

struct NowPlayingWidgetView: View {
    let widget: DesktopWidget

    @ObservedObject private var service = NowPlayingService.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
            let snapshot = service.snapshot
            let elapsed = snapshot.elapsed(at: context.date)

            HStack(spacing: artworkGap) {
                artwork(snapshot)

                VStack(alignment: .leading, spacing: contentSpacing) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.hasTrack ? snapshot.title : "Nothing Playing")
                            .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(subtitle(snapshot))
                            .font(.system(size: subtitleSize, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    EqualizerView(
                        isActive: snapshot.hasTrack && snapshot.isPlaying,
                        date: context.date,
                        barCount: barCount
                    )
                    .frame(height: visualizerHeight)

                    VStack(spacing: 5) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.white.opacity(0.16))
                                Capsule()
                                    .fill(.white.opacity(snapshot.hasTrack ? 0.88 : 0.24))
                                    .frame(
                                        width: proxy.size.width * progress(
                                            elapsed: elapsed,
                                            duration: snapshot.duration
                                        )
                                    )
                            }
                        }
                        .frame(height: 3)

                        HStack {
                            Text(timeString(snapshot.hasTrack ? elapsed : 0))
                            Spacer()
                            Text(timeString(snapshot.hasTrack ? snapshot.duration : 0))
                        }
                        .font(.system(size: timeSize, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.56))
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
            }
            .padding(padding)
            .background {
                if widget.nowPlaying.showsBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.09),
                                    .black.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: cornerRadius,
                                    style: .continuous
                                )
                            )
                        }
                }
            }
            .overlay {
                if widget.nowPlaying.showsBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.30), radius: 14, y: 5)
        }
    }

    @ViewBuilder
    private func artwork(_ snapshot: NowPlayingSnapshot) -> some View {
        if let image = snapshot.artwork {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: artworkRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: artworkRadius, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: artworkSize, height: artworkSize)
                .overlay {
                    Image(systemName: snapshot.hasTrack ? "music.note" : "music.note.list")
                        .font(.system(size: artworkIconSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
        }
    }

    private func subtitle(_ snapshot: NowPlayingSnapshot) -> String {
        guard snapshot.hasTrack else { return "Play audio to see it here" }
        if !snapshot.artist.isEmpty { return snapshot.artist }
        if !snapshot.album.isEmpty { return snapshot.album }
        return snapshot.isPlaying ? "Playing" : "Paused"
    }

    private func progress(elapsed: Double, duration: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(elapsed / duration, 0), 1))
    }

    private func timeString(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "0:00" }
        let total = Int(interval.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var artworkSize: CGFloat {
        switch widget.size {
        case .small: return 68
        case .medium: return 92
        case .large: return 122
        }
    }

    private var artworkRadius: CGFloat { artworkSize * 0.16 }
    private var artworkIconSize: CGFloat { artworkSize * 0.30 }

    private var titleSize: CGFloat {
        switch widget.size {
        case .small: return 13
        case .medium: return 16
        case .large: return 20
        }
    }

    private var subtitleSize: CGFloat {
        switch widget.size {
        case .small: return 10
        case .medium: return 12
        case .large: return 14
        }
    }

    private var timeSize: CGFloat {
        switch widget.size {
        case .small: return 8
        case .medium: return 10
        case .large: return 12
        }
    }

    private var contentWidth: CGFloat {
        switch widget.size {
        case .small: return 115
        case .medium: return 165
        case .large: return 225
        }
    }

    private var visualizerHeight: CGFloat {
        switch widget.size {
        case .small: return 18
        case .medium: return 27
        case .large: return 36
        }
    }

    private var contentSpacing: CGFloat {
        switch widget.size {
        case .small: return 7
        case .medium: return 10
        case .large: return 13
        }
    }

    private var artworkGap: CGFloat {
        switch widget.size {
        case .small: return 11
        case .medium: return 14
        case .large: return 18
        }
    }

    private var padding: CGFloat {
        switch widget.size {
        case .small: return 10
        case .medium: return 13
        case .large: return 17
        }
    }

    private var cornerRadius: CGFloat {
        switch widget.size {
        case .small: return 16
        case .medium: return 21
        case .large: return 27
        }
    }

    private var barCount: Int {
        switch widget.size {
        case .small: return 12
        case .medium: return 18
        case .large: return 24
        }
    }
}

private struct EqualizerView: View {
    let isActive: Bool
    let date: Date
    let barCount: Int

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(isActive ? 0.72 : 0.22))
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 2,
                            maxHeight: barHeight(
                                index: index,
                                available: proxy.size.height
                            )
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(index: Int, available: CGFloat) -> CGFloat {
        guard isActive else {
            return max(
                2,
                available * CGFloat(0.15 + Double(index % 3) * 0.04)
            )
        }
        let phase = date.timeIntervalSinceReferenceDate * 4.2
            + Double(index) * 0.72
        let secondary = sin(phase * 0.63 + Double(index) * 0.31)
        let value = 0.24 + abs(sin(phase)) * 0.52 + abs(secondary) * 0.18
        return max(3, available * CGFloat(min(value, 0.96)))
    }
}
