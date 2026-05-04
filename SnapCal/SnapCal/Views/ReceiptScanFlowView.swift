import SwiftUI
import UIKit

// Scanner → OCR → confirm sheet. Owns the flow state so PantryView only
// has to mount this once. The confirm step is mandatory (parity with the
// barcode flow) — nothing lands in the pantry without an explicit "Add
// X items" tap.
struct ReceiptScanFlowView: View {
    enum Phase: Equatable {
        case scanning
        case processing
        case confirming([ReceiptItemClassifier.Candidate])
        case empty
        case failed(String)
    }

    let onClose: () -> Void

    @State private var phase: Phase = .scanning

    var body: some View {
        Group {
            switch phase {
            case .scanning:
                DocumentScannerView(
                    onScanned: handleScanned,
                    onCancel: onClose,
                    onError: { phase = .failed($0) }
                )
                .ignoresSafeArea()
            case .processing:
                ProcessingView()
            case .confirming(let candidates):
                CandidateReviewView(
                    candidates: candidates,
                    onClose: onClose,
                    onSave: saveSelected
                )
            case .empty:
                MessageView(
                    icon: "doc.text.magnifyingglass",
                    title: "Couldn't read any items",
                    message: "Try moving to a better light or framing just the items list.",
                    primary: ("Try again", { phase = .scanning }),
                    secondary: ("Close", onClose)
                )
            case .failed(let message):
                MessageView(
                    icon: "exclamationmark.triangle.fill",
                    title: "Scanner trouble",
                    message: message,
                    primary: ("Try again", { phase = .scanning }),
                    secondary: ("Close", onClose)
                )
            }
        }
    }

    private func handleScanned(_ images: [UIImage]) {
        phase = .processing
        Task {
            do {
                let candidates = try await parseCandidates(from: images)
                await MainActor.run {
                    phase = candidates.isEmpty ? .empty : .confirming(candidates)
                }
            } catch {
                await MainActor.run {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // Pipeline:
    //   1. Veryfi (if configured) → clean line items with totals
    //      OR on-device OCR + heuristic classifier as fallback
    //   2. Gemini normalization pass → expand store-brand abbreviations,
    //      assign categories, drop non-food lines (paper towels, gift
    //      cards, etc.). Skipped if Gemini key is missing or the call
    //      fails — partial-quality data is still better than nothing.
    private func parseCandidates(from images: [UIImage]) async throws -> [ReceiptItemClassifier.Candidate] {
        let parsed: [ReceiptItemClassifier.Candidate]
        if VeryfiConfig.isConfigured, let first = images.first {
            parsed = try await VeryfiReceiptService.parseReceipt(image: first)
        } else {
            let lines = try await ReceiptOCRService.recognizeLines(in: images)
            parsed = ReceiptItemClassifier.classify(lines: lines)
        }

        do {
            return try await GeminiReceiptNormalizer.normalize(candidates: parsed)
        } catch {
            print("[Receipt] Gemini normalization skipped: \(error.localizedDescription)")
            return parsed
        }
    }

    private func saveSelected(_ updated: [ReceiptItemClassifier.Candidate]) {
        for candidate in updated where candidate.include {
            let item = PantryItem(
                name: candidate.name,
                quantity: candidate.quantity,
                unit: candidate.unit,
                category: candidate.category,
                expirationDate: candidate.suggestedExpiration
            )
            PantryStore.shared.add(item)
        }
        onClose()
    }
}

// MARK: - Processing splash

private struct ProcessingView: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Reading your receipt…")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text(subline)
                .font(SCTheme.Type_.caption())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var subline: String {
        if VeryfiConfig.isConfigured {
            return "Parsing line items — this can take a few seconds."
        }
        return "On-device OCR — nothing leaves your phone."
    }
}

// MARK: - Generic message screen (empty / failure)

private struct MessageView: View {
    let icon: String
    let title: String
    let message: String
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(SCTheme.Colors.accentPink)
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text(message)
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            VStack(spacing: 8) {
                Button {
                    primary.1()
                } label: {
                    Text(primary.0)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(SCTheme.Gradients.cta, in: Capsule())
                }
                if let secondary {
                    Button(secondary.0, action: secondary.1)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

// MARK: - Candidate review

private struct CandidateReviewView: View {
    @State var candidates: [ReceiptItemClassifier.Candidate]
    let onClose: () -> Void
    let onSave: ([ReceiptItemClassifier.Candidate]) -> Void

    private var includedCount: Int {
        candidates.filter(\.include).count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tap a row to edit. Toggle off anything you don't want in your pantry.")
                        .font(SCTheme.Type_.caption())
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach($candidates) { $candidate in
                        NavigationLink {
                            EditCandidateView(candidate: $candidate)
                        } label: {
                            CandidateRow(candidate: $candidate)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review \(candidates.count) item\(candidates.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add \(includedCount)") { onSave(candidates) }
                        .fontWeight(.semibold)
                        .disabled(includedCount == 0)
                }
            }
        }
    }
}

private struct CandidateRow: View {
    @Binding var candidate: ReceiptItemClassifier.Candidate

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: $candidate.include)
                .labelsHidden()
                .tint(SCTheme.Colors.accentPink)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(candidate.category.label, systemImage: candidate.category.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(expirationLabel)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentOrange)
                }
            }
        }
        .opacity(candidate.include ? 1 : 0.45)
    }

    private var expirationLabel: String {
        let days = Calendar.current.dateComponents([.day], from: .now, to: candidate.suggestedExpiration).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "1 day" }
        return "\(days) days"
    }
}

private struct EditCandidateView: View {
    @Binding var candidate: ReceiptItemClassifier.Candidate
    @State private var quantityString: String

    init(candidate: Binding<ReceiptItemClassifier.Candidate>) {
        _candidate = candidate
        _quantityString = State(initialValue: Self.formatted(candidate.wrappedValue.quantity))
    }

    var body: some View {
        Form {
            Section("Item") {
                TextField("Name", text: $candidate.name)
                    .textInputAutocapitalization(.words)
                Picker("Category", selection: $candidate.category) {
                    ForEach(PantryCategory.allCases) { cat in
                        Label(cat.label, systemImage: cat.systemImage).tag(cat)
                    }
                }
            }

            Section("Quantity") {
                HStack {
                    TextField("1", text: $quantityString)
                        .keyboardType(.decimalPad)
                        .onChange(of: quantityString) { _, new in
                            if let value = Double(new), value > 0 { candidate.quantity = value }
                        }
                    Picker("Unit", selection: $candidate.unit) {
                        ForEach(PantryUnit.allCases) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 100)
                }
            }

            Section("Expires") {
                DatePicker("Date", selection: $candidate.suggestedExpiration, displayedComponents: [.date])
            }

            Section {
                Text("Original: \(candidate.rawLine)")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Edit item")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func formatted(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}
