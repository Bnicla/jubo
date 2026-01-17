import SwiftUI

struct WebSearchIndicator: View {
    let state: WebSearchCoordinator.SearchState
    var onConfirmSearch: (() -> Void)? = nil
    var onDeclineSearch: (() -> Void)? = nil

    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()

            case .detectingIntent:
                statusRow(
                    icon: "magnifyingglass",
                    iconColor: .secondary,
                    text: "Analyzing query...",
                    showProgress: true
                )

            case .awaitingConfirmation(let query, let type):
                confirmationView(query: query, type: type)

            case .sanitizing:
                statusRow(
                    icon: "shield",
                    iconColor: .blue,
                    text: "Preparing search...",
                    showProgress: true
                )

            case .searching(let query):
                statusRow(
                    icon: "globe",
                    iconColor: .blue,
                    text: "Searching: \(truncate(query, to: 30))",
                    showProgress: true
                )

            case .fetchingWeather(let location):
                statusRow(
                    icon: "cloud.sun",
                    iconColor: .blue,
                    text: "Getting weather for \(location)...",
                    showProgress: true
                )

            case .fetchingCalendar:
                statusRow(
                    icon: "calendar",
                    iconColor: .blue,
                    text: "Checking calendar...",
                    showProgress: true
                )

            case .fetchingReminders:
                statusRow(
                    icon: "checklist",
                    iconColor: .blue,
                    text: "Getting reminders...",
                    showProgress: true
                )

            case .complete(let count):
                statusRow(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    text: "Found \(count) result\(count == 1 ? "" : "s")",
                    showProgress: false
                )

            case .weatherComplete:
                statusRow(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    text: "Weather data ready",
                    showProgress: false
                )

            case .calendarComplete(let count):
                statusRow(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    text: "\(count) event\(count == 1 ? "" : "s") found",
                    showProgress: false
                )

            case .remindersComplete(let count):
                statusRow(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    text: "\(count) reminder\(count == 1 ? "" : "s") found",
                    showProgress: false
                )

            case .failed(let reason):
                statusRow(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange,
                    text: reason,
                    showProgress: false
                )

            case .skipped(let reason):
                statusRow(
                    icon: "shield.fill",
                    iconColor: .blue,
                    text: reason,
                    showProgress: false
                )
            }
        }
    }

    private func confirmationView(query: String, type: WebSearchCoordinator.ConfirmationType) -> some View {
        let (icon, promptText, buttonText) = confirmationContent(for: type, query: query)

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.caption)

                Text(promptText)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    onConfirmSearch?()
                } label: {
                    Label(buttonText, systemImage: icon)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onDeclineSearch?()
                } label: {
                    Label("Answer Offline", systemImage: "iphone")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    private func confirmationContent(
        for type: WebSearchCoordinator.ConfirmationType,
        query: String
    ) -> (icon: String, prompt: String, button: String) {
        switch type {
        case .webSearch:
            return ("globe", "Search web for: \(truncate(query, to: 35))?", "Search Web")
        case .weather:
            return ("cloud.sun", "Get weather for \(query.capitalized)?", "Get Weather")
        case .calendar:
            return ("calendar", "Check calendar for \(query)?", "Check Calendar")
        case .reminders:
            return ("checklist", "View pending reminders?", "View Reminders")
        }
    }

    private func statusRow(icon: String, iconColor: Color, text: String, showProgress: Bool) -> some View {
        HStack(spacing: 8) {
            if showProgress {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.caption)
            }

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }

    private func truncate(_ text: String, to length: Int) -> String {
        if text.count > length {
            return String(text.prefix(length)) + "..."
        }
        return text
    }
}

// MARK: - Web Search Badge for Messages

struct WebSearchBadge: View {
    let sources: [String]?
    @State private var showingSources = false

    var body: some View {
        Button {
            if sources != nil && !sources!.isEmpty {
                showingSources = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.caption2)
                Text("Web")
                    .font(.caption2)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSources) {
            if let sources = sources {
                SourcesSheet(sources: sources)
            }
        }
    }
}

// MARK: - Sources Sheet

struct SourcesSheet: View {
    let sources: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Sources used for this response") {
                    ForEach(sources, id: \.self) { source in
                        if let url = URL(string: source) {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url.host ?? source)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(source)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        } else {
                            Text(source)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    VStack(spacing: 20) {
        WebSearchIndicator(state: .idle)
        WebSearchIndicator(state: .detectingIntent)
        WebSearchIndicator(state: .sanitizing)
        WebSearchIndicator(state: .searching(query: "latest news about AI"))
        WebSearchIndicator(state: .complete(resultCount: 3))
        WebSearchIndicator(state: .failed(reason: "Network unavailable"))
        WebSearchIndicator(state: .skipped(reason: "Contains personal info"))

        Divider()

        WebSearchBadge(sources: ["https://example.com/article1", "https://news.com/story"])
    }
    .padding()
}
