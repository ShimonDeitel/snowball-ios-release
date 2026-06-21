import SwiftUI

/// Add a new debt, or edit an existing one when `editing` is passed.
struct AddDebtView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    var editing: Debt?

    @State private var name: String = ""
    @State private var balance: String = ""
    @State private var apr: String = ""
    @State private var minPayment: String = ""

    private var balanceValue: Double { Double(balance) ?? 0 }
    private var aprValue: Double { Double(apr) ?? 0 }
    private var minValue: Double { Double(minPayment) ?? 0 }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && balanceValue > 0 && minValue > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Debt") {
                    TextField("Name (e.g. Visa, Car loan)", text: $name)
                        .accessibilityIdentifier("field-name")
                }
                Section {
                    numberRow(title: "Balance", systemImage: "dollarsign.circle",
                              text: $balance, id: "field-balance")
                    numberRow(title: "APR %", systemImage: "percent",
                              text: $apr, id: "field-apr")
                    numberRow(title: "Min payment", systemImage: "calendar",
                              text: $minPayment, id: "field-min")
                } header: {
                    Text("Numbers")
                } footer: {
                    Text("APR is the annual interest rate on your statement. Minimum payment is what's due each month.")
                }
            }
            .navigationTitle(editing == nil ? "Add Debt" : "Edit Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                        .accessibilityIdentifier("save-debt")
                }
            }
            .tint(.snowAccent)
            .onAppear(perform: loadEditing)
        }
    }

    private func loadEditing() {
        guard let d = editing else { return }
        name = d.name
        balance = trimmed(d.balance)
        apr = trimmed(d.apr)
        minPayment = trimmed(d.minPayment)
    }

    private func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

    private func save() {
        if let d = editing {
            appModel.updateDebt(d, name: name, balance: balanceValue, apr: aprValue, minPayment: minValue)
        } else {
            appModel.addDebt(name: name, balance: balanceValue, apr: aprValue, minPayment: minValue)
        }
        Haptics.success()
        dismiss()
    }

    /// A labelled numeric field row.
    @ViewBuilder
    private func numberRow(title: String, systemImage: String,
                           text: Binding<String>, id: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
                .accessibilityIdentifier(id)
        }
    }
}
