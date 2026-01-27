//
//  DebugLogView.swift
//  Videographics
//

import SwiftUI
import Combine

struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText: String = ""
    @State private var autoRefresh = true

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Controls
                HStack {
                    Toggle("Auto-refresh", isOn: $autoRefresh)
                        .toggleStyle(.switch)

                    Spacer()

                    Button("Refresh") {
                        refreshLog()
                    }

                    Button("Clear") {
                        ActionLogger.shared.clear()
                        refreshLog()
                    }
                    .foregroundStyle(.red)
                }
                .padding()
                .background(Color(.secondarySystemBackground))

                Divider()

                // Log content
                ScrollView {
                    Text(logText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: logText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .onAppear {
                refreshLog()
            }
            .onReceive(timer) { _ in
                if autoRefresh {
                    refreshLog()
                }
            }
        }
    }

    private func refreshLog() {
        logText = ActionLogger.shared.getFormattedLog(count: 200)
        if logText.isEmpty {
            logText = "(No log entries yet)"
        }
    }
}

#Preview {
    DebugLogView()
}
