import SwiftUI

struct HomeView: View {
    var forceScreen: String?

    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store

    @State private var showAddDebt = false
    @State private var showPlan = false
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var selectedDebt: Debt?

    private var plan: PayoffPlan { appModel.currentPlan() }

    var body: some View {
        NavigationStack {
            ZStack {
                SnowBackground()
                if appModel.debts.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Snowball")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.tap(); showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("open-settings")
                    .accessibilityLabel("Settings")
                }
            }
        }
        .tint(.snowAccent)
        .sheet(isPresented: $showAddDebt) { AddDebtView() }
        .sheet(isPresented: $showPlan) { PlanView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $selectedDebt) { debt in DebtDetailView(debt: debt) }
        .onAppear { appModel.refresh(); applyForceScreen() }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                ForEach(appModel.debts) { debt in
                    Button {
                        Haptics.tap(); selectedDebt = debt
                    } label: {
                        DebtRow(debt: debt)
                    }
                    .buttonStyle(.plain)
                }
                planButton
                addButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Total debt").font(.subheadline).foregroundStyle(.secondary)
                Text(Money.string(appModel.totalBalance))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            Divider()
            HStack {
                Label {
                    Text(debtFreeText).font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(Color.snowAccent)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .snowCard()
    }

    private var debtFreeText: String {
        if let date = plan.debtFreeDate {
            return "Debt-free \(monthYear(date))"
        } else if !plan.isFeasible {
            return "Add more per month to finish"
        }
        return "All clear"
    }

    private var planButton: some View {
        Button { Haptics.tap(); showPlan = true } label: {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("View payoff plan")
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .snowCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("open-plan")
    }

    private var addButton: some View {
        Button {
            Haptics.tap()
            if appModel.canAddDebt { showAddDebt = true } else { showPaywall = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appModel.canAddDebt ? "plus.circle.fill" : "lock.fill")
                Text(appModel.canAddDebt ? "Add a debt" : "Unlock unlimited debts")
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .prominentButton()
        .accessibilityIdentifier("add-debt")
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            ProgressRing(progress: 0, size: 140, lineWidth: 14) {
                Image(systemName: "snowflake")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.snowAccent)
            }
            VStack(spacing: 8) {
                Text("Start your snowball").font(.title2.weight(.bold))
                Text("Add your first debt and we'll build a month-by-month plan to pay it all off.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Button { Haptics.tap(); showAddDebt = true } label: {
                Text("Add a debt").frame(maxWidth: 220).padding(.vertical, 4)
            }
            .prominentButton()
            .accessibilityIdentifier("add-debt-empty")
        }
        .padding()
    }

    private func applyForceScreen() {
        guard let s = forceScreen else { return }
        switch s {
        case "add": showAddDebt = true
        case "plan": showPlan = true
        case "settings": showSettings = true
        case "paywall": showPaywall = true
        default: break
        }
    }
}

/// A single debt row with a shrinking ring, balance, and quick details.
struct DebtRow: View {
    let debt: Debt

    var body: some View {
        HStack(spacing: 16) {
            ProgressRing(progress: debt.progress, size: 56, lineWidth: 7) {
                if debt.isPaidOff {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.snowAccent)
                } else {
                    Text("\(Int((debt.progress * 100).rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(debt.name).font(.headline)
                Text("\(Money.string(debt.balance)) · \(aprText) APR")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .snowCard()
    }

    private var aprText: String {
        debt.apr == debt.apr.rounded() ? String(format: "%.0f%%", debt.apr)
                                       : String(format: "%.2f%%", debt.apr)
    }
}
