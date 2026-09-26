import SwiftUI

enum Palette {
    static let groups: [Color] = [
        Color(red: 0.26, green: 0.52, blue: 0.96), // blue
        Color(red: 0.93, green: 0.45, blue: 0.20), // orange
        Color(red: 0.62, green: 0.38, blue: 0.86), // purple
        Color(red: 0.90, green: 0.30, blue: 0.45), // rose
        Color(red: 0.16, green: 0.66, blue: 0.70), // teal
        Color(red: 0.85, green: 0.65, blue: 0.13), // amber
        Color(red: 0.45, green: 0.55, blue: 0.25), // olive
        Color(red: 0.55, green: 0.40, blue: 0.30), // brown
        Color(red: 0.35, green: 0.40, blue: 0.75), // indigo
        Color(red: 0.80, green: 0.40, blue: 0.70), // pink
    ]

    static func color(for tint: SankeyNode.Tint) -> Color {
        switch tint {
        case .income: Color(red: 0.20, green: 0.65, blue: 0.38)
        case .budget: Color.gray
        case .saved: Color(red: 0.12, green: 0.55, blue: 0.45)
        case .reserves: Color(red: 0.80, green: 0.35, blue: 0.25)
        case .group(let i): groups[i % groups.count]
        }
    }
}

/// Fits the chart to the window at 100%; zooming in enlarges the canvas
/// (labels stay the same size, so crowded ones get room) and it scrolls.
struct SankeyView: View {
    let graph: SankeyGraph
    let format: (Milliunits) -> String
    let total: Milliunits
    @Binding var zoom: CGFloat

    @State private var pinchStart: CGFloat?

    static let zoomRange: ClosedRange<CGFloat> = 1...4

