import SwiftUI

/// A single metric line: symbol, title, trailing value, optional progress bar.
struct MetricRow: View {
    let symbol: String
    let title: String
    var value: String
    var fraction: Double? = nil
    var tint: Color = .accentColor
    var valueColor: Color = .secondary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(.body))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.system(.callout, weight: .medium))
                    Spacer()
                    Text(value)
                        .font(.system(.callout).monospacedDigit())
                        .foregroundStyle(valueColor)
                }
                if let fraction {
                    ProgressBar(fraction: fraction, tint: tint)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Thin rounded usage bar. Minimal, no animations to stay light.
struct ProgressBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 4)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}

/// Unified panel section header: icon + title on the left, optional tinted value
/// on the right. Shared by Overview and History so both tabs read the same.
struct SectionHeaderRow<Trailing: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.top, 4)
    }
}

extension SectionHeaderRow where Trailing == _SectionHeaderValue {
    /// Convenience for the common "single tinted value" trailing content.
    init(symbol: String, title: String, value: String, tint: Color = .secondary) {
        self.init(symbol: symbol, title: title) {
            _SectionHeaderValue(value: value, tint: tint)
        }
    }
}

struct _SectionHeaderValue: View {
    let value: String
    let tint: Color
    var body: some View {
        Text(value)
            .font(.system(.subheadline).monospacedDigit())
            .foregroundStyle(tint)
    }
}
