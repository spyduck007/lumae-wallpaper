import SwiftUI
import LumaeCore

struct DesktopWidgetOverlayView: View {
    let widgets: [DesktopWidget]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(widgets.filter(\.isEnabled)) { widget in
                    widgetView(widget)
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

    @ViewBuilder
    private func widgetView(_ widget: DesktopWidget) -> some View {
        switch widget.kind {
        case .digitalClock:
            DigitalClockWidgetView(widget: widget)
        }
    }
}

struct DigitalClockWidgetView: View {
    let widget: DesktopWidget

    var body: some View {
        TimelineView(.periodic(from: .now, by: widget.digitalClock.showsSeconds ? 1 : 30)) { context in
            Text(clockText(for: context.date))
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.42), radius: 8, y: 3)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
    }

    private var fontSize: CGFloat {
        switch widget.size {
        case .small: return 34
        case .medium: return 52
        case .large: return 76
        }
    }

    private var horizontalPadding: CGFloat {
        switch widget.size {
        case .small: return 16
        case .medium: return 22
        case .large: return 28
        }
    }

    private var verticalPadding: CGFloat {
        switch widget.size {
        case .small: return 9
        case .medium: return 12
        case .large: return 15
        }
    }

    private var cornerRadius: CGFloat {
        switch widget.size {
        case .small: return 14
        case .medium: return 18
        case .large: return 22
        }
    }

    private func clockText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }

    private var dateFormat: String {
        let hour = widget.digitalClock.uses24HourTime ? "HH:mm" : "h:mm"
        let seconds = widget.digitalClock.showsSeconds ? ":ss" : ""
        let suffix = widget.digitalClock.uses24HourTime ? "" : " a"
        return hour + seconds + suffix
    }
}
