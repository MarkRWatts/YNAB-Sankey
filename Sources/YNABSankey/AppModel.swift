import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Granularity: String, CaseIterable, Identifiable {
        case month = "Month", year = "Year"
        var id: String { rawValue }
    }

    private(set) var hasToken = Keychain.readToken() != nil
    private(set) var budgets: [YNABBudgetSummary] = []
    private(set) var ledger: Ledger?
    private(set) var isLoading = false
    var errorMessage: String?

    /// The budget currently on screen. Switching it from the toolbar lasts for this session only.
    var selectedBudgetId: String? {
        didSet { if oldValue != selectedBudgetId { Task { await loadLedger() } } }
    }

    /// The budget to open at launch (set in Settings); nil means "most recently edited in YNAB".
    var defaultBudgetId: String? = UserDefaults.standard.string(forKey: "defaultBudgetId") {
        didSet { UserDefaults.standard.set(defaultBudgetId, forKey: "defaultBudgetId") }
    }

    var granularity: Granularity = .month {
        didSet { selectedPeriod = periods.last(where: { $0 <= current(selectedPeriod) }) ?? periods.last }
    }
    var selectedPeriod: Period?
    var showCategories = true
    var zoom: CGFloat = 1

    func zoom(by factor: CGFloat) {
        zoom = min(max(zoom * factor, SankeyView.zoomRange.lowerBound), SankeyView.zoomRange.upperBound)
    }

    var selectedBudget: YNABBudgetSummary? { budgets.first { $0.id == selectedBudgetId } }

    var periods: [Period] {
        guard let range = ledger?.dateRange else { return [] }
        return Period.all(monthly: granularity == .month, from: range.first, to: range.last)
    }

    var summary: PeriodSummary? {
        guard let ledger, let selectedPeriod else { return nil }
        return ledger.summary(for: selectedPeriod)
    }

    /// Maps a period into the current granularity (e.g. Sep 2026 → 2026).
    private func current(_ p: Period?) -> Period {
        switch (p, granularity) {
        case (.month(let y, _)?, .year): .year(y)
        case (.year(let y)?, .month):
            periods.last(where: { if case .month(y, _) = $0 { true } else { false } }) ?? .month(year: y, month: 12)
        case (let p?, _): p
        case (nil, _): periods.last ?? .year(0)
        }
    }

    func step(_ delta: Int) {
        guard let selectedPeriod, let i = periods.firstIndex(of: selectedPeriod) else { return }
        let j = i + delta
        if periods.indices.contains(j) { self.selectedPeriod = periods[j] }
    }

    func canStep(_ delta: Int) -> Bool {
        guard let selectedPeriod, let i = periods.firstIndex(of: selectedPeriod) else { return false }
        return periods.indices.contains(i + delta)
    }

    // MARK: Token

    func saveToken(_ token: String) async {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await YNABClient(token: token).budgets()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard Keychain.saveToken(token) else {
            errorMessage = "Couldn't save the token to the Keychain."
            return
        }
        errorMessage = nil
        hasToken = true
        await refresh()
    }

    func forgetToken() {
        Keychain.deleteToken()
        hasToken = false
        defaultBudgetId = nil // a new token may belong to a different YNAB account
        selectedBudgetId = nil
        budgets = []
        ledger = nil
    }

    // MARK: Loading

    func refresh() async {
        guard let token = Keychain.readToken() else { hasToken = false; return }
        isLoading = true
        do {
            budgets = try await YNABClient(token: token).budgets()
                .sorted { ($0.lastModifiedOn ?? "") > ($1.lastModifiedOn ?? "") }
            if selectedBudget == nil {
                // budgets is sorted most-recently-edited first. A default that has
                // since been deleted, or isn't visible to this token, falls back to that.
                let preferred = budgets.first { $0.id == defaultBudgetId } ?? budgets.first
                selectedBudgetId = preferred?.id // didSet triggers the ledger load
                isLoading = false
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }
        isLoading = false
        await loadLedger()
    }

    private func loadLedger() async {
        guard let token = Keychain.readToken(), let budgetId = selectedBudgetId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let client = YNABClient(token: token)
            async let accounts = client.accounts(budgetId: budgetId)
            async let groups = client.categoryGroups(budgetId: budgetId)
            async let transactions = client.transactions(budgetId: budgetId)
            let ledger = try await Ledger(transactions: transactions, accounts: accounts, groups: groups)
            guard budgetId == selectedBudgetId else { return }
            self.ledger = ledger
            errorMessage = nil
            if selectedPeriod == nil || !periods.contains(selectedPeriod!) {
                selectedPeriod = defaultPeriod()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The current month (or year) if there's data for it, otherwise the latest.
    private func defaultPeriod() -> Period? {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let today: Period = granularity == .month
            ? .month(year: now.year!, month: now.month!) : .year(now.year!)
        return periods.contains(today) ? today : periods.last
    }

    // MARK: Formatting

    func format(_ amount: Milliunits) -> String {
        let code = selectedBudget?.currencyFormat?.isoCode ?? "GBP"
        let value = Double(amount) / 1000
        return value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }
}
