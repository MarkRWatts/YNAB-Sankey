import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.hasToken {
                TokenSetupView()
            } else if model.ledger == nil {
                VStack(spacing: 12) {
                    if model.isLoading {
                        ProgressView("Loading your budget from YNAB…")
                    } else if let error = model.errorMessage {
                        ContentUnavailableView("Couldn't load your budget", systemImage: "exclamationmark.triangle",
                                               description: Text(error))
                        Button("Try Again") { Task { await model.refresh() } }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SpendingView()
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .task { if model.hasToken && model.budgets.isEmpty { await model.refresh() } }
    }
}

private struct SpendingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let summary = model.summary

        VStack(alignment: .leading, spacing: 0) {
            if let summary {
                StatsRow(summary: summary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                Divider().padding(.top, 14)
                if summary.isEmpty {
                    ContentUnavailableView("No spending in \(model.selectedPeriod?.title ?? "this period")",
                                           systemImage: "chart.bar.xaxis")
                } else {
                    SankeyView(graph: summary.sankeyGraph(options: SankeyOptions(showCategories: model.showCategories)),
                               format: model.format,
                               total: max(summary.totalIncome, summary.totalSpending), zoom: $model.zoom)
                        .padding(12)
                }
            }
        }
        .navigationTitle(model.selectedBudget?.name ?? "YNAB Sankey")
        .navigationSubtitle(model.selectedPeriod?.title ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.canStep(-1))
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .help("Previous \(model.granularity.rawValue.lowercased())")
                Picker("Period", selection: $model.selectedPeriod) {
                    ForEach(model.periods.reversed(), id: \.self) { p in
                        Text(p.title).tag(Optional(p))
                    }
                }
                .frame(width: 160)
                Button { model.step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canStep(1))
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .help("Next \(model.granularity.rawValue.lowercased())")
            }
            ToolbarItemGroup {
                Picker("View by", selection: $model.granularity) {
                    ForEach(AppModel.Granularity.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                ControlGroup {
                    Button { model.zoom(by: 1 / 1.25) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                        .disabled(model.zoom <= SankeyView.zoomRange.lowerBound)
                        .help("Zoom out (⌘-)")
                    Button { model.zoom = 1 } label: {
                        Text("\(Int((model.zoom * 100).rounded()))%").monospacedDigit()
                    }
                    .help("Actual size (⌘0)")
                    Button { model.zoom(by: 1.25) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                        .disabled(model.zoom >= SankeyView.zoomRange.upperBound)
                        .help("Zoom in (⌘=), or pinch on the trackpad")
                }
                Toggle(isOn: $model.showCategories) {
                    Label("Categories", systemImage: "list.bullet.indent")
                }
                .help("Show individual categories as well as category groups")
                if model.budgets.count > 1 {
                    Picker("Budget", selection: $model.selectedBudgetId) {
                        ForEach(model.budgets) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Button { Task { await model.refresh() } } label: {
                    if model.isLoading { ProgressView().controlSize(.small) }
                    else { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .keyboardShortcut("r")
                .disabled(model.isLoading)
                .help("Reload from YNAB")
            }
        }
        .overlay(alignment: .bottom) {
            if let error = model.errorMessage {
                Text(error)
                    .padding(10)
                    .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .onTapGesture { model.errorMessage = nil }
            }
        }
    }
}

private struct StatsRow: View {
    @Environment(AppModel.self) private var model
    let summary: PeriodSummary

    var body: some View {
        let income = summary.totalIncome, spent = summary.totalSpending
        let net = income - spent
        HStack(spacing: 32) {
            Stat(title: "Income", value: model.format(income))
            Stat(title: "Spending", value: model.format(spent))
            Stat(title: net >= 0 ? "Saved" : "Overspent", value: model.format(abs(net)),
                 tint: net >= 0 ? .green : .red)
            if income > 0 {
                Stat(title: "Savings rate",
                     value: (Double(net) / Double(income)).formatted(.percent.precision(.fractionLength(0))))
            }
            Spacer()
        }
    }
}

private struct Stat: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
        }
    }
}

struct TokenSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to YNAB").font(.largeTitle.weight(.semibold))
            Text("Paste a YNAB Personal Access Token. Create one in YNAB under Account Settings → Developer Settings → New Token. It's stored in your macOS Keychain and only used to read your budget.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Personal Access Token", text: $token)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Button("Connect", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || model.isLoading)
                if model.isLoading { ProgressView().controlSize(.small) }
                Link("Open YNAB Developer Settings",
                     destination: URL(string: "https://app.ynab.com/settings/developer")!)
                    .padding(.leading, 8)
            }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: 460)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        let value = token
        Task {
            await model.saveToken(value)
            if model.hasToken { token = "" }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Default budget", selection: $model.defaultBudgetId) {
                Text("Most recently edited in YNAB").tag(String?.none)
                if !model.budgets.isEmpty { Divider() }
                ForEach(model.budgets) { Text($0.name).tag(Optional($0.id)) }
                // Keep a saved default selectable even if it's not in the list right now.
                if let id = model.defaultBudgetId, !model.budgets.contains(where: { $0.id == id }) {
                    Text("Unavailable budget").tag(Optional(id))
                }
            }
            .disabled(!model.hasToken)
            Text("The budget YNAB Sankey opens with. Switching budgets in the toolbar only lasts until you quit.")
                .font(.caption).foregroundStyle(.secondary)

            Divider().padding(.vertical, 6)

            LabeledContent("YNAB token") {
                if model.hasToken {
                    Button("Disconnect…", role: .destructive) { model.forgetToken() }
                } else {
                    Text("Not connected").foregroundStyle(.secondary)
                }
            }
            Text("Disconnecting removes the token from your Keychain. You can reconnect with a new token from the main window.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
