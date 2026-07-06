import SwiftUI

/// The full-screen title strip's left-side status readouts (AIN-109) — the
/// region the system traffic lights vacate once the window goes full-screen.
/// Renders an ordered, extensible list of items (clock, network, battery —
/// skipped when there is none) in the HUD's mono/small-symbol language, so a
/// future item (e.g. CPU/memory) only needs a new `StatusBarItem` case and a
/// branch in `itemView`, not a one-off view.
struct FullScreenStatusBarView: View {
    let monitor: SystemStatusMonitor
    let tokens: DesignTokens

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items) { item in
                itemView(item)
            }
        }
    }

    private var items: [StatusBarItem] {
        let clock = StatusClock.string(from: monitor.now)
        var result: [StatusBarItem] = [
            .clock(time: clock.time, date: clock.date),
            .network(monitor.network),
        ]
        if let battery = monitor.battery {
            result.append(.battery(battery))
        }
        return result
    }

    @ViewBuilder
    private func itemView(_ item: StatusBarItem) -> some View {
        switch item {
        case .clock(let time, let date):
            HStack(spacing: 6) {
                Text(time)
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Text(date)
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
            .font(AinkradFont.mono(11, weight: .medium))
        case .network(let status):
            symbolReadout(status.symbolName, text: status.label)
        case .battery(let info):
            symbolReadout(info.symbolName, text: info.displayText)
        }
    }

    private func symbolReadout(_ symbolName: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 10))
            Text(text)
                .font(AinkradFont.mono(11))
        }
        .foregroundStyle(tokens.foreground.opacity(0.7))
    }
}

/// One entry in the full-screen status bar's ordered item list.
private enum StatusBarItem: Identifiable {
    case clock(time: String, date: String)
    case network(NetworkStatus)
    case battery(BatteryInfo)

    var id: String {
        switch self {
        case .clock: return "clock"
        case .network: return "network"
        case .battery: return "battery"
        }
    }
}
