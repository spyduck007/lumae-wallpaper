import AppKit
import SwiftUI
import LumaeCore

struct DesktopWidgetHostContent: View {
    let widget: DesktopWidget

    var body: some View {
        DesktopWidgetContentView(widget: widget)
            .environment(\.widgetUsesSharedBackdrop, true)
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
        case .dateCalendar:
            DateCalendarWidgetView(widget: widget)
        case .battery:
            BatteryWidgetView(widget: widget)
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
            HStack(
                alignment: .firstTextBaseline,
                spacing: 7 * layoutScale
            ) {
                Text(mainTime(for: context.date))
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .tracking(-1.2 * layoutScale)

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
            .shadow(
                color: .black.opacity(0.45),
                radius: 10 * layoutScale,
                y: 3 * layoutScale
            )
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .widgetSurface(
                style: widget.style,
                cornerRadius: cornerRadius,
                scale: layoutScale
            )
        }
    }

    private var layoutScale: CGFloat {
        CGFloat(widget.renderingScale)
    }

    private var fontSize: CGFloat {
        switch widget.size {
        case .small: return 34
        case .medium: return 50
        case .large: return 72
        case .custom: return 50 * layoutScale
        }
    }

    private var secondaryFontSize: CGFloat {
        switch widget.size {
        case .small: return 16
        case .medium: return 21
        case .large: return 29
        case .custom: return 21 * layoutScale
        }
    }

    private var horizontalPadding: CGFloat {
        switch widget.size {
        case .small: return 17
        case .medium: return 22
        case .large: return 28
        case .custom: return 22 * layoutScale
        }
    }

    private var verticalPadding: CGFloat {
        switch widget.size {
        case .small: return 10
        case .medium: return 13
        case .large: return 17
        case .custom: return 13 * layoutScale
        }
    }

    private var cornerRadius: CGFloat {
        switch widget.size {
        case .small: return 16
        case .medium: return 20
        case .large: return 25
        case .custom: return 20 * layoutScale
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
        switch format {
        case "HH:mm": return Self.twentyFourHourFormatter.string(from: date)
        case "h:mm": return Self.twelveHourFormatter.string(from: date)
        case "ss": return Self.secondsFormatter.string(from: date)
        case "a": return Self.periodFormatter.string(from: date)
        default: return Self.makeFormatter(format).string(from: date)
        }
    }

    private static let twentyFourHourFormatter = makeFormatter("HH:mm")
    private static let twelveHourFormatter = makeFormatter("h:mm")
    private static let secondsFormatter = makeFormatter("ss")
    private static let periodFormatter = makeFormatter("a")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }
}

struct NowPlayingWidgetView: View {
    let widget: DesktopWidget

    @ObservedObject private var service = NowPlayingService.shared

