import CoreGraphics
import Foundation

struct SankeyLayout: Sendable {
    struct PlacedNode: Sendable {
        let index: Int
        let rect: CGRect
        let value: Milliunits
    }
    struct PlacedLink: Sendable {
        let index: Int
        let sourceY: ClosedRange<CGFloat> // along the source node's right edge
        let targetY: ClosedRange<CGFloat> // along the target node's left edge
        let x0: CGFloat
        let x1: CGFloat
    }

    let nodes: [PlacedNode]
    let links: [PlacedLink]

    struct Metrics: Sendable {
        var nodeWidth: CGFloat = 14
        var maxNodePadding: CGFloat = 14
        var leftMargin: CGFloat = 180
        var rightMargin: CGFloat = 240
        var verticalMargin: CGFloat = 16
    }

    init(graph: SankeyGraph, size: CGSize, metrics m: Metrics = Metrics()) {
        let n = graph.nodes.count
        guard n > 0, size.width > m.leftMargin + m.rightMargin, size.height > 2 * m.verticalMargin else {
            nodes = []; links = []; return
        }

        var inflow = [Milliunits](repeating: 0, count: n), outflow = inflow
        for l in graph.links {
            outflow[l.source] += l.value
            inflow[l.target] += l.value
        }
        let value = (0..<n).map { max(inflow[$0], outflow[$0]) }

        let columnCount = (graph.nodes.map(\.column).max() ?? 0) + 1
        var columns = [[Int]](repeating: [], count: columnCount)
        for (i, node) in graph.nodes.enumerated() { columns[node.column].append(i) }

        // Padding shrinks so the busiest column still leaves most room for flow.
        let height = size.height - 2 * m.verticalMargin
        let busiest = columns.map(\.count).max() ?? 1
        let padding = min(m.maxNodePadding, height * 0.3 / CGFloat(max(busiest - 1, 1)))

        // One scale (points per milliunit) for every column: the tightest one wins.
        var scale = CGFloat.greatestFiniteMagnitude
        for col in columns where !col.isEmpty {
            let total = CGFloat(col.reduce(0) { $0 + value[$1] })
            guard total > 0 else { continue }
            scale = min(scale, (height - padding * CGFloat(col.count - 1)) / total)
        }
        if scale == .greatestFiniteMagnitude { scale = 0 }

        let usableWidth = size.width - m.leftMargin - m.rightMargin - m.nodeWidth
        var rects = [CGRect](repeating: .zero, count: n)
        for (c, col) in columns.enumerated() {
            let x = m.leftMargin + (columnCount > 1 ? usableWidth * CGFloat(c) / CGFloat(columnCount - 1) : 0)
            // Top-aligned rather than centred, so each group's categories sit level
            // with it and the "Saved" node at the bottom doesn't get crossed.
            var y = m.verticalMargin
            for i in col {
                let h = CGFloat(value[i]) * scale
                rects[i] = CGRect(x: x, y: y, width: m.nodeWidth, height: h)
                y += h + padding
            }
        }

        // Stack each node's ribbons in the order of the node at the other end,
        // which keeps ribbons from crossing where they meet a node.
        var sourceY = [ClosedRange<CGFloat>](repeating: 0...0, count: graph.links.count)
        var targetY = sourceY
        for i in 0..<n {
            var y = rects[i].minY
            let outgoing = graph.links.indices.filter { graph.links[$0].source == i }
                .sorted { rects[graph.links[$0].target].midY < rects[graph.links[$1].target].midY }
            for li in outgoing {
                let h = CGFloat(graph.links[li].value) * scale
                sourceY[li] = y...(y + h)
                y += h
            }
            y = rects[i].minY
            let incoming = graph.links.indices.filter { graph.links[$0].target == i }
                .sorted { rects[graph.links[$0].source].midY < rects[graph.links[$1].source].midY }
            for li in incoming {
                let h = CGFloat(graph.links[li].value) * scale
                targetY[li] = y...(y + h)
                y += h
            }
        }

        nodes = (0..<n).map { PlacedNode(index: $0, rect: rects[$0], value: value[$0]) }
        links = graph.links.indices.map { li in
            PlacedLink(index: li, sourceY: sourceY[li], targetY: targetY[li],
                       x0: rects[graph.links[li].source].maxX, x1: rects[graph.links[li].target].minX)
        }
    }
}

extension SankeyLayout.PlacedLink {
    /// A ribbon with horizontal tangents at both ends.
    var path: CGPath {
        let p = CGMutablePath()
        let xm = (x0 + x1) / 2
        p.move(to: CGPoint(x: x0, y: sourceY.lowerBound))
        p.addCurve(to: CGPoint(x: x1, y: targetY.lowerBound),
                   control1: CGPoint(x: xm, y: sourceY.lowerBound),
                   control2: CGPoint(x: xm, y: targetY.lowerBound))
        p.addLine(to: CGPoint(x: x1, y: targetY.upperBound))
        p.addCurve(to: CGPoint(x: x0, y: sourceY.upperBound),
                   control1: CGPoint(x: xm, y: targetY.upperBound),
                   control2: CGPoint(x: xm, y: sourceY.upperBound))
        p.closeSubpath()
        return p
    }
}
