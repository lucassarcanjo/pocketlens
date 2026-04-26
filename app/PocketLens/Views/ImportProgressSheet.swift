import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Modal phase indicator. Shows the four-step pipeline ticker, surfaces
/// the result on completion, and offers a single dismiss button when done.
struct ImportProgressSheet: View {
    @ObservedObject var controller: ImportFlowController
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Importing statement")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                phaseRow("Extracting text",      active: controller.phase == .extractingText)
                phaseRow("Calling Claude",       active: controller.phase == .callingLLM)
                phaseRow("Validating totals",    active: controller.phase == .validating)
                phaseRow("Saving to database",   active: controller.phase == .saving)
            }
            .padding(.vertical, 4)

            Divider()

            Group {
                switch controller.phase {
                case .done(let n):
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Imported \(n) transactions.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if !controller.lastWarnings.isEmpty {
                            DisclosureGroup("Warnings (\(controller.lastWarnings.count))") {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(controller.lastWarnings, id: \.self) { w in
                                        Text("• \(w)").font(.callout)
                                    }
                                }
                            }
                        }
                    }
                case .error(let msg):
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            ScrollView {
                                Text(msg)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                        }
                        Button {
                            #if canImport(AppKit)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(msg, forType: .string)
                            #endif
                        } label: {
                            Label("Copy error", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                default:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(controller.phase.label)
                    }
                }
            }

            HStack {
                Spacer()
                Button(controller.phase.isTerminal ? "Done" : "Working…") {
                    onDone()
                    controller.dismiss()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.phase.isTerminal)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func phaseRow(_ label: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: active ? "circle.dotted" : "circle")
                .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            Text(label)
                .foregroundStyle(active ? .primary : .secondary)
        }
        .font(.callout)
    }
}