    var body: some View {
        let snapshot = service.snapshot
        let refreshInterval = snapshot.isPlaying ? 1.0 : 60.0

        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            let elapsed = snapshot.elapsed(at: context.date)

            HStack(spacing: artworkGap) {
                artwork(snapshot)

                VStack(alignment: .leading, spacing: contentSpacing) {
                    VStack(
                        alignment: .leading,
                        spacing: 3 * layoutScale
                    ) {
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
                        barCount: barCount,
                        barSpacing: 2 * layoutScale
                    )
                    .frame(height: visualizerHeight)

                    VStack(spacing: 5 * layoutScale) {
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
                        .frame(height: 3 * layoutScale)

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
            .widgetSurface(
                style: widget.style,
                cornerRadius: cornerRadius,
                scale: layoutScale,
                tint: artworkTintColor
            )
        }
        .onAppear { service.beginObserving() }
        .onDisappear { service.endObserving() }
    }

    private var artworkTintColor: Color? {
        guard widget.nowPlaying.usesArtworkTint,
              let color = service.snapshot.artworkTint else {
            return nil
        }
        return Color(nsColor: color)
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
                .fill(.white.opacity(0.055))
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

    private var layoutScale: CGFloat {
        CGFloat(widget.renderingScale)
    }

    private var artworkSize: CGFloat {
        switch widget.size {
        case .small: return 68
        case .medium: return 92
        case .large: return 122
        case .custom: return 92 * layoutScale
        }
    }

    private var artworkRadius: CGFloat { artworkSize * 0.16 }
    private var artworkIconSize: CGFloat { artworkSize * 0.30 }

    private var titleSize: CGFloat {
        switch widget.size {
        case .small: return 13
        case .medium: return 16
        case .large: return 20
        case .custom: return 16 * layoutScale
        }
    }

    private var subtitleSize: CGFloat {
        switch widget.size {
        case .small: return 10
        case .medium: return 12
        case .large: return 14
        case .custom: return 12 * layoutScale
        }
    }

    private var timeSize: CGFloat {
        switch widget.size {
        case .small: return 8
        case .medium: return 10
        case .large: return 12
        case .custom: return 10 * layoutScale
        }
    }

    private var contentWidth: CGFloat {
        switch widget.size {
        case .small: return 115
        case .medium: return 165
        case .large: return 225
        case .custom: return 165 * layoutScale
        }
    }

    private var visualizerHeight: CGFloat {
        switch widget.size {
        case .small: return 18
        case .medium: return 27
        case .large: return 36
        case .custom: return 27 * layoutScale
        }
    }

    private var contentSpacing: CGFloat {
        switch widget.size {
        case .small: return 7
        case .medium: return 10
        case .large: return 13
        case .custom: return 10 * layoutScale
        }
    }

    private var artworkGap: CGFloat {
        switch widget.size {
        case .small: return 11
        case .medium: return 14
        case .large: return 18
        case .custom: return 14 * layoutScale
        }
    }

    private var padding: CGFloat {
        switch widget.size {
        case .small: return 10
        case .medium: return 13
        case .large: return 17
        case .custom: return 13 * layoutScale
        }
    }

    private var cornerRadius: CGFloat {
        switch widget.size {
        case .small: return 16
        case .medium: return 21
        case .large: return 27
        case .custom: return 21 * layoutScale
        }
    }

    private var barCount: Int {
        switch widget.size {
        case .small: return 12
        case .medium, .custom: return 18
        case .large: return 24
        }
    }
}

private struct EqualizerView: View {
    let isActive: Bool
    let barCount: Int
    let barSpacing: CGFloat

    var body: some View {
        if isActive {
            // 20fps still reads as smooth for a bar equalizer, and in
            // mirrored mode this Canvas redraws independently per display,
            // so the saving multiplies with monitor count.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                equalizerCanvas(date: context.date, isActive: true)
            }
        } else {
            equalizerCanvas(date: .distantPast, isActive: false)
        }
    }

    private func equalizerCanvas(date: Date, isActive: Bool) -> some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            guard barCount > 0, size.width > 0, size.height > 0 else {
                return
            }

            let totalSpacing = barSpacing * CGFloat(max(barCount - 1, 0))
            let barWidth = max(
                (size.width - totalSpacing) / CGFloat(barCount),
                1
            )
            let color = Color.white.opacity(isActive ? 0.72 : 0.22)

            for index in 0..<barCount {
                let height = barHeight(
                    index: index,
                    date: date,
                    available: size.height,
                    isActive: isActive
                )
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + barSpacing),
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let path = Path(
                    roundedRect: rect,
                    cornerRadius: min(barWidth, height) / 2
                )
                context.fill(path, with: .color(color))
            }
        }
    }

    private func barHeight(
        index: Int,
        date: Date,
        available: CGFloat,
        isActive: Bool
    ) -> CGFloat {
        guard isActive else {
            return max(
                2,
                available * CGFloat(0.15 + Double(index % 3) * 0.04)
            )
        }

        let time = date.timeIntervalSinceReferenceDate
        let phase = time * 5.4 + Double(index) * 0.74
        let primary = abs(sin(phase))
        let secondary = abs(sin(time * 3.1 + Double(index) * 1.17))
        let tertiary = abs(cos(time * 2.3 + Double(index) * 0.43))
        let value = 0.16 + primary * 0.48 + secondary * 0.22 + tertiary * 0.10
        return max(3, available * CGFloat(min(value, 0.96)))
    }
}


