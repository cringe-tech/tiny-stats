import Foundation

/// Short, human-readable labels for the handful of well-known SMC power rails, so the Sensors
/// view can show "System total" instead of a raw `PSTR` key. The keys are factual SMC FourCCs;
/// the labels here are plain functional descriptions written for this project. Anything not in
/// this map is shown by its raw key (nerd mode only), so the list still adapts to new chips.
public enum PowerNames {
    public static func name(forKey key: String) -> String? { labels[key] }

    private static let labels: [String: String] = [
        "PSTR": "System total",
        "PMTR": "Memory total",
        "PPBR": "Battery",
        "PDTR": "DC in",
        "PDBR": "Display brightness",
        "PG0R": "GPU",
        "PCPC": "CPU package",
        "PCPG": "CPU graphics",
        "PCTR": "CPU total",
        "PU1R": "Thunderbolt left",
        "PU2R": "Thunderbolt right",
    ]
}
