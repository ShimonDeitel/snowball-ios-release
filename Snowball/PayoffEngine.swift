import Foundation

/// The debt-payoff strategy.
enum PayoffStrategy: String, CaseIterable, Identifiable, Codable {
    case snowball   // smallest balance first (momentum)
    case avalanche  // highest APR first (least interest)

    var id: String { rawValue }
    var title: String { self == .snowball ? "Snowball" : "Avalanche" }
    var subtitle: String {
        self == .snowball ? "Smallest balance first" : "Highest interest first"
    }
    var blurb: String {
        self == .snowball
            ? "Knock out the smallest debt first for quick wins and momentum."
            : "Attack the highest interest rate first to pay the least overall."
    }
}

/// A plain-value snapshot of a debt, decoupled from SwiftData so the engine stays pure & testable.
struct DebtInput: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var balance: Double      // current balance owed
    var apr: Double          // annual percentage rate, e.g. 19.99 for 19.99%
    var minPayment: Double   // required minimum monthly payment

    init(id: UUID = UUID(), name: String, balance: Double, apr: Double, minPayment: Double) {
        self.id = id
        self.name = name
        self.balance = max(0, balance)
        self.apr = max(0, apr)
        self.minPayment = max(0, minPayment)
    }

    var monthlyRate: Double { apr / 100.0 / 12.0 }
}

/// One debt's standing within a single month of the plan.
struct DebtMonthLine: Equatable {
    let debtID: UUID
    let name: String
    let startingBalance: Double
    let interest: Double
    let payment: Double
    let endingBalance: Double
    var isPaidOffThisMonth: Bool { endingBalance <= 0.0001 && startingBalance > 0 }
}

/// One month of the whole-portfolio plan.
struct PlanMonth: Identifiable, Equatable {
    let index: Int            // 1-based month number from "now"
    let date: Date            // the calendar month this represents
    let lines: [DebtMonthLine]
    let totalPaid: Double
    let totalInterest: Double
    let remainingBalance: Double

    var id: Int { index }
    /// Names of debts fully cleared in this month — used for milestone badges.
    var clearedDebtNames: [String] { lines.filter { $0.isPaidOffThisMonth }.map { $0.name } }
}

/// The computed result of running a strategy against a set of debts with a given monthly budget.
struct PayoffPlan: Equatable {
    let strategy: PayoffStrategy
    let months: [PlanMonth]
    let totalInterest: Double
    let totalPaid: Double
    let monthsToDebtFree: Int
    /// The projected debt-free date, or nil if the plan never finishes (budget too small / runaway).
    let debtFreeDate: Date?
    /// True when the budget couldn't cover the minimums or balances never reach zero.
    let isFeasible: Bool

    static let empty = PayoffPlan(strategy: .snowball, months: [], totalInterest: 0,
                                  totalPaid: 0, monthsToDebtFree: 0, debtFreeDate: nil,
                                  isFeasible: true)
}

/// Pure amortization engine. No I/O, no UI, no SwiftData — fully unit-testable.
enum PayoffEngine {

    /// The sum of all minimum payments — the floor for a viable monthly budget.
    static func totalMinimum(_ debts: [DebtInput]) -> Double {
        debts.filter { $0.balance > 0 }.reduce(0) { $0 + $1.minPayment }
    }

    static func totalBalance(_ debts: [DebtInput]) -> Double {
        debts.reduce(0) { $0 + $1.balance }
    }

