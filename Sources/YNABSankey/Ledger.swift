import Foundation

/// One leaf money movement that matters for a spending Sankey: either income
/// into "Inflow: Ready to Assign", or activity against a spending category.
struct LedgerEntry: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case income(payee: String)
        case category(id: String)
    }
    let date: String // "YYYY-MM-DD"
    let amount: Milliunits // YNAB sign: negative = outflow
    let kind: Kind
}

struct CategoryInfo: Sendable, Equatable {
    let id: String
    let name: String
    let groupId: String
    let groupName: String
    let groupOrder: Int
}

/// The budget's transactions reduced to the entries a Sankey needs, plus the
/// category metadata to label them.
struct Ledger: Sendable {
    static let uncategorizedId = "__uncategorized__"

    let entries: [LedgerEntry]
    let categories: [String: CategoryInfo]

    /// Rules:
    /// - Only on-budget accounts count (tracking accounts have no categories).
    /// - Split transactions are replaced by their subtransactions.
    /// - Transfers with no category (on-budget ↔ on-budget) are money moving
    ///   between your own accounts, so they're skipped. Transfers *with* a
    ///   category (on-budget → tracking, e.g. a pension contribution) are real
    ///   spending and are kept.
    /// - Anything categorised to an "Inflow: …" internal category is income,
    ///   grouped by payee. Refunds categorised to a spending category net off
    ///   that category's spending instead.
    init(transactions: [YNABTransaction], accounts: [YNABAccount], groups: [YNABCategoryGroup]) {
        let onBudget = Set(accounts.filter(\.onBudget).map(\.id))

        var categories: [String: CategoryInfo] = [:]
        var inflowIds: Set<String> = []
        for (order, group) in groups.enumerated() {
            for c in group.categories {
                if group.name == "Internal Master Category" {
                    if c.name.hasPrefix("Inflow") { inflowIds.insert(c.id) }
                    if c.name != "Uncategorized" { continue }
                }
                categories[c.id] = CategoryInfo(
                    id: c.id, name: c.name, groupId: group.id, groupName: group.name, groupOrder: order)
            }
        }
        categories[Self.uncategorizedId] = CategoryInfo(
            id: Self.uncategorizedId, name: "Uncategorized", groupId: Self.uncategorizedId,
            groupName: "Uncategorized", groupOrder: Int.max)

        var entries: [LedgerEntry] = []
        func add(date: String, amount: Milliunits, payee: String?, categoryId: String?, transfer: String?) {
            guard amount != 0 else { return }
            if let categoryId, inflowIds.contains(categoryId) {
                entries.append(LedgerEntry(date: date, amount: amount, kind: .income(payee: payee ?? "Unknown payee")))
            } else if let categoryId {
                let id = categories[categoryId] == nil ? Self.uncategorizedId : categoryId
                entries.append(LedgerEntry(date: date, amount: amount, kind: .category(id: id)))
            } else if transfer == nil {
                entries.append(LedgerEntry(date: date, amount: amount, kind: .category(id: Self.uncategorizedId)))
            }
        }

        for t in transactions where !t.deleted && onBudget.contains(t.accountId) {
            let subs = t.subtransactions.filter { !$0.deleted }
            if subs.isEmpty {
                add(date: t.date, amount: t.amount, payee: t.payeeName, categoryId: t.categoryId,
                    transfer: t.transferAccountId)
            } else {
                for s in subs {
                    add(date: t.date, amount: s.amount, payee: s.payeeName ?? t.payeeName,
                        categoryId: s.categoryId, transfer: s.transferAccountId)
                }
            }
        }

        self.entries = entries
        self.categories = categories
    }

    var dateRange: (first: String, last: String)? {
        guard let first = entries.map(\.date).min(), let last = entries.map(\.date).max() else { return nil }
        return (first, last)
    }

    func summary(for period: Period) -> PeriodSummary {
        var income: [String: Milliunits] = [:]
        var spending: [String: Milliunits] = [:]
        for e in entries where period.contains(e.date) {
            switch e.kind {
            case .income(let payee): income[payee, default: 0] += e.amount
            case .category(let id): spending[id, default: 0] -= e.amount
            }
        }
        return PeriodSummary(
            incomeByPayee: income.filter { $0.value > 0 },
            spendingByCategory: spending.filter { $0.value > 0 },
            categories: categories)
    }
}

/// A calendar month or year.
enum Period: Hashable, Sendable, Comparable {
    case month(year: Int, month: Int)
    case year(Int)

    var prefix: String {
        switch self {
        case .month(let y, let m): String(format: "%04d-%02d", y, m)
        case .year(let y): String(format: "%04d", y)
        }
    }

    func contains(_ date: String) -> Bool { date.hasPrefix(prefix) }

    var title: String {
        switch self {
        case .year(let y): return String(y)
        case .month(let y, let m):
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: 1))!
            return f.string(from: date)
        }
    }

    static func < (a: Period, b: Period) -> Bool { a.prefix < b.prefix }

    /// Every month (or year) from `first` through `last`, oldest first.
    static func all(monthly: Bool, from first: String, to last: String) -> [Period] {
        func ym(_ s: String) -> (Int, Int) {
            let parts = s.split(separator: "-").compactMap { Int($0) }
            return (parts[0], parts[1])
        }
        let (y0, m0) = ym(first), (y1, m1) = ym(last)
        if !monthly { return (y0...y1).map { .year($0) } }
        var out: [Period] = []
        var (y, m) = (y0, m0)
        while (y, m) <= (y1, m1) {
            out.append(.month(year: y, month: m))
            m += 1
            if m > 12 { m = 1; y += 1 }
        }
        return out
    }
}

struct PeriodSummary: Sendable {
    let incomeByPayee: [String: Milliunits]
    let spendingByCategory: [String: Milliunits] // positive = net spend
    let categories: [String: CategoryInfo]

    var totalIncome: Milliunits { incomeByPayee.values.reduce(0, +) }
    var totalSpending: Milliunits { spendingByCategory.values.reduce(0, +) }
    var isEmpty: Bool { totalIncome == 0 && totalSpending == 0 }
}
