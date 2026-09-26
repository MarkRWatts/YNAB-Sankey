import CoreGraphics
import Testing
@testable import YNABSankey

private let groups = [
    YNABCategoryGroup(id: "internal", name: "Internal Master Category", hidden: false, deleted: false, categories: [
        YNABCategory(id: "rta", name: "Inflow: Ready to Assign", categoryGroupId: "internal", hidden: false, deleted: false),
        YNABCategory(id: "uncat", name: "Uncategorized", categoryGroupId: "internal", hidden: false, deleted: false),
    ]),
    YNABCategoryGroup(id: "bills", name: "Bills", hidden: false, deleted: false, categories: [
        YNABCategory(id: "rent", name: "Rent", categoryGroupId: "bills", hidden: false, deleted: false),
        YNABCategory(id: "power", name: "Power", categoryGroupId: "bills", hidden: false, deleted: false),
    ]),
    YNABCategoryGroup(id: "fun", name: "Fun", hidden: false, deleted: false, categories: [
        YNABCategory(id: "eating", name: "Eating out", categoryGroupId: "fun", hidden: false, deleted: false),
        YNABCategory(id: "pension", name: "Pension", categoryGroupId: "fun", hidden: false, deleted: false),
    ]),
]

private let accounts = [
    YNABAccount(id: "current", name: "Current", onBudget: true, deleted: false),
    YNABAccount(id: "savings", name: "Savings", onBudget: true, deleted: false),
    YNABAccount(id: "pensionAcct", name: "Pension", onBudget: false, deleted: false),
]

private func tx(_ id: String, _ date: String, _ amount: Milliunits, payee: String? = nil, account: String = "current",
                category: String? = nil, transfer: String? = nil, deleted: Bool = false,
                subs: [YNABSubtransaction] = []) -> YNABTransaction {
    YNABTransaction(id: id, date: date, amount: amount, payeeName: payee, accountId: account, categoryId: category,
                    transferAccountId: transfer, deleted: deleted, subtransactions: subs)
}

private let transactions: [YNABTransaction] = [
    tx("salary", "2026-09-01", 3_000_000, payee: "Employer", category: "rta"),
    tx("rent", "2026-09-02", -1_200_000, payee: "Landlord", category: "rent"),
    tx("split", "2026-09-03", -150_000, payee: "Supermarket", subs: [
        YNABSubtransaction(id: "s1", amount: -100_000, payeeName: nil, categoryId: "power", transferAccountId: nil, deleted: false),
        YNABSubtransaction(id: "s2", amount: -50_000, payeeName: nil, categoryId: "eating", transferAccountId: nil, deleted: false),
    ]),
    tx("refund", "2026-09-04", 20_000, payee: "Restaurant", category: "eating"),
    tx("move", "2026-09-05", -500_000, account: "current", transfer: "savings"), // own money moving: ignored
    tx("pension", "2026-09-06", -300_000, account: "current", category: "pension", transfer: "pensionAcct"), // counts
    tx("tracking", "2026-09-06", 300_000, account: "pensionAcct", transfer: "current"), // off-budget: ignored
    tx("deleted", "2026-09-07", -999_000, category: "rent", deleted: true),
    tx("mystery", "2026-09-08", -10_000, payee: "???"), // uncategorised
    tx("august", "2026-08-15", -40_000, category: "eating"),
]

@Test func ledgerAppliesSpendingRules() {
    let ledger = Ledger(transactions: transactions, accounts: accounts, groups: groups)
    let sep = ledger.summary(for: .month(year: 2026, month: 9))

    #expect(sep.incomeByPayee == ["Employer": 3_000_000])
    #expect(sep.spendingByCategory == [
        "rent": 1_200_000,
        "power": 100_000,
        "eating": 30_000, // 50 spent minus 20 refunded
        "pension": 300_000,
        Ledger.uncategorizedId: 10_000,
    ])
    #expect(ledger.summary(for: .year(2026)).spendingByCategory["eating"] == 70_000)
    #expect(ledger.dateRange! == ("2026-08-15", "2026-09-08"))
}

@Test func periodsEnumerateAcrossYearBoundary() {
    let months = Period.all(monthly: true, from: "2025-11-20", to: "2026-02-01")
    #expect(months == [.month(year: 2025, month: 11), .month(year: 2025, month: 12),
                       .month(year: 2026, month: 1), .month(year: 2026, month: 2)])
    #expect(Period.all(monthly: false, from: "2024-03-01", to: "2026-01-01") == [.year(2024), .year(2025), .year(2026)])
}

/// Every node except sources and sinks must have equal flow in and out.
private func expectConserved(_ g: SankeyGraph) {
    for i in g.nodes.indices {
        let inflow = g.links.filter { $0.target == i }.reduce(0) { $0 + $1.value }
        let outflow = g.links.filter { $0.source == i }.reduce(0) { $0 + $1.value }
        if inflow > 0 && outflow > 0 { #expect(inflow == outflow, "\(g.nodes[i].label)") }
    }
}

@Test func graphBalancesSavingsAndOverspend() {
    let ledger = Ledger(transactions: transactions, accounts: accounts, groups: groups)
    let sep = ledger.summary(for: .month(year: 2026, month: 9)).sankeyGraph()
    expectConserved(sep)
    #expect(sep.nodes.contains { $0.id == "saved" })
    #expect(sep.links.first { sep.nodes[$0.target].id == "saved" }?.value == Milliunits(1_360_000))

    let aug = ledger.summary(for: .month(year: 2026, month: 8)).sankeyGraph()
    expectConserved(aug)
    #expect(aug.links.first { aug.nodes[$0.source].id == "reserves" }?.value == 40_000)
}

@Test func smallCategoriesFoldIntoOther() {
    let infos = (0..<5).map { CategoryInfo(id: "c\($0)", name: "C\($0)", groupId: "g", groupName: "G", groupOrder: 0) }
    let summary = PeriodSummary(
        incomeByPayee: [:],
        spendingByCategory: ["c0": 1_000_000, "c1": 1_000, "c2": 1_000, "c3": 500_000, "c4": 2_000],
        categories: Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) }))
    let g = summary.sankeyGraph(options: SankeyOptions(minCategoryShare: 0.01))
    let leaves = g.nodes.filter { $0.column == 3 }.map(\.label)
    #expect(leaves == ["C0", "C3", "Other G (3)"])
    expectConserved(g)
}

@Test func layoutStacksRibbonsFlushWithNodes() {
    let ledger = Ledger(transactions: transactions, accounts: accounts, groups: groups)
    let g = ledger.summary(for: .month(year: 2026, month: 9)).sankeyGraph()
    let layout = SankeyLayout(graph: g, size: CGSize(width: 1200, height: 700))

    for node in layout.nodes {
        #expect(node.rect.minY >= 0 && node.rect.maxY <= 700)
        let out = layout.links.filter { g.links[$0.index].source == node.index }
        if let first = out.first, let last = out.last {
            #expect(abs(first.sourceY.lowerBound - node.rect.minY) < 0.001)
            #expect(abs(last.sourceY.upperBound - node.rect.maxY) < 0.001)
        }
    }
    // Nodes in one column never overlap.
    for col in 0...3 {
        let rects = layout.nodes.filter { g.nodes[$0.index].column == col }.map(\.rect).sorted { $0.minY < $1.minY }
        for (a, b) in zip(rects, rects.dropFirst()) { #expect(a.maxY <= b.minY + 0.001) }
    }
}
