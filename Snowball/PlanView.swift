import SwiftUI

struct PlanView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false
    @State private var showShare = false

    private var plan: PayoffPlan { appModel.plan(for: appModel.strategy) }

    var body: some View {
        NavigationStack {
            ZStack {
                SnowBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        strategyPicker
                        budgetCard
                        if !plan.isFeasible { feasibilityNote }
                        summaryTiles
                        if store.isPro { compareCard } else { compareLocked }
                        milestonesCard
                        scheduleCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Payoff Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if store.isPro { showShare = true } else { showPaywall = true }
                    } label: {
                        Image(systemName: store.isPro ? "square.and.arrow.up" : "lock.fill")
                    }
                    .accessibilityIdentifier("share-plan")
                }
            }
            .tint(.snowAccent)
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showShare) { ShareSheet(items: [shareText]) }
        }
    }

    // MARK: Pieces

    private var strategyPicker: some View {
        HStack(spacing: 12) {
            ForEach(PayoffStrategy.allCases) { s in
                StrategyChip(strategy: s, selected: appModel.strategy == s) {
                    Haptics.tap(); appModel.strategy = s
                }
            }
        }
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Monthly budget").font(.headline)
                Spacer()
                Text(Money.string(appModel.monthlyBudget)).font(.headline)
                    .foregroundStyle(Color.snowAccent)
            }
            HStack {
                Text("Minimums").foregroundStyle(.secondary)
                Spacer()
                Text(Money.string(appModel.totalMinimum)).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Extra per month").font(.subheadline)
                    Spacer()
                    Text(Money.string(appModel.extraMonthly)).font(.subheadline.weight(.semibold))
                }
                Slider(value: Binding(
                    get: { appModel.extraMonthly },
                    set: { appModel.extraMonthly = $0 }
                ), in: 0...1000, step: 10)
                .tint(.snowAccent)
                .accessibilityIdentifier("extra-slider")
            }
        }
        .snowCard()
    }

    private var feasibilityNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.snowAccent)
            Text("Your monthly budget barely covers interest. Add a little extra each month so balances actually shrink.")
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .snowCard()
    }

    private var summaryTiles: some View {
        HStack(spacing: 12) {
            MetricTile(value: debtFree, label: "Debt-free")
            MetricTile(value: monthsText, label: "Months")
            MetricTile(value: Money.whole(plan.totalInterest), label: "Interest")
        }
    }

    private var debtFree: String {
        plan.debtFreeDate.map(monthYear) ?? "—"
    }
    private var monthsText: String {
        plan.monthsToDebtFree > 0 ? "\(plan.monthsToDebtFree)" : "—"
    }

    private var compareCard: some View {
        let snow = appModel.plan(for: .snowball)
        let aval = appModel.plan(for: .avalanche)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Snowball vs Avalanche").font(.headline)
            comparisonRow(title: "Snowball", plan: snow, highlight: appModel.strategy == .snowball)
            Divider()
            comparisonRow(title: "Avalanche", plan: aval, highlight: appModel.strategy == .avalanche)
            if snow.isFeasible && aval.isFeasible {
                let saved = snow.totalInterest - aval.totalInterest
                if abs(saved) >= 1 {
                    Text(saved > 0
                         ? "Avalanche saves \(Money.whole(abs(saved))) in interest."
                         : "Snowball costs \(Money.whole(abs(saved))) less here.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .snowCard()
    }

    private func comparisonRow(title: String, plan: PayoffPlan, highlight: Bool) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(highlight ? .bold : .regular))
                .foregroundStyle(highlight ? Color.snowAccent : .primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(plan.debtFreeDate.map(monthYear) ?? "—")
                    .font(.subheadline.weight(.medium))
                Text("\(Money.whole(plan.totalInterest)) interest")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var compareLocked: some View {
        Button { Haptics.tap(); showPaywall = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill").foregroundStyle(Color.snowAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare Snowball vs Avalanche").font(.subheadline.weight(.semibold))
                    Text("See which saves you the most interest.").font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
            }
            .snowCard()
        }
        .buttonStyle(.plain)
    }

    private var milestonesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Milestones").font(.headline)
            let cleared = clearedMilestones
            if cleared.isEmpty {
                Text("Clear your first debt to earn a badge.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(cleared, id: \.0) { item in
                            MilestoneBadge(title: item.0, systemImage: item.1)
                        }
                    }
                }
            }
        }
        .snowCard()
    }

    /// Milestone badges earned: one per debt fully paid off, plus an all-clear badge.
    private var clearedMilestones: [(String, String)] {
        var out: [(String, String)] = []
        let paidNames = appModel.debts.filter { $0.isPaidOff }.map { $0.name }
        for name in paidNames { out.append((name, "checkmark.seal.fill")) }
        if !appModel.debts.isEmpty && appModel.debts.allSatisfy({ $0.isPaidOff }) {
            out.append(("Debt-free", "flag.checkered"))
        }
        return out
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Month-by-month").font(.headline)
            if plan.months.isEmpty {
                Text("Add a debt to see your schedule.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(plan.months.prefix(24)) { month in
                    HStack {
                        Text(monthYear(month.date)).font(.subheadline.weight(.medium))
                            .frame(width: 88, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pay \(Money.string(month.totalPaid))")
                                .font(.subheadline)
                            if !month.clearedDebtNames.isEmpty {
                                Text("Cleared: \(month.clearedDebtNames.joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(Color.snowAccent)
                            }
                        }
                        Spacer()
                        Text(Money.whole(month.remainingBalance))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    if month.id != plan.months.prefix(24).last?.id { Divider() }
                }
                if plan.months.count > 24 {
                    Text("+ \(plan.months.count - 24) more months")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
        }
        .snowCard()
    }

    private var shareText: String {
        let p = plan
        let date = p.debtFreeDate.map(monthYear) ?? "soon"
        return "I'm paying off \(Money.string(appModel.totalBalance)) of debt with the \(p.strategy.title) method — debt-free by \(date). Tracked with Snowball."
    }
}
