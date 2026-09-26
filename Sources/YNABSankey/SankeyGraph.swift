import Foundation

struct SankeyNode: Sendable, Equatable {
    enum Tint: Sendable, Equatable {
        case income, budget, saved, reserves
        case group(Int) // palette index
    }
    let id: String
    let label: String
    let column: Int
    let tint: Tint
}

struct SankeyLink: Sendable, Equatable {
    let source: Int
    let target: Int
    let value: Milliunits
}

/// Nodes are listed in draw order within each column (top to bottom).
struct SankeyGraph: Sendable {
    var nodes: [SankeyNode] = []
    var links: [SankeyLink] = []

    @discardableResult
    mutating func addNode(_ node: SankeyNode) -> Int {
        nodes.append(node)
        return nodes.count - 1
    }
}

struct SankeyOptions: Sendable {
    var showCategories = true
    var maxIncomeSources = 7
    /// Categories smaller than this share of total spending fold into "Other <group>".
    var minCategoryShare = 0.006
}

extension PeriodSummary {
    /// Income sources → Budget → category groups (+ Saved) → categories.
    func sankeyGraph(options: SankeyOptions = SankeyOptions()) -> SankeyGraph {
        var g = SankeyGraph()
        guard !isEmpty else { return g }

        let income = totalIncome, spending = totalSpending

        // Column 0: income sources, biggest first, tail folded into "Other income".
        var sources = incomeByPayee.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        if sources.count > options.maxIncomeSources {
            let rest = sources[(options.maxIncomeSources - 1)...].reduce(0) { $0 + $1.value }
            sources = Array(sources.prefix(options.maxIncomeSources - 1)) + [("Other income", rest)]
        }
        var sourceNodes: [(Int, Milliunits)] = sources.map { payee, value in
            (g.addNode(SankeyNode(id: "income:\(payee)", label: payee, column: 0, tint: .income)), value)
        }
        if spending > income {
            let idx = g.addNode(SankeyNode(id: "reserves", label: "From savings / buffer", column: 0, tint: .reserves))
            sourceNodes.append((idx, spending - income))
        }

        // Column 1: the budget itself.
        let budget = g.addNode(SankeyNode(id: "budget", label: "Budget", column: 1, tint: .budget))
        for (idx, value) in sourceNodes { g.links.append(SankeyLink(source: idx, target: budget, value: value)) }

        // Column 2: category groups, biggest first; "Saved" last.
        var byGroup: [String: [(CategoryInfo, Milliunits)]] = [:]
        for (id, value) in spendingByCategory {
            guard let info = categories[id] else { continue }
            byGroup[info.groupId, default: []].append((info, value))
        }
        let groups = byGroup
            .map { (id: $0.key, cats: $0.value, total: $0.value.reduce(0) { $0 + $1.1 }) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.id < $1.id }

        var groupNodes: [(node: Int, palette: Int, cats: [(CategoryInfo, Milliunits)])] = []
        for (i, group) in groups.enumerated() {
            let name = group.cats[0].0.groupName
            let idx = g.addNode(SankeyNode(id: "group:\(group.id)", label: name, column: 2, tint: .group(i)))
            g.links.append(SankeyLink(source: budget, target: idx, value: group.total))
            groupNodes.append((idx, i, group.cats))
        }
        if income > spending {
            let saved = g.addNode(SankeyNode(id: "saved", label: "Saved / unspent", column: 2, tint: .saved))
            g.links.append(SankeyLink(source: budget, target: saved, value: income - spending))
        }

        // Column 3: categories, grouped under their group so ribbons don't cross.
        guard options.showCategories else { return g }
        let threshold = Milliunits((Double(spending) * options.minCategoryShare).rounded())
        for group in groupNodes {
            let sorted = group.cats.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
            var kept = sorted.filter { $0.1 >= threshold }
            let small = sorted.filter { $0.1 < threshold }
            if small.count == 1 { kept += small }
            for (info, value) in kept {
                let idx = g.addNode(SankeyNode(id: "cat:\(info.id)", label: info.name, column: 3,
                                               tint: .group(group.palette)))
                g.links.append(SankeyLink(source: group.node, target: idx, value: value))
            }
            if small.count > 1 {
                let value = small.reduce(0) { $0 + $1.1 }
                let label = "Other \(g.nodes[group.node].label) (\(small.count))"
                let idx = g.addNode(SankeyNode(id: "other:\(g.nodes[group.node].id)", label: label, column: 3,
                                               tint: .group(group.palette)))
                g.links.append(SankeyLink(source: group.node, target: idx, value: value))
            }
        }
        return g
    }
}