struct DateCalendarWidgetView: View {
    let widget: DesktopWidget

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Group {
                switch widget.dateCalendar.mode {
                case .compactDate:
                    compactDate(context.date)
                case .fullDate:
                    fullDate(context.date)
                case .monthCalendar:
                    monthCalendar(context.date)
                }
            }
            .foregroundStyle(.white)
            .padding(containerPadding)
            .widgetSurface(
                style: widget.style,
                cornerRadius: cornerRadius,
                scale: layoutScale
            )
        }
    }

    private func compactDate(_ date: Date) -> some View {
        HStack(alignment: .center, spacing: 12 * layoutScale) {
            VStack(alignment: .leading, spacing: 2 * layoutScale) {
                if widget.dateCalendar.showsWeekday {
                    Text(format(date, "EEE").uppercased())
                        .font(.system(
                            size: 10 * layoutScale,
                            weight: .bold,
                            design: .rounded
                        ))
                        .tracking(1.1 * layoutScale)
                        .foregroundStyle(.white.opacity(0.58))
                }

                Text(format(date, "MMM").uppercased())
                    .font(.system(
                        size: 16 * layoutScale,
                        weight: .semibold,
                        design: .rounded
                    ))

                if widget.dateCalendar.showsYear {
                    Text(format(date, "yyyy"))
                        .font(.system(
                            size: 9 * layoutScale,
                            weight: .medium,
                            design: .rounded
                        ))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }

            Text(format(date, "d"))
                .font(.system(
                    size: 46 * layoutScale,
                    weight: .semibold,
                    design: .rounded
                ))
                .monospacedDigit()
        }
        .fixedSize()
    }

    private func fullDate(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2 * layoutScale) {
            if widget.dateCalendar.showsWeekday {
                Text(format(date, "EEEE"))
                    .font(.system(
                        size: 15 * layoutScale,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(.white.opacity(0.62))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8 * layoutScale) {
                Text(format(date, "MMMM"))
                    .font(.system(
                        size: 28 * layoutScale,
                        weight: .medium,
                        design: .rounded
                    ))

                Text(format(date, "d"))
                    .font(.system(
                        size: 34 * layoutScale,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .monospacedDigit()

                if widget.dateCalendar.showsYear {
                    Text(format(date, "yyyy"))
                        .font(.system(
                            size: 14 * layoutScale,
                            weight: .medium,
                            design: .rounded
                        ))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
        .fixedSize()
    }

    private func monthCalendar(_ date: Date) -> some View {
        let calendar = configuredCalendar
        let cells = calendarCells(for: date, calendar: calendar)
        let symbols = weekdaySymbols(calendar: calendar)

        return VStack(alignment: .leading, spacing: 10 * layoutScale) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * layoutScale) {
                Text(format(date, "MMMM"))
                    .font(.system(
                        size: 20 * layoutScale,
                        weight: .semibold,
                        design: .rounded
                    ))

                if widget.dateCalendar.showsYear {
                    Text(format(date, "yyyy"))
                        .font(.system(
                            size: 12 * layoutScale,
                            weight: .medium,
                            design: .rounded
                        ))
                        .foregroundStyle(.white.opacity(0.52))
                }

                Spacer(minLength: 0)

                Text(format(date, "d"))
                    .font(.system(
                        size: 12 * layoutScale,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(width: calendarWidth)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .fixed(calendarCellWidth),
                        spacing: calendarColumnSpacing
                    ),
                    count: 7
                ),
                alignment: .leading,
                spacing: 4 * layoutScale
            ) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.system(
                            size: 8 * layoutScale,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .foregroundStyle(.white.opacity(0.44))
                        .frame(
                            width: calendarCellWidth,
                            height: 16 * layoutScale
                        )
                }

                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    calendarCell(cell, calendar: calendar)
                }
            }
            .frame(width: calendarWidth, alignment: .leading)
        }
        .frame(width: calendarWidth, alignment: .leading)
        .fixedSize()
    }

    private func calendarCell(
        _ cell: CalendarCell,
        calendar: Calendar
    ) -> some View {
        let isToday = cell.date.map { calendar.isDateInToday($0) } ?? false
        return ZStack(alignment: .center) {
            if isToday {
                Circle()
                    .fill(Color.accentColor.opacity(0.92))
                    .frame(
                        width: todayHighlightSize,
                        height: todayHighlightSize
                    )
            }

            Text(cell.date.map { String(calendar.component(.day, from: $0)) } ?? "")
                .font(.system(
                    size: 10 * layoutScale,
                    weight: isToday ? .bold : .medium,
                    design: .rounded
                ))
                .foregroundStyle(
                    cell.isCurrentMonth
                        ? Color.white
                        : Color.white.opacity(0.28)
                )
                .frame(
                    width: todayHighlightSize,
                    height: todayHighlightSize,
                    alignment: .center
                )
        }
        .frame(
            width: calendarCellWidth,
            height: calendarCellHeight,
            alignment: .center
        )
    }

    private var calendarCellWidth: CGFloat { 25 * layoutScale }
    private var calendarCellHeight: CGFloat { 23 * layoutScale }
    private var todayHighlightSize: CGFloat { 19 * layoutScale }
    private var calendarColumnSpacing: CGFloat { 4 * layoutScale }
    private var calendarWidth: CGFloat {
        calendarCellWidth * 7 + calendarColumnSpacing * 6
    }

    private var configuredCalendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        switch widget.dateCalendar.weekStart {
        case .system:
            break
        case .sunday:
            calendar.firstWeekday = 1
        case .monday:
            calendar.firstWeekday = 2
        }
        return calendar
    }

    private func weekdaySymbols(calendar: Calendar) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = calendar
        let localized = formatter.veryShortStandaloneWeekdaySymbols
            ?? formatter.veryShortWeekdaySymbols
            ?? []
        let symbols = localized.isEmpty
            ? ["S", "M", "T", "W", "T", "F", "S"]
            : localized
        let index = min(max(calendar.firstWeekday - 1, 0), symbols.count - 1)
        return Array(symbols[index...]) + Array(symbols[..<index])
    }

    private func calendarCells(
        for date: Date,
        calendar: Calendar
    ) -> [CalendarCell] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              calendar.range(of: .day, in: .month, for: date) != nil else {
            return []
        }

        let firstDay = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstDay)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: firstDay)
            ?? firstDay

        return (0..<42).map { index in
            let cellDate = calendar.date(byAdding: .day, value: index, to: start)
            guard let cellDate else {
                return CalendarCell(date: nil, isCurrentMonth: false)
            }
            let currentMonth = calendar.isDate(
                cellDate,
                equalTo: date,
                toGranularity: .month
            )
            return CalendarCell(
                date: currentMonth || widget.dateCalendar.showsAdjacentMonthDates
                    ? cellDate
                    : nil,
                isCurrentMonth: currentMonth
            )
        }
    }

    private func fullDateText(_ date: Date) -> String {
        let dateFormat = widget.dateCalendar.showsYear
            ? "MMMM d, yyyy"
            : "MMMM d"
        return format(date, dateFormat)
    }

    private func format(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = configuredCalendar
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private var layoutScale: CGFloat {
        let custom = CGFloat(widget.renderingScale)
        switch widget.size {
        case .small: return 0.78
        case .medium: return 1
        case .large: return 1.30
        case .custom: return custom
        }
    }

    private var containerPadding: CGFloat { 15 * layoutScale }
    private var cornerRadius: CGFloat { 20 * layoutScale }
}

