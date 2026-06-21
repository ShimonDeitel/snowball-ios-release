import Foundation
import SwiftData
import SwiftUI

/// App state: owns the SwiftData store for debts & payments, derives the payoff plan from the
/// current debts + monthly budget, and enforces the free-tier debt cap (defense-in-depth).
@MainActor
final class AppModel: ObservableObject {
    let container: ModelContainer
    weak var store: Store?

    static let freeDebtLimit = 2

    @Published private(set) var debts: [Debt] = []
    @Published private(set) var payments: [Payment] = []

    /// Persisted user choices.
    @AppStorage("snowball.strategy") private var strategyRaw = PayoffStrategy.snowball.rawValue
    @AppStorage("snowball.extra") private var extraMonthlyStored: Double = 100

    var strategy: PayoffStrategy {
        get { PayoffStrategy(rawValue: strategyRaw) ?? .snowball }
        set { strategyRaw = newValue.rawValue; objectWillChange.send() }
    }

    /// Extra dollars per month above the combined minimums (the "snowball" amount).
    var extraMonthly: Double {
        get { max(0, extraMonthlyStored) }
        set { extraMonthlyStored = max(0, newValue); objectWillChange.send() }
    }

    init(container: ModelContainer) {
        self.container = container
        #if DEBUG
        seedIfRequested()
        #endif
        refresh()
    }

    // MARK: Container (fully local, on-device persistence — no CloudKit, no sync)

    static func makeContainer() -> ModelContainer {
        let schema = Schema([Debt.self, Payment.self])
        // Local-only on-device store. No CloudKit/sync.
        let local = ModelConfiguration(schema: schema)
        if let c = try? ModelContainer(for: schema, configurations: local) { return c }
        // Safe fallback so the app always launches even if the on-disk store can't be opened.
        let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: mem)
    }

    // MARK: Derived budget & plan

    /// Combined minimum payment across all active debts.
    var totalMinimum: Double { PayoffEngine.totalMinimum(debts.map(\.input)) }

    /// The full monthly budget = minimums + the user's chosen extra.
    var monthlyBudget: Double { totalMinimum + extraMonthly }

    var totalBalance: Double { debts.reduce(0) { $0 + $1.balance } }

    /// The active plan for the user's selected strategy.
    func currentPlan() -> PayoffPlan {
        PayoffEngine.makePlan(debts: debts.map(\.input),
                              monthlyBudget: monthlyBudget,
                              strategy: strategy)
    }

    func plan(for strategy: PayoffStrategy) -> PayoffPlan {
        PayoffEngine.makePlan(debts: debts.map(\.input),
                              monthlyBudget: monthlyBudget,
                              strategy: strategy)
    }

    // MARK: Debts

    var canAddDebt: Bool {
        (store?.isPro ?? false) || debts.count < Self.freeDebtLimit
    }

    @discardableResult
    func addDebt(name: String, balance: Double, apr: Double, minPayment: Double) -> Debt? {
        // Defense-in-depth: never exceed the free cap unless Pro, even past the UI gate.
        guard canAddDebt else { return nil }
        let ctx = container.mainContext
        let debt = Debt(name: name.isEmpty ? "Debt" : name, balance: balance, apr: apr,
                        minPayment: minPayment, startingBalance: balance, order: debts.count)
        ctx.insert(debt)
        try? ctx.save()
        refresh()
        return debt
    }

    func updateDebt(_ debt: Debt, name: String, balance: Double, apr: Double, minPayment: Double) {
        debt.name = name.isEmpty ? "Debt" : name
        debt.apr = max(0, apr)
        debt.minPayment = max(0, minPayment)
        // Keep startingBalance as the high-water mark so the ring stays meaningful.
        debt.startingBalance = max(debt.startingBalance, max(0, balance))
        debt.balance = max(0, balance)
        try? container.mainContext.save()
        refresh()
    }

    func deleteDebt(_ debt: Debt) {
        let ctx = container.mainContext
        let id = debt.id
        ctx.delete(debt)
        // Also remove its payment history.
        for p in payments where p.debtID == id { ctx.delete(p) }
        try? ctx.save()
        refresh()
    }

    // MARK: Payments

    /// Log a payment against a debt: reduce the balance and record the entry.
    func logPayment(_ debt: Debt, amount: Double) {
        let amt = max(0, min(amount, debt.balance))
        guard amt > 0 else { return }
        let ctx = container.mainContext
        debt.balance = max(0, debt.balance - amt)
        ctx.insert(Payment(debtID: debt.id, debtName: debt.name, amount: amt))
        try? ctx.save()
        Haptics.success()
        refresh()
    }

    func payments(for debt: Debt) -> [Payment] {
        payments.filter { $0.debtID == debt.id }.sorted { $0.date > $1.date }
    }

    var totalPaidAllTime: Double { payments.reduce(0) { $0 + $1.amount } }

    // MARK: Refresh

    func refresh() {
        let ctx = container.mainContext
        debts = ((try? ctx.fetch(FetchDescriptor<Debt>())) ?? [])
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
        payments = (try? ctx.fetch(FetchDescriptor<Payment>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        objectWillChange.send()
    }

    /// Erase all on-device data (used by Delete Account).
    func deleteAllData() {
        let ctx = container.mainContext
        try? ctx.delete(model: Payment.self)
        try? ctx.delete(model: Debt.self)
        try? ctx.save()
        refresh()
    }

    // MARK: DEBUG seeding (compiled out of Release)

    #if DEBUG
    private func seedIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["SNOWBALL_SEED"] == "1" else { return }
        let ctx = container.mainContext
        if ((try? ctx.fetch(FetchDescriptor<Debt>()))?.isEmpty ?? true) {
            let samples: [(String, Double, Double, Double)] = [
                ("Store Card", 800, 24.99, 35),
                ("Car Loan", 6200, 6.5, 220),
                ("Visa", 2400, 19.99, 60)
            ]
            for (i, s) in samples.enumerated() {
                ctx.insert(Debt(name: s.0, balance: s.1, apr: s.2, minPayment: s.3,
                                startingBalance: s.1, order: i))
            }
            try? ctx.save()
        }
    }
    #endif
}
