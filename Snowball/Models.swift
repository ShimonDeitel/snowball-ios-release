import Foundation
import SwiftData

/// One debt the user is paying off. All properties have defaults and there are no unique
/// constraints, so the schema is CloudKit-mirroring compatible.
@Model
final class Debt {
    var id: UUID = UUID()
    var name: String = "Debt"
    var balance: Double = 0          // current balance owed
    var apr: Double = 0              // annual percentage rate, e.g. 19.99
    var minPayment: Double = 0       // required minimum monthly payment
    var startingBalance: Double = 0  // balance when first added (for progress rings)
    var createdAt: Date = Date.now
    var order: Int = 0               // user sort hint

    init(id: UUID = UUID(), name: String = "Debt", balance: Double = 0, apr: Double = 0,
         minPayment: Double = 0, startingBalance: Double? = nil,
         createdAt: Date = .now, order: Int = 0) {
        self.id = id
        self.name = name
        self.balance = max(0, balance)
        self.apr = max(0, apr)
        self.minPayment = max(0, minPayment)
        self.startingBalance = max(self.balance, startingBalance ?? balance)
        self.createdAt = createdAt
        self.order = order
    }

    /// Plain-value form for the pure payoff engine.
    var input: DebtInput {
        DebtInput(id: id, name: name, balance: balance, apr: apr, minPayment: minPayment)
    }

    /// Fraction paid off so far (0...1), used by the shrinking progress ring.
    var progress: Double {
        guard startingBalance > 0 else { return balance <= 0 ? 1 : 0 }
        let paid = max(0, startingBalance - balance)
        return min(1, max(0, paid / startingBalance))
    }

    var isPaidOff: Bool { balance <= 0.0001 }
}

/// One logged payment against a debt. Defaults + no unique constraints keep it CloudKit-friendly.
@Model
final class Payment {
    var id: UUID = UUID()
    var debtID: UUID = UUID()
    var debtName: String = "Debt"
    var amount: Double = 0
    var date: Date = Date.now

    init(id: UUID = UUID(), debtID: UUID = UUID(), debtName: String = "Debt",
         amount: Double = 0, date: Date = .now) {
        self.id = id
        self.debtID = debtID
        self.debtName = debtName
        self.amount = max(0, amount)
        self.date = date
    }
}
