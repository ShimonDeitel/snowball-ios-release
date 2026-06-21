# Snowball — Debt Payoff

**App Store Title:** Snowball: Debt Payoff
**Subtitle:** Pay off debt, smallest first
**Bundle id:** com.shimondeitel.snowball
**iCloud container:** iCloud.com.shimondeitel.snowball
**Pro product (one-time, $0.99 non-consumable):** snowball_pro_unlock
**Platform:** iOS 17+, native Swift / SwiftUI, XcodeGen project

---

## What it does

Snowball is a debt payoff planner built around the two proven payoff methods:

- **Snowball** — pay the *smallest balance* first for quick wins and momentum.
- **Avalanche** — pay the *highest APR* first to minimize total interest.

You enter each debt (balance, APR, minimum payment). Snowball computes the payoff
order and a month-by-month amortization plan, shows a shrinking progress ring per
debt, awards milestone badges as debts are cleared, and lets you log each payment
with one tap.

## Free vs Pro

- **Free:** up to **2 debts**, full month-by-month plan, progress rings, payment
  logging, milestone badges, snowball method.
- **Pro ($0.99 one-time, `snowball_pro_unlock`):**
  - Unlimited debts
  - Snowball vs Avalanche comparison (interest saved)
  - Payoff-date projection on the comparison
  - Share your plan and milestones

Pro is **never persisted as truth** — it is derived live from StoreKit 2
`Transaction.currentEntitlements` (see `Store.swift`). The free 2-debt cap is also
enforced in `AppModel.addDebt` as defense-in-depth.

## Screens

- **Home** (`HomeView`) — total debt, projected debt-free date, a row per debt with
  a shrinking ring + percent paid, "View payoff plan", and "Add a debt" (locks to the
  paywall past the free cap).
- **Debt detail** (`DebtDetailView`) — large progress ring, APR / min / paid tiles,
  "Log a payment", payment history, edit/delete.
- **Add / Edit debt** (`AddDebtView`) — name, balance, APR, minimum payment.
- **Plan / Compare** (`PlanView`) — strategy chips, monthly-budget card with an
  "extra per month" slider, summary tiles (debt-free date / months / interest),
  Snowball-vs-Avalanche comparison (Pro), milestone badges, and the month-by-month
  schedule. Share button (Pro).
- **Settings** (`SettingsView`) — Pro unlock / restore, default payoff method,
  appearance, account (Sign in with Apple, sign out, delete account), privacy link.
- **Onboarding** (`OnboardingView`) — Sign in with Apple gate.

## Engine (pure, well-tested)

`PayoffEngine` (in `PayoffEngine.swift`) is a pure value-in / value-out amortizer
with no I/O or UI:

- `order(_:by:)` — sorts active debts by strategy (snowball = smallest balance;
  avalanche = highest APR), with deterministic tie-breaks.
- `makePlan(debts:monthlyBudget:strategy:…)` — month loop that (1) accrues monthly
  interest (`apr/100/12`), (2) pays each minimum, (3) funnels all remaining budget to
  the focus debt and cascades to the next once one is cleared, (4) records a per-debt
  line and a `PlanMonth`. Flags `isFeasible == false` when the budget can't beat the
  interest (so balances never shrink), with a `maxMonths` safety bound.

Outputs `PayoffPlan` with `months`, `totalInterest`, `totalPaid`, `monthsToDebtFree`,
and `debtFreeDate`.

## Data (SwiftData local + CloudKit mirror)

- `Debt(name, balance, apr, minPayment, startingBalance, createdAt, order)`
- `Payment(debtID, debtName, amount, date)`

All properties have defaults and there are no unique constraints, so the schema is
CloudKit-mirroring compatible. `AppModel.makeContainer()` uses an automatic CloudKit
private-DB mirror when an iCloud account exists and degrades gracefully to local-only
(and finally to in-memory) so the app always works offline.

`CloudSync` writes a best-effort public-DB `PaidStatus` record (keyed by the Sign in
with Apple user id) for owner visibility only — it never gates Pro.

## Privacy & permissions

- **Zero device permissions** — no camera, photos, mic, location, contacts, health,
  motion, sensors, or files.
- **Backend = Apple only** — CloudKit + Sign in with Apple. No servers, no third-party
  APIs, no AI. Works fully offline.
- `PrivacyInfo.xcprivacy` declares no tracking and only required-reason API usage.
- No emojis anywhere; SF Symbols only.

## Design

Minimalist, Apple-native: flat surfaces, system semantic colors (light + dark), a
single Apple-blue accent (`#007AFF`). No gradients. Shared design system in
`Design.swift` + `Components.swift` + `ColorHex.swift`.

## Build & test

XcodeGen project (`project.yml`). Two targets: the `Snowball` app and a
`SnowballTests` unit-test bundle (no widget, no UI-test target). One `$0.99`
non-consumable in `Snowball.storekit`.

```
xcodegen generate
xcodebuild -project Snowball.xcodeproj -scheme Snowball -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/snowball_dd CODE_SIGNING_ALLOWED=NO build
```

`SnowballTests/SnowballLogicTests.swift` covers strategy ordering, zero-interest and
APR amortization, the extra-budget-finishes-sooner property, the avalanche ≤ snowball
interest invariant, infeasible-budget detection, the empty-plan case, the free 2-debt
cap, payment logging/clamping, and the StoreKit price/lock baseline. All 11 pass.