    var body: some View {
        GeometryReader { viewport in
            let size = CGSize(width: viewport.size.width * zoom, height: viewport.size.height * zoom)
            ScrollView([.horizontal, .vertical]) {
                SankeyChart(graph: graph, format: format, total: total)
                    .frame(width: size.width, height: size.height)
            }
            .scrollDisabled(zoom <= 1)
            .gesture(MagnifyGesture()
                .onChanged { value in
                    let start = pinchStart ?? zoom
                    pinchStart = start
                    zoom = min(max(start * value.magnification, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
                }
                .onEnded { _ in pinchStart = nil })
        }
    }
}

/// The Sankey itself, drawn to fill whatever frame it's given.
struct SankeyChart: View {
    let graph: SankeyGraph
    let format: (Milliunits) -> String
    let total: Milliunits // denominator for percentages (the budget node's value)

    @State private var hover: CGPoint?

    private enum Hit: Equatable { case node(Int), link(Int) }

    var body: some View {
        GeometryReader { geo in chart(size: geo.size) }
    }

    private func chart(size: CGSize) -> some View {
        let layout = SankeyLayout(graph: graph, size: size, metrics: metrics(width: size.width))
        let hit = hover.flatMap { hitTest($0, layout) }
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in draw(in: &ctx, layout: layout, hit: hit) }
            if let hit, let hover {
                tooltip(for: hit, layout: layout)
                    .fixedSize()
                    .offset(tooltipOffset(hover, in: size))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): hover = p
            case .ended: hover = nil
            }
        }
    }

    /// Side margins wide enough for the longest label in the first and last columns.
    private func metrics(width chartWidth: CGFloat) -> SankeyLayout.Metrics {
        var m = SankeyLayout.Metrics()
        let lastColumn = graph.nodes.map(\.column).max() ?? 0
        var inflow = [Milliunits](repeating: 0, count: graph.nodes.count), outflow = inflow
        for l in graph.links { outflow[l.source] += l.value; inflow[l.target] += l.value }
        func width(_ i: Int) -> CGFloat {
            let label = "\(graph.nodes[i].label)  \(format(max(inflow[i], outflow[i])))"
            return (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
        }
        let left = graph.nodes.indices.filter { graph.nodes[$0].column == 0 }.map(width).max() ?? 0
        let right = graph.nodes.indices.filter { graph.nodes[$0].column == lastColumn }.map(width).max() ?? 0
        // Capped so one very long payee name can't squeeze the chart away (zoom in to read it).
        m.leftMargin = min(ceil(left) + 16, chartWidth * 0.3)
        m.rightMargin = min(ceil(right) + 16, chartWidth * 0.3)
        return m
    }

    // MARK: Drawing

    private func linkColor(_ link: SankeyLink) -> Color {
        // Colour a ribbon by whichever end carries the meaningful category.
        let target = graph.nodes[link.target]
        if case .budget = target.tint { return Palette.color(for: graph.nodes[link.source].tint) }
        return Palette.color(for: target.tint)
    }

    private func isRelated(_ linkIndex: Int, to hit: Hit?) -> Bool {
        guard let hit else { return false }
        let l = graph.links[linkIndex]
        switch hit {
        case .link(let i): return i == linkIndex
        case .node(let n): return l.source == n || l.target == n
        }
    }

    private func draw(in ctx: inout GraphicsContext, layout: SankeyLayout, hit: Hit?) {
        for placed in layout.links {
            let link = graph.links[placed.index]
            let related = isRelated(placed.index, to: hit)
            let opacity = hit == nil ? 0.35 : (related ? 0.65 : 0.12)
            ctx.fill(Path(placed.path), with: .color(linkColor(link).opacity(opacity)))
        }

        let lastColumn = graph.nodes.map(\.column).max() ?? 0
        var lastLabelY: [Int: CGFloat] = [:] // per column: bottom edge of the last label drawn
        for placed in layout.nodes {
            let node = graph.nodes[placed.index]
            let rect = placed.rect
            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Palette.color(for: node.tint)))

            // Label a node if there's vertical room left after the label above it.
            let emphasised = hit == .node(placed.index)
            let labelHeight: CGFloat = 14
            let top = max(rect.midY - labelHeight / 2, lastLabelY[node.column] ?? -.infinity)
            guard top + labelHeight / 2 <= rect.maxY + 3 || emphasised else { continue }
            lastLabelY[node.column] = top + labelHeight

            let amount = format(placed.value)
            let text = Text("\(Text(node.label).fontWeight(.medium))  \(Text(amount).foregroundStyle(.secondary))")
                .font(.system(size: rect.height >= 12 || node.column < 3 ? 12 : 10.5))
            let resolved = ctx.resolve(text)
            let textSize = resolved.measure(in: CGSize(width: 400, height: 40))

            let point: CGPoint, anchor: UnitPoint
            let y = emphasised ? rect.midY : top + labelHeight / 2
            if node.column == 0 {
                point = CGPoint(x: rect.minX - 6, y: y); anchor = .trailing
            } else {
                point = CGPoint(x: rect.maxX + 6, y: y); anchor = .leading
            }
            if node.column != 0 && node.column != lastColumn {
                // Labels over ribbons get a halo so they stay readable.
                let bg = CGRect(x: point.x - 3, y: point.y - textSize.height / 2 - 1,
                                width: textSize.width + 6, height: textSize.height + 2)
                ctx.fill(Path(roundedRect: bg, cornerRadius: 4),
                         with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.8)))
            }
            ctx.draw(resolved, at: point, anchor: anchor)
        }
    }

    // MARK: Hover

    private func hitTest(_ p: CGPoint, _ layout: SankeyLayout) -> Hit? {
        if let node = layout.nodes.first(where: { $0.rect.insetBy(dx: -3, dy: -1).contains(p) }) {
            return .node(node.index)
        }
        // Topmost (last drawn) ribbon wins.
        if let link = layout.links.last(where: { $0.path.contains(p) }) { return .link(link.index) }
        return nil
    }

    private func percent(_ v: Milliunits) -> String {
        guard total > 0 else { return "" }
        return (Double(v) / Double(total)).formatted(.percent.precision(.fractionLength(1)))
    }

    @ViewBuilder
    private func tooltip(for hit: Hit, layout: SankeyLayout) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch hit {
            case .node(let i):
                Text(graph.nodes[i].label).font(.headline)
                Text("\(format(layout.nodes[i].value)) · \(percent(layout.nodes[i].value))")
            case .link(let i):
                let l = graph.links[i]
                Text("\(graph.nodes[l.source].label) → \(graph.nodes[l.target].label)").font(.headline)
                Text("\(format(l.value)) · \(percent(l.value))")
            }
        }
        .font(.callout)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 3)
    }

    private func tooltipOffset(_ p: CGPoint, in size: CGSize) -> CGSize {
        let x = p.x > size.width - 280 ? p.x - 270 : p.x + 14
        let y = p.y > size.height - 70 ? p.y - 60 : p.y + 14
        return CGSize(width: x, height: y)
    }
}