    /// Order the debts by the chosen strategy. Ties broken deterministically by name then id so
    /// the plan is stable across runs.
    static func order(_ debts: [DebtInput], by strategy: PayoffStrategy) -> [DebtInput] {
        let active = debts.filter { $0.balance > 0 }
        switch strategy {
        case .snowball:
            return active.sorted {
                if $0.balance != $1.balance { return $0.balance < $1.balance }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .avalanche:
            return active.sorted {
                if $0.apr != $1.apr { return $0.apr > $1.apr }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }

    /// Build the month-by-month plan.
    ///
    /// - Parameters:
    ///   - debts: the current debts (only positive balances are amortized).
    ///   - monthlyBudget: total dollars available each month across ALL debts. If it is below the
    ///     sum of minimums, the plan is marked infeasible (we still amortize what we can so the UI
    ///     can show the shortfall rather than crashing).
    ///   - strategy: snowball or avalanche.
    ///   - startDate: anchor for the projected dates (defaults to now).
    ///   - maxMonths: safety bound so a too-small budget can't loop forever.
    static func makePlan(debts: [DebtInput],
                         monthlyBudget: Double,
                         strategy: PayoffStrategy,
                         startDate: Date = .now,
                         maxMonths: Int = 1200) -> PayoffPlan {
        let cal = Calendar.current
        var balances: [UUID: Double] = [:]
        let order = order(debts, by: strategy)
        for d in order { balances[d.id] = d.balance }
        let nameByID = Dictionary(uniqueKeysWithValues: debts.map { ($0.id, $0.name) })
        let rateByID = Dictionary(uniqueKeysWithValues: debts.map { ($0.id, $0.monthlyRate) })
        let minByID  = Dictionary(uniqueKeysWithValues: debts.map { ($0.id, $0.minPayment) })

        let minimums = totalMinimum(debts)
        // Feasible only when the budget covers the minimums AND is large enough that at least the
        // accruing interest can be beaten (otherwise balances grow forever).
        var feasible = monthlyBudget + 0.0001 >= minimums

        var months: [PlanMonth] = []
        var totalInterest = 0.0
        var totalPaid = 0.0
        var monthIndex = 0

        func anyOutstanding() -> Bool { order.contains { (balances[$0.id] ?? 0) > 0.0001 } }

        while anyOutstanding() && monthIndex < maxMonths {
            monthIndex += 1
            var budget = monthlyBudget
            var lines: [DebtMonthLine] = []
            var monthInterest = 0.0
            var monthPaid = 0.0

            // 1) Accrue interest on every active debt first.
            for d in order {
                let bal = balances[d.id] ?? 0
                guard bal > 0 else { continue }
                let interest = bal * (rateByID[d.id] ?? 0)
                balances[d.id] = bal + interest
                monthInterest += interest
            }

            // 2) Pay the minimum on every debt (capped at the balance).
            var paidThisMonth: [UUID: Double] = [:]
            for d in order {
                let bal = balances[d.id] ?? 0
                guard bal > 0 else { continue }
                let want = min(minByID[d.id] ?? 0, bal)
                let pay = min(want, max(0, budget))
                balances[d.id] = bal - pay
                budget -= pay
                paidThisMonth[d.id] = pay
            }

            // 3) Funnel everything left to the FIRST debt in strategy order (the focus debt),
            //    cascading to the next once one is cleared.
            for d in order {
                if budget <= 0.0001 { break }
                let bal = balances[d.id] ?? 0
                guard bal > 0 else { continue }
                let extra = min(budget, bal)
                balances[d.id] = bal - extra
                budget -= extra
                paidThisMonth[d.id, default: 0] += extra
            }

            // 4) Record per-debt lines. We reconstruct each debt's pre-interest starting balance by
            //    reversing the interest+payment math applied above.
            for d in order {
                let pay = paidThisMonth[d.id] ?? 0
                let ending = max(0, balances[d.id] ?? 0)
                // starting (pre-interest) = ending + pay - interest, but easier: derive interest now.
                // Recompute interest from ending+pay since we already applied it.
                let postInterest = ending + pay
                let rate = rateByID[d.id] ?? 0
                let startingPre = rate > 0 ? postInterest / (1 + rate) : postInterest
                let interest = postInterest - startingPre
                guard startingPre > 0.0001 || pay > 0.0001 else { continue }
                lines.append(DebtMonthLine(debtID: d.id,
                                           name: nameByID[d.id] ?? "Debt",
                                           startingBalance: startingPre,
                                           interest: interest,
                                           payment: pay,
                                           endingBalance: ending))
                monthPaid += pay
            }

            totalInterest += monthInterest
            totalPaid += monthPaid

            let remaining = order.reduce(0.0) { $0 + max(0, balances[$1.id] ?? 0) }
            let date = cal.date(byAdding: .month, value: monthIndex, to: startDate) ?? startDate
            months.append(PlanMonth(index: monthIndex, date: date, lines: lines,
                                    totalPaid: monthPaid, totalInterest: monthInterest,
                                    remainingBalance: remaining))

            // Safety: if nothing was paid down this month (budget can't beat interest), bail.
            if monthPaid <= 0.0001 && remaining > 0.0001 {
                feasible = false
                break
            }
        }

        if monthIndex >= maxMonths && anyOutstanding() { feasible = false }

        let debtFreeDate = (feasible && !anyOutstanding() && !months.isEmpty) ? months.last?.date : nil

        return PayoffPlan(strategy: strategy,
                          months: months,
                          totalInterest: totalInterest,
                          totalPaid: totalPaid,
                          monthsToDebtFree: feasible ? months.count : 0,
                          debtFreeDate: debtFreeDate,
                          isFeasible: feasible)
    }
}