private struct CalendarCell {
    var date: Date?
    var isCurrentMonth: Bool
}

struct BatteryWidgetView: View {
    let widget: DesktopWidget

    @ObservedObject private var service = BatteryService.shared

    var body: some View {
        let snapshot = service.snapshot
        HStack(spacing: 13 * layoutScale) {
            batteryIcon(snapshot)

            VStack(alignment: .leading, spacing: 6 * layoutScale) {
                HStack(alignment: .firstTextBaseline, spacing: 7 * layoutScale) {
                    if widget.battery.showsPercentage {
                        Text(snapshot.hasInternalBattery ? "\(snapshot.percentage)%" : "AC Power")
                            .font(.system(
                                size: 25 * layoutScale,
                                weight: .semibold,
                                design: .rounded
                            ))
                            .monospacedDigit()
                    }

                    if snapshot.isCharging && snapshot.hasInternalBattery {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11 * layoutScale, weight: .bold))
                            .foregroundStyle(.yellow.opacity(0.92))
                    }
                }

                if widget.battery.showsStatusText {
                    Text(snapshot.hasInternalBattery
                        ? snapshot.statusText
                        : "No internal battery")
                        .font(.system(
                            size: 11 * layoutScale,
                            weight: .medium,
                            design: .rounded
                        ))
                        .foregroundStyle(.white.opacity(0.60))
                }

                if widget.battery.showsProgressBar {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule()
                                .fill(progressColor(snapshot))
                                .frame(
                                    width: proxy.size.width
                                        * CGFloat(snapshot.hasInternalBattery
                                            ? Double(snapshot.percentage) / 100
                                            : 1)
                                )
                        }
                    }
                    .frame(width: 118 * layoutScale, height: 4 * layoutScale)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14 * layoutScale)
        .widgetSurface(
            style: widget.style,
            cornerRadius: 19 * layoutScale,
            scale: layoutScale
        )
        .onAppear { service.beginObserving() }
        .onDisappear { service.endObserving() }
    }

    private func batteryIcon(_ snapshot: BatterySnapshot) -> some View {
        Image(systemName: batterySymbol(snapshot))
            .font(.system(size: 31 * layoutScale, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(progressColor(snapshot))
            .frame(width: 42 * layoutScale)
    }

    private func batterySymbol(_ snapshot: BatterySnapshot) -> String {
        guard snapshot.hasInternalBattery else { return "powerplug.fill" }
        if snapshot.isCharging { return "battery.100percent" }
        switch snapshot.percentage {
        case 76...100: return "battery.100percent"
        case 51...75: return "battery.75percent"
        case 26...50: return "battery.50percent"
        case 11...25: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func progressColor(_ snapshot: BatterySnapshot) -> Color {
        guard snapshot.hasInternalBattery else { return .white.opacity(0.72) }
        if snapshot.isCharging { return .green.opacity(0.92) }
        if snapshot.percentage <= 20 { return .red.opacity(0.92) }
        return .white.opacity(0.84)
    }

    private var layoutScale: CGFloat {
        let custom = CGFloat(widget.renderingScale)
        switch widget.size {
        case .small: return 0.78
        case .medium: return 1
        case .large: return 1.30
        case .custom: return custom
        }
    }
}
