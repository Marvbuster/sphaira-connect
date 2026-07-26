import SwiftUI

/// Collapsible log, monospaced, scrolls to the end automatically.
struct LogConsoleView: View {
    var lines: [AppLogLine]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded.animation(.snappy(duration: 0.3))) {
            console
        } label: {
            Label("Protokoll", systemImage: "terminal")
                .font(Fonts.helper)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .connectCard(radius: 12)
        .accessibilityLabel("Protokoll, \(lines.count) Einträge")
    }

    @ViewBuilder
    private var console: some View {
        if lines.isEmpty {
            Text("Noch keine Einträge.")
                .font(Fonts.mono)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.sm)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                                Text(Self.timestamp(line.date))
                                    .foregroundStyle(.tertiary)
                                Text(line.text)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .font(Fonts.mono)
                            .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
                }
                .frame(height: 150)
                .onChange(of: lines.count) {
                    guard let last = lines.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = lines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
    }
}
