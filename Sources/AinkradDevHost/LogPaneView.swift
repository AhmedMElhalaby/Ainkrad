import SwiftUI

/// Renders `LogTail`'s merged line stream — lifecycle events from
/// `DevHostModel` plus the plugin subsystem's real os_log tail — as a
/// scrolling, monospaced list. Kept seamless with the window body per the
/// Cardinal HUD language: a filled background, no separator line above it
/// (the `ValidationBanner` strip above already reads as a distinct region
/// by color, not by a drawn line).
struct LogPaneView: View {
    let logTail: LogTail
    let subsystem: String

    @State private var lines: [String] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
        .task {
            for await line in logTail.stream(subsystem: subsystem) {
                lines.append(line)
            }
        }
    }
}
