import Foundation
import SwiftUI
import Testing
@testable import YNABSankey

/// Renders a Sankey of synthetic data to a PNG for eyeballing the layout.
/// Only runs when SANKEY_SNAPSHOT_DIR is set.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["SANKEY_SNAPSHOT_DIR"] != nil))
func renderSnapshot() throws {
    let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SANKEY_SNAPSHOT_DIR"]!)
    let spend: [(group: String, cat: String, amount: Milliunits)] = [
        ("Bills", "Mortgage", 1_450_000), ("Bills", "Council Tax", 210_000), ("Bills", "Energy", 185_000),
        ("Bills", "Water", 42_000), ("Bills", "Broadband", 35_000), ("Bills", "Phones", 28_000),
        ("Everyday", "Groceries", 620_000), ("Everyday", "Fuel", 140_000), ("Everyday", "Household", 60_000),
        ("Everyday", "Parking", 6_000), ("Everyday", "Car wash", 4_000),
        ("Fun", "Eating out", 180_000), ("Fun", "Subscriptions", 45_000), ("Fun", "Hobbies", 90_000),
        ("Kids", "Clubs", 120_000), ("Kids", "Clothes", 75_000),
        ("Savings Goals", "Holiday", 300_000), ("Savings Goals", "Christmas", 100_000),
    ]
    var categories: [String: CategoryInfo] = [:]
    var spending: [String: Milliunits] = [:]
    for (i, s) in spend.enumerated() {
        categories["c\(i)"] = CategoryInfo(id: "c\(i)", name: s.cat, groupId: s.group, groupName: s.group, groupOrder: 0)
        spending["c\(i)"] = s.amount
    }
    let summary = PeriodSummary(
        incomeByPayee: ["Acme Widgets International Holdings Ltd": 3_900_000, "Partner Salary": 1_400_000, "Child Benefit": 102_000,
                        "Interest": 12_000],
        spendingByCategory: spending, categories: categories)

    for showCategories in [true, false] {
        let view = SankeyChart(graph: summary.sankeyGraph(options: SankeyOptions(showCategories: showCategories)),
                              format: { (Double($0) / 1000).formatted(.currency(code: "GBP").precision(.fractionLength(0))) },
                              total: max(summary.totalIncome, summary.totalSpending))
            .frame(width: 1300, height: 760)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: dir.appendingPathComponent("sankey-\(showCategories ? "categories" : "groups").png"))
    }
}
