import SwiftUI

struct DebtDetailView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    let debt: Debt

    @State private var showEdit = false
    @State private var showLogPayment = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                SnowBackground()
                ScrollView {
                    VStack(spacing: 22) {
                        ringCard
                        statsRow
                        logButton
                        if !history.isEmpty { historySection }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(debt.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .tint(.snowAccent)
            .sheet(isPresented: $showEdit) { AddDebtView(editing: debt) }
            .sheet(isPresented: $showLogPayment) { LogPaymentView(debt: debt) }
            .alert("Delete \(debt.name)?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    appModel.deleteDebt(debt); dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the debt and its payment history. This can't be undone.")
            }
        }
    }

    private var history: [Payment] { appModel.payments(for: debt) }

    private var ringCard: some View {
        VStack(spacing: 16) {
            ProgressRing(progress: debt.progress, size: 200, lineWidth: 20) {
                VStack(spacing: 2) {
                    Text("\(Int((debt.progress * 100).rounded()))%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("paid off").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 4) {
                Text(Money.string(debt.balance))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("of \(Money.string(debt.startingBalance)) starting")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if debt.isPaidOff {
                Label("Paid off", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.snowAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .snowCard()
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            MetricTile(value: aprText, label: "APR")
            MetricTile(value: Money.string(debt.minPayment), label: "Min / mo")
            MetricTile(value: Money.string(paidSoFar), label: "Paid so far")
        }
    }

    private var paidSoFar: Double { max(0, debt.startingBalance - debt.balance) }

    private var aprText: String {
        debt.apr == debt.apr.rounded() ? String(format: "%.0f%%", debt.apr)
                                       : String(format: "%.2f%%", debt.apr)
    }

    private var logButton: some View {
        Button {
            Haptics.tap(); showLogPayment = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("Log a payment")
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .prominentButton()
        .disabled(debt.isPaidOff)
        .accessibilityIdentifier("log-payment")
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payment history").font(.headline)
            VStack(spacing: 0) {
                ForEach(history) { p in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.snowAccent)
                        Text(Money.string(p.amount)).font(.body.weight(.medium))
                        Spacer()
                        Text(p.date, style: .date).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    if p.id != history.last?.id { Divider() }
                }
            }
            .snowCard()
        }
    }
}

/// A focused sheet to log a payment amount against a debt.
struct LogPaymentView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    let debt: Debt
    @State private var amount: String = ""

    private var amountValue: Double { Double(amount) ?? 0 }
    private var isValid: Bool { amountValue > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                            .accessibilityIdentifier("payment-amount")
                    }
                } header: {
                    Text("Payment for \(debt.name)")
                } footer: {
                    Text("Current balance \(Money.string(debt.balance)).")
                }
                Section {
                    Button("Pay the minimum (\(Money.string(debt.minPayment)))") {
                        amount = String(format: "%.2f", min(debt.minPayment, debt.balance))
                    }
                    Button("Pay it off (\(Money.string(debt.balance)))") {
                        amount = String(format: "%.2f", debt.balance)
                    }
                }
            }
            .navigationTitle("Log Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        appModel.logPayment(debt, amount: amountValue)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                    .accessibilityIdentifier("save-payment")
                }
            }
            .tint(.snowAccent)
        }
    }
}
