import SwiftUI

struct LogWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProfilePrefsKeys.weightUnit) private var unitRaw = WeightUnit.pounds.rawValue

    @State private var valueString: String = ""
    @State private var measuredAt: Date = .now

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .pounds }
    private var parsedValue: Double? { Double(valueString.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0.0", text: $valueString)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                        Picker("Unit", selection: $unitRaw) {
                            ForEach(WeightUnit.allCases) { u in
                                Text(u.label).tag(u.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                }

                Section("When") {
                    DatePicker("Measured at", selection: $measuredAt, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(parsedValue == nil || (parsedValue ?? 0) <= 0)
                }
            }
        }
    }

    private func save() {
        guard let value = parsedValue, value > 0 else { return }
        let kg: Double = unit == .kilograms ? value : value / 2.20462
        WeightLog.shared.log(WeightEntry(measuredAt: measuredAt, kilograms: kg))
        dismiss()
    }
}
