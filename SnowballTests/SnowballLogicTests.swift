import XCTest
import SwiftData
import StoreKit
@testable import Snowball

/// Tests for the live logic: the pure payoff/amortization engine, strategy ordering,
/// the free-tier debt cap, payment logging, and the StoreKit price/lock baseline.
@MainActor
final class SnowballLogicTests: XCTestCase {

    private func memoryModel() -> ModelContainer {
        try! ModelContainer(for: Debt.self, Payment.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func debt(_ name: String, _ balance: Double, _ apr: Double, _ minP: Double) -> DebtInput {
        DebtInput(name: name, balance: balance, apr: apr, minPayment: minP)
    }

    // MARK: Strategy ordering

    func testSnowballOrdersBySmallestBalanceFirst() {
        let debts = [debt("A", 5000, 5, 100), debt("B", 800, 25, 30), debt("C", 2000, 12, 50)]
        let ordered = PayoffEngine.order(debts, by: .snowball).map(\.name)
        XCTAssertEqual(ordered, ["B", "C", "A"], "snowball = smallest balance first")
    }

    func testAvalancheOrdersByHighestAPRFirst() {
        let debts = [debt("A", 5000, 5, 100), debt("B", 800, 25, 30), debt("C", 2000, 12, 50)]
        let ordered = PayoffEngine.order(debts, by: .avalanche).map(\.name)
        XCTAssertEqual(ordered, ["B", "C", "A"], "avalanche = highest APR first")
    }

    // MARK: Amortization correctness

    func testZeroInterestPaysOffInExactWholeMonths() {
        // One $1,000 debt, 0% APR, $100/mo min, no extra → exactly 10 months.
        let plan = PayoffEngine.makePlan(debts: [debt("Loan", 1000, 0, 100)],
                                         monthlyBudget: 100, strategy: .snowball)
        XCTAssertTrue(plan.isFeasible)
        XCTAssertEqual(plan.monthsToDebtFree, 10)
        XCTAssertEqual(plan.totalInterest, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.totalPaid, 1000, accuracy: 0.01)
        XCTAssertNotNil(plan.debtFreeDate)
    }

    func testInterestAccruesAndIsPositiveOnAPRDebt() {
        let plan = PayoffEngine.makePlan(debts: [debt("Card", 1000, 24, 50)],
                                         monthlyBudget: 100, strategy: .avalanche)
        XCTAssertTrue(plan.isFeasible)
        XCTAssertGreaterThan(plan.totalInterest, 0, "an APR debt must accrue some interest")
        // Paying $100/mo on a $1,000 balance at 24% finishes within a couple of years.
        XCTAssertLessThan(plan.monthsToDebtFree, 24)
        XCTAssertGreaterThan(plan.monthsToDebtFree, 10)
    }

    func testExtraBudgetFunnelsToFocusDebtAndFinishesSooner() {
        let debts = [debt("Small", 500, 10, 25), debt("Big", 3000, 10, 60)]
        let lean = PayoffEngine.makePlan(debts: debts, monthlyBudget: 85, strategy: .snowball)
        let aggressive = PayoffEngine.makePlan(debts: debts, monthlyBudget: 285, strategy: .snowball)
        XCTAssertTrue(lean.isFeasible)
        XCTAssertTrue(aggressive.isFeasible)
        XCTAssertLessThan(aggressive.monthsToDebtFree, lean.monthsToDebtFree,
                          "a bigger budget must reach debt-free sooner")
        XCTAssertLessThan(aggressive.totalInterest, lean.totalInterest,
                          "paying faster must cost less interest")
    }

    func testAvalancheNeverCostsMoreInterestThanSnowball() {
        // Classic case: small balance has the LOW rate, big balance the HIGH rate.
        let debts = [debt("SmallLow", 500, 6, 25), debt("BigHigh", 4000, 28, 90)]
        let snow = PayoffEngine.makePlan(debts: debts, monthlyBudget: 300, strategy: .snowball)
        let aval = PayoffEngine.makePlan(debts: debts, monthlyBudget: 300, strategy: .avalanche)
        XCTAssertTrue(snow.isFeasible && aval.isFeasible)
        XCTAssertLessThanOrEqual(aval.totalInterest, snow.totalInterest + 0.01,
                                 "avalanche minimizes interest by definition")
    }

    func testInfeasibleWhenBudgetCannotBeatInterest() {
        // $10k at 30% APR with only $50/mo — interest alone exceeds the payment forever.
        let plan = PayoffEngine.makePlan(debts: [debt("Trap", 10000, 30, 50)],
                                         monthlyBudget: 50, strategy: .snowball)
        XCTAssertFalse(plan.isFeasible, "a budget below the interest must be flagged infeasible")
        XCTAssertNil(plan.debtFreeDate)
    }

    func testEmptyDebtsProducesEmptyFeasiblePlan() {
        let plan = PayoffEngine.makePlan(debts: [], monthlyBudget: 100, strategy: .snowball)
        XCTAssertTrue(plan.months.isEmpty)
        XCTAssertTrue(plan.isFeasible)
        XCTAssertNil(plan.debtFreeDate)
        XCTAssertEqual(plan.monthsToDebtFree, 0)
    }

    // MARK: Free-tier cap (defense-in-depth)

    func testFreeUserCappedAtTwoDebts() {
        let model = AppModel(container: memoryModel())
        // No store attached → not Pro.
        XCTAssertNotNil(model.addDebt(name: "One", balance: 100, apr: 5, minPayment: 10))
        XCTAssertNotNil(model.addDebt(name: "Two", balance: 100, apr: 5, minPayment: 10))
        XCTAssertFalse(model.canAddDebt, "free tier is capped at two debts")
        let third = model.addDebt(name: "Three", balance: 100, apr: 5, minPayment: 10)
        XCTAssertNil(third, "the third debt must be rejected for free users")
        XCTAssertEqual(model.debts.count, 2)
    }

    // MARK: Payment logging

    func testLoggingPaymentReducesBalanceAndRecordsHistory() {
        let model = AppModel(container: memoryModel())
        let d = model.addDebt(name: "Visa", balance: 500, apr: 20, minPayment: 25)!
        model.logPayment(d, amount: 200)
        XCTAssertEqual(d.balance, 300, accuracy: 0.001)
        XCTAssertEqual(d.progress, 0.4, accuracy: 0.001, "200 of 500 paid = 40%")
        XCTAssertEqual(model.payments(for: d).count, 1)
        // Overpaying clamps to the balance and never goes negative.
        model.logPayment(d, amount: 9999)
        XCTAssertEqual(d.balance, 0, accuracy: 0.001)
        XCTAssertTrue(d.isPaidOff)
    }

    // MARK: Store baseline

    func testStoreStartsLockedAtRightPrice() async {
        let store = Store()
        try? await Task.sleep(for: .seconds(0.3))
        XCTAssertEqual(Store.productID, "snowball_pro_unlock")
        XCTAssertEqual(store.displayPrice, "$0.99")
        XCTAssertFalse(store.isPro, "Pro must start locked")
    }
}
