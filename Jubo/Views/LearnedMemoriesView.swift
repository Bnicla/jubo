//
//  LearnedMemoriesView.swift
//  Jubo
//
//  Displays and manages learned user preferences and facts.
//  Allows users to view, delete individual facts, and see interaction patterns.
//

import SwiftUI

struct LearnedMemoriesView: View {
    @ObservedObject private var memory = UserMemory.shared
    @State private var showingResetConfirmation = false

    var body: some View {
        List {
            // Learned Facts Section
            if !memory.facts.isEmpty {
                Section {
                    ForEach(memory.facts) { fact in
                        FactRow(fact: fact)
                    }
                    .onDelete(perform: deleteFacts)
                } header: {
                    Text("Learned Facts")
                } footer: {
                    Text("Swipe left to delete individual facts.")
                }
            } else {
                Section("Learned Facts") {
                    Text("No facts learned yet.")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            // Interaction Patterns Section
            Section {
                PatternRow(
                    label: "Total Interactions",
                    value: "\(memory.patterns.totalInteractions)"
                )

                PatternRow(
                    label: "Average Message Length",
                    value: "\(Int(memory.patterns.avgUserMessageLength)) chars"
                )

                PatternRow(
                    label: "Prefers Concise",
                    value: preferenceText(memory.patterns.prefersConcise)
                )

                PatternRow(
                    label: "Values Accuracy",
                    value: memory.patterns.valuesAccuracy ? "Yes" : "No"
                )

                PatternRow(
                    label: "Corrections Given",
                    value: "\(memory.patterns.correctionsCount)"
                )
            } header: {
                Text("Interaction Patterns")
            } footer: {
                Text("These patterns are derived from your conversations and help adapt responses to your style.")
            }

            // Actions Section
            Section {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset All Learning", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Learned Memories")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset All Learning?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                memory.resetAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear all learned facts and interaction patterns. This action cannot be undone.")
        }
    }

    private func deleteFacts(at offsets: IndexSet) {
        for index in offsets {
            let fact = memory.facts[index]
            memory.removeFact(id: fact.id)
        }
    }

    private func preferenceText(_ preference: Bool?) -> String {
        switch preference {
        case .some(true):
            return "Yes"
        case .some(false):
            return "No (prefers detail)"
        case .none:
            return "Unknown"
        }
    }
}

// MARK: - Supporting Views

struct FactRow: View {
    let fact: UserMemory.MemoryFact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fact.content)
                .font(.body)

            HStack(spacing: 8) {
                // Source badge
                Text(sourceLabel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sourceColor.opacity(0.2))
                    .foregroundColor(sourceColor)
                    .clipShape(Capsule())

                // Confidence
                Text("Conf: \(Int(fact.confidence * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                // Date
                Text(fact.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var sourceLabel: String {
        switch fact.source {
        case .userStated:
            return "Stated"
        case .inferred:
            return "Inferred"
        case .corrected:
            return "Corrected"
        }
    }

    private var sourceColor: Color {
        switch fact.source {
        case .userStated:
            return .blue
        case .inferred:
            return .orange
        case .corrected:
            return .purple
        }
    }
}

struct PatternRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LearnedMemoriesView()
    }
}
