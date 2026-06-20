import SwiftUI
import TinyStatsCore
import SMCKit

struct SensorsView: View {
    let sensors: [SensorReading]
    let nerd: Bool
    var temperatureUnit: TemperatureUnit = .celsius

    /// Components shown (and ordered) in the temperature view.
    private let components: [TempComponent] = [.cpu, .memory, .gpu, .power]
    /// Non-temperature categories, in display order.
    private let otherCategories: [SensorCategory] = [.power, .voltage, .current]

    var body: some View {
        if sensors.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "sensor.fill").foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(Loc.t(.readingSensors))
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                fansSection
                if nerd { nerdTemperature } else { plainTemperature }
                ForEach(visibleOtherCategories, id: \.self) { category in
                    genericSection(category)
                }
            }
        }
    }

    // MARK: Temperature — plain (component averages only)

    /// One averaged row per component, fixed order, so the list never reshuffles.
    @ViewBuilder
    private var plainTemperature: some View {
        let rows = components.compactMap { comp -> (TempComponent, Double)? in
            guard let avg = componentAverage(comp) else { return nil }
            return (comp, avg)
        }
        if !rows.isEmpty {
            SectionHeader(title: "\(Loc.t(.temperature)) · \(rows.count)")
            ForEach(rows, id: \.0) { comp, value in
                sensorRow(name: componentName(comp),
                          value: Format.temperature(value, unit: temperatureUnit))
            }
        }
    }

    private func componentName(_ comp: TempComponent) -> String {
        switch comp {
        case .cpu: return Loc.t(.cpu)
        case .memory: return Loc.t(.memory)
        case .gpu: return Loc.t(.gpu)
        case .power: return Loc.t(.power)
        }
    }

    // MARK: Temperature — nerd (per component: average + named sensors)

    @ViewBuilder
    private var nerdTemperature: some View {
        let named = namedTemperatures()
        ForEach(components, id: \.rawValue) { comp in
            if let avg = componentAverage(comp) {
                let items = named[comp] ?? []
                SectionHeader(title: "\(componentName(comp)) · \(items.count)")
                sensorRow(name: Loc.t(.average),
                          value: Format.temperature(avg, unit: temperatureUnit),
                          emphasized: true)
                ForEach(items) { item in
                    sensorRow(name: item.name,
                              value: Format.temperature(item.reading.value, unit: temperatureUnit))
                }
            }
        }
        let system = namedSystem()
        if !system.isEmpty {
            SectionHeader(title: "\(Loc.t(.system)) · \(system.count)")
            ForEach(system) { item in
                sensorRow(name: item.name,
                          value: Format.temperature(item.reading.value, unit: temperatureUnit))
            }
        }
    }

    // MARK: Named-sensor grouping

    /// A temperature reading paired with its human-readable name.
    private struct NamedTemp: Identifiable {
        let reading: SensorReading
        let name: String
        var id: String { reading.key }
    }

    /// Temperature sensors grouped by component (via the prefix classifier), each group
    /// sorted by key. Individual sensors are labelled by their raw SMC key.
    private func namedTemperatures() -> [TempComponent: [NamedTemp]] {
        var map: [TempComponent: [NamedTemp]] = [:]
        for reading in sensors where reading.category == .temperature {
            guard let comp = SensorClassifier.component(forKey: reading.key) else { continue }
            map[comp, default: []].append(NamedTemp(reading: reading, name: reading.name))
        }
        for key in map.keys { map[key]?.sort { $0.name < $1.name } }
        return map
    }

    /// Temperature sensors that don't map to a compute component (battery, display, NAND,
    /// thunderbolt…), shown by their raw SMC key.
    private func namedSystem() -> [NamedTemp] {
        sensors
            .filter { $0.category == .temperature && SensorClassifier.component(forKey: $0.key) == nil }
            .map { NamedTemp(reading: $0, name: $0.name) }
            .sorted { $0.name < $1.name }
    }

    /// Average for a component: mean of all temperature sensors the classifier assigns to it.
    private func componentAverage(_ component: TempComponent) -> Double? {
        let prefixed = sensors.filter {
            $0.category == .temperature && SensorClassifier.component(forKey: $0.key) == component
        }
        return mean(prefixed)
    }

    // MARK: Other categories (fans / power / voltage / current)

    private var fansSection: some View {
        let fans = sensors.filter { $0.category == .fan }
        return Group {
            if !fans.isEmpty {
                SectionHeader(title: "\(Loc.t(.fans)) · \(fans.count)")
                ForEach(fans) { reading in
                    sensorRow(symbol: "fanblades", name: reading.name, value: formatted(reading))
                }
            }
        }
    }

    @ViewBuilder
    private func genericSection(_ category: SensorCategory) -> some View {
        if category == .power {
            powerSection
        } else {
            // Voltage / current (nerd only) — raw SMC keys.
            let items = sensors.filter { $0.category == category }
            if !items.isEmpty {
                SectionHeader(title: "\(title(for: category)) · \(items.count)")
                ForEach(items) { reading in
                    sensorRow(symbol: symbol(for: category), name: reading.name, value: formatted(reading))
                }
            }
        }
    }

    @ViewBuilder
    private var powerSection: some View {
        let rows = powerRows()
        if !rows.isEmpty {
            SectionHeader(title: "\(Loc.t(.power)) · \(rows.count)")
            ForEach(rows) { item in
                sensorRow(symbol: "bolt.fill", name: item.name, value: formatted(item.reading))
            }
        }
    }

    /// Power readings with human-readable names. Plain mode shows only the named
    /// (meaningful) ones; nerd mode also lists the rest under their raw key.
    private func powerRows() -> [NamedTemp] {
        sensors
            .filter { $0.category == .power }
            .compactMap { reading -> NamedTemp? in
                if let name = PowerNames.name(forKey: reading.key) {
                    return NamedTemp(reading: reading, name: name)
                }
                return nerd ? NamedTemp(reading: reading, name: reading.name) : nil
            }
            .sorted { $0.reading.value > $1.reading.value }
    }

    private var visibleOtherCategories: [SensorCategory] {
        nerd ? otherCategories : otherCategories.filter { $0 != .voltage && $0 != .current }
    }

    // MARK: Row + helpers

    private func sensorRow(symbol: String = "thermometer.medium",
                           name: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Image(systemName: symbol)
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(name)
                .font(.system(.subheadline, weight: emphasized ? .medium : .regular))
            Spacer()
            Text(value)
                .font(.system(.subheadline).monospacedDigit())
                .foregroundStyle(emphasized ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(value)")
    }

    private func mean(_ items: [SensorReading]) -> Double? {
        guard !items.isEmpty else { return nil }
        return items.map(\.value).reduce(0, +) / Double(items.count)
    }

    private func formatted(_ reading: SensorReading) -> String {
        reading.category == .temperature
            ? Format.temperature(reading.value, unit: temperatureUnit)
            : Format.value(reading.value, unit: reading.unit)
    }

    private func title(for category: SensorCategory) -> String {
        switch category {
        case .temperature: return Loc.t(.temperature)
        case .fan: return Loc.t(.fans)
        case .power: return Loc.t(.power)
        case .voltage: return Loc.t(.voltage)
        case .current: return Loc.t(.current)
        }
    }

    private func symbol(for category: SensorCategory) -> String {
        switch category {
        case .temperature: return "thermometer.medium"
        case .fan: return "fanblades"
        case .power: return "bolt.fill"
        case .voltage: return "powerplug"
        case .current: return "bolt.horizontal"
        }
    }
}
