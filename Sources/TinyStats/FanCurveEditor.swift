import SwiftUI
import TinyStatsCore

/// Interactive temperature→fan-speed curve. The X axis is temperature (°C), the Y axis is fan
/// speed (% of the fan's usable range). Drag the points to reshape it; the dashed marker shows
/// the live source temperature. Commits to the binding only when a drag ends, so dragging
/// doesn't spam settings persistence.
struct FanCurveEditor: View {
    /// The curve to display (a preset's built-in curve, or the user's custom one).
    let displayCurve: FanCurve
    var markerTempC: Double?
    /// Called once when a drag ends, with the new points. The parent decides what to do —
    /// e.g. switch the active preset to Custom and persist.
    let onCommit: ([CurvePoint]) -> Void

    @State private var points: [CurvePoint] = []
    @State private var dragging: Int?
    /// Last integer (temp,percent) we played a haptic tick for, so dragging ticks per step.
    @State private var lastTickKey = ""

    private let tempMin = 30.0
    private let tempMax = 100.0
    private let handle: CGFloat = 13

    // Gutters reserved for the axis labels, so the plot itself doesn't overlap them.
    private let leftGutter: CGFloat = 34
    private let bottomGutter: CGFloat = 18
    private let topPad: CGFloat = 16
    private let rightPad: CGFloat = 10

    /// Temperatures labelled along the X axis (also drawn as gridlines).
    private let xTicks: [Double] = [40, 50, 60, 70, 80, 90, 100]
    /// Fan-speed percentages labelled along the Y axis (also drawn as gridlines).
    private let yTicks: [Double] = [0, 50, 100]

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: leftGutter, y: topPad,
                              width: max(1, geo.size.width - leftGutter - rightPad),
                              height: max(1, geo.size.height - topPad - bottomGutter))
            ZStack(alignment: .topLeading) {
                grid(plot)
                axisLabels(plot)
                curveShape(plot)
                marker(plot)
                handles(plot)
                dragReadout(plot)
            }
        }
        .onAppear { points = displayCurve.points }
        .onChange(of: displayCurve) { _, new in
            if dragging == nil { points = new.points }   // adopt preset/external changes when idle
        }
    }

    // MARK: Geometry

    private func x(_ t: Double, _ plot: CGRect) -> CGFloat {
        plot.minX + CGFloat((t - tempMin) / (tempMax - tempMin)) * plot.width
    }
    private func y(_ p: Double, _ plot: CGRect) -> CGFloat {
        plot.minY + (1 - CGFloat(p / 100)) * plot.height
    }
    private func temp(_ px: CGFloat, _ plot: CGRect) -> Double {
        tempMin + Double(max(0, min(1, (px - plot.minX) / plot.width))) * (tempMax - tempMin)
    }
    private func percent(_ py: CGFloat, _ plot: CGRect) -> Double {
        Double(1 - max(0, min(1, (py - plot.minY) / plot.height))) * 100
    }

    // MARK: Layers

    private func grid(_ plot: CGRect) -> some View {
        ZStack {
            Path { p in
                for t in yTicks {                       // horizontal lines (fan %)
                    let yy = y(t, plot)
                    p.move(to: CGPoint(x: plot.minX, y: yy)); p.addLine(to: CGPoint(x: plot.maxX, y: yy))
                }
                for t in xTicks {                       // vertical lines (temperature)
                    let xx = x(t, plot)
                    p.move(to: CGPoint(x: xx, y: plot.minY)); p.addLine(to: CGPoint(x: xx, y: plot.maxY))
                }
            }
            .stroke(.quaternary, lineWidth: 0.5)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
                .frame(width: plot.width, height: plot.height)
                .position(x: plot.midX, y: plot.midY)
        }
    }

    private func axisLabels(_ plot: CGRect) -> some View {
        ZStack {
            // Y axis: fan speed (%) at left.
            ForEach(yTicks, id: \.self) { t in
                Text("\(Int(t))%")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .frame(width: leftGutter - 6, alignment: .trailing)
                    .position(x: (leftGutter - 6) / 2, y: y(t, plot))
            }
            // X axis: temperature (°C) along the bottom.
            ForEach(xTicks, id: \.self) { t in
                Text("\(Int(t))°")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .position(x: x(t, plot), y: plot.maxY + bottomGutter / 2 + 2)
            }
        }
    }

    /// The curve as the controller actually evaluates it (sampled across the width, so the flat
    /// clamped ends show correctly), filled below for a "fan speed" feel.
    private func curveShape(_ plot: CGRect) -> some View {
        let live = FanCurve(points: points)
        let step: CGFloat = 3
        var pts: [CGPoint] = []
        var xx = plot.minX
        while xx <= plot.maxX {
            pts.append(CGPoint(x: xx, y: y(live.percent(atTemp: temp(xx, plot)), plot)))
            xx += step
        }
        return ZStack {
            Path { p in
                guard let first = pts.first else { return }
                p.move(to: CGPoint(x: first.x, y: plot.maxY))
                p.addLine(to: first)
                for pt in pts.dropFirst() { p.addLine(to: pt) }
                if let last = pts.last { p.addLine(to: CGPoint(x: last.x, y: plot.maxY)) }
                p.closeSubpath()
            }
            .fill(Color.accentColor.opacity(0.12))
            Path { p in
                guard let first = pts.first else { return }
                p.move(to: first)
                for pt in pts.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }

    /// Dashed vertical line at the live source temperature, tagged with its value so it's clear
    /// what the line represents.
    @ViewBuilder
    private func marker(_ plot: CGRect) -> some View {
        if let t = markerTempC, t >= tempMin, t <= tempMax {
            let xx = x(t, plot)
            ZStack {
                Path { p in p.move(to: CGPoint(x: xx, y: plot.minY)); p.addLine(to: CGPoint(x: xx, y: plot.maxY)) }
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("\(Int(t.rounded()))°")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.orange, in: Capsule())
                    .position(x: min(max(xx, plot.minX + 12), plot.maxX - 12), y: plot.minY - topPad / 2 + 1)
            }
        }
    }

    private func handles(_ plot: CGRect) -> some View {
        ForEach(points.indices, id: \.self) { i in
            Circle()
                .fill(Color.accentColor)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: handle, height: handle)
                .scaleEffect(dragging == i ? 1.25 : 1)
                .position(x: x(points[i].tempC, plot), y: y(points[i].percent, plot))
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in dragPoint(i, to: value.location, plot) }
                        .onEnded { _ in
                            dragging = nil
                            onCommit(points)   // parent persists (and switches to Custom)
                        }
                )
                .animation(.easeOut(duration: 0.1), value: dragging)
        }
    }

    /// While dragging, show the active point's exact temperature/percent next to it.
    @ViewBuilder
    private func dragReadout(_ plot: CGRect) -> some View {
        if let i = dragging, points.indices.contains(i) {
            let pt = points[i]
            Text("\(Int(pt.tempC.rounded()))° · \(Int(pt.percent.rounded()))%")
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5))
                .position(x: min(max(x(pt.tempC, plot), plot.minX + 24), plot.maxX - 24),
                          y: max(plot.minY + 10, y(pt.percent, plot) - 16))
                .allowsHitTesting(false)
        }
    }

    /// Moves point `i`, keeping points monotonically ordered in temperature.
    private func dragPoint(_ i: Int, to loc: CGPoint, _ plot: CGRect) {
        dragging = i
        let lower = i == 0 ? tempMin : points[i - 1].tempC + 1
        let upper = i == points.count - 1 ? tempMax : points[i + 1].tempC - 1
        var t = temp(loc.x, plot)
        t = min(max(t, lower), upper)
        let p = min(100, max(0, percent(loc.y, plot)))
        points[i] = CurvePoint(tempC: t, percent: p)

        // Haptic tick whenever the rounded value steps, so dragging "ratchets" tactically.
        let key = "\(Int(t.rounded()))-\(Int(p.rounded()))"
        if key != lastTickKey {
            lastTickKey = key
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
