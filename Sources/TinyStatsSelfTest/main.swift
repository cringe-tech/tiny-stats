import Foundation
import Darwin
import TinyStatsCore
import SMCKit

// `--live`: sample the real engine once (incl. SMC sensors) and print it, to verify
// the whole pipeline against system tools. Default: run the offline math checks.
if CommandLine.arguments.contains("--live") {
    let engine = MetricsEngine()
    engine.setIncludeSensors(true)
    engine.setIncludeProcesses(true)
    engine.start(interval: 1)
    var count = 0
    for await snap in engine.snapshots {
        count += 1
        guard count >= 2 else { continue }  // second tick has deltas populated
        print(String(format: "CPU total: %.1f%%  (user %.1f / sys %.1f) cores: %d",
                     snap.cpu.total * 100, snap.cpu.user * 100, snap.cpu.system * 100, snap.cpu.perCore.count))
        print(String(format: "GPU: %.1f%%", snap.gpu.utilization * 100))
        print("Memory: \(snap.memory.usedBytes / 1_048_576) / \(snap.memory.totalBytes / 1_048_576) MiB")
        print(String(format: "Net: down %.0f KB/s  up %.0f KB/s",
                     snap.network.downloadBytesPerSec / 1024, snap.network.uploadBytesPerSec / 1024))
        print("Disk: \(snap.disk.freeBytes / 1_073_741_824) GiB free of \(snap.disk.totalBytes / 1_073_741_824) GiB")
        if let b = snap.battery {
            print(String(format: "Battery: %.0f%% charging=%@ plugged=%@ cycles=%@",
                         b.charge * 100, "\(b.isCharging)", "\(b.isPluggedIn)", b.cycleCount.map(String.init) ?? "?"))
        } else {
            print("Battery: none")
        }
        for cat in SensorCategory.allCases {
            let items = snap.sensors.filter { $0.category == cat }
            let sample = items.prefix(4).map { "\($0.name)=\(String(format: "%.1f", $0.value))" }.joined(separator: " ")
            print("Sensors[\(cat.rawValue)]: \(items.count)  \(sample)")
        }
        print("Processes: \(snap.processes.count) total")
        let topCPU = snap.processes.sorted { $0.cpu > $1.cpu }.prefix(5)
        for p in topCPU {
            print(String(format: "  cpu %.1f%%  mem %4llu MB  %@",
                         p.cpu * 100, p.memoryBytes / 1_048_576, p.name))
        }
        break
    }
    exit(0)
}

if CommandLine.arguments.contains("--smc") {
    guard let smc = SMCConnection() else {
        print("SMCConnection: FAILED to open AppleSMC")
        exit(1)
    }
    print("SMCConnection: opened")
    let count = smc.keyCount()
    print("keyCount (#KEY): \(count)")
    let keys = smc.allKeys()
    print("enumerated keys: \(keys.count)")
    print("first 30: \(keys.prefix(30).joined(separator: " "))")
    // Show raw reads for a sampling of T/F/V/I/P keys.
    let probe = keys.filter { "TFVIP".contains($0.first ?? " ") }.prefix(20)
    for k in probe {
        if let v = smc.read(k) {
            print(String(format: "  %@  type=%-4@ bytes=%@ -> %@", k, v.type,
                         v.bytes.map { String(format: "%02x", $0) }.joined(),
                         v.double.map { String(format: "%.3f", $0) } ?? "nil"))
        } else {
            print("  \(k)  read FAILED")
        }
    }
    exit(0)
}

// Minimal self-test runner — no XCTest/Testing needed, so it runs with the
// Command Line Tools toolchain alone. Exits non-zero on the first failure.

var failures = 0

@MainActor
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✔ \(message)")
    } else {
        print("  ✘ \(message)")
        failures += 1
    }
}

func approx(_ a: Double, _ b: Double, _ eps: Double = 0.001) -> Bool { abs(a - b) < eps }

func makeLoad(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) -> host_cpu_load_info {
    var info = host_cpu_load_info()
    info.cpu_ticks.0 = user
    info.cpu_ticks.1 = system
    info.cpu_ticks.2 = idle
    info.cpu_ticks.3 = nice
    return info
}

print("CPU usage:")
do {
    let usage = CPUCollector.usage(
        previous: [makeLoad(user: 0, system: 0, idle: 0, nice: 0)],
        current: [makeLoad(user: 25, system: 25, idle: 50, nice: 0)])
    check(approx(usage.total, 0.5), "50% busy")
    check(approx(usage.user, 0.25), "25% user")
    check(approx(usage.system, 0.25), "25% system")
    check(approx(usage.perCore.first ?? -1, 0.5), "per-core 50%")
}
do {
    let usage = CPUCollector.usage(
        previous: [makeLoad(user: 100, system: 50, idle: 1000, nice: 0)],
        current: [makeLoad(user: 100, system: 50, idle: 1100, nice: 0)])
    check(approx(usage.total, 0), "fully idle -> 0%")
    check(approx(usage.idle, 1.0), "idle 100%")
}
check(CPUCollector.usage(previous: [], current: [makeLoad(user: 1, system: 1, idle: 1, nice: 0)]).total == 0,
      "mismatched counts -> safe 0")

print("Network rate:")
do {
    let usage = NetworkCollector.rate(
        previousIn: 0, previousOut: 0,
        currentIn: 1024 * 1024, currentOut: 512 * 1024, seconds: 2)
    check(approx(usage.downloadBytesPerSec, 524288, 1), "1 MiB / 2s = 512 KiB/s down")
    check(approx(usage.uploadBytesPerSec, 262144, 1), "512 KiB / 2s = 256 KiB/s up")
}
do {
    let usage = NetworkCollector.rate(
        previousIn: 5000, previousOut: 5000,
        currentIn: 100, currentOut: 100, seconds: 1)
    check(usage.downloadBytesPerSec == 0, "counter reset clamps down to 0")
    check(usage.uploadBytesPerSec == 0, "counter reset clamps up to 0")
}

print("Sensor classification (Apple Silicon):")
do {
    func comp(_ key: String) -> TempComponent? {
        SensorClassifier.component(forKey: key, arch: .appleSilicon)
    }
    check(comp("Tp01") == .cpu, "Tp01 -> CPU")
    check(comp("Te05") == .cpu, "Te05 -> CPU")
    check(comp("TC10") == .cpu, "TC10 -> CPU")
    check(comp("Tg05") == .gpu, "Tg05 -> GPU")
    check(comp("Tm02") == .memory, "Tm02 -> Memory")
    check(comp("TPD0") == .power, "TPD0 -> Power (case-sensitive vs Tp)")
    check(comp("TW0P") == nil, "TW0P (airport) -> unclassified")
}

print("Sensor classification (Intel):")
do {
    func comp(_ key: String) -> TempComponent? {
        SensorClassifier.component(forKey: key, arch: .intel)
    }
    check(comp("TC0P") == .cpu, "TC0P -> CPU")
    check(comp("TG0P") == .gpu, "TG0P -> GPU")
    check(comp("TM0P") == .memory, "TM0P -> Memory")
}

print("Power names (self-authored):")
do {
    check(PowerNames.name(forKey: "PSTR") == "System total", "power PSTR -> System total")
    check(PowerNames.name(forKey: "PPBR") == "Battery", "power PPBR -> Battery")
    check(PowerNames.name(forKey: "PHPB") == nil, "unknown power key -> nil")
}

print("Version compare:")
do {
    check(UpdateChecker.isNewer("0.2.0", than: "0.1.0"), "0.2.0 > 0.1.0")
    check(!UpdateChecker.isNewer("0.1.0", than: "0.1.0"), "0.1.0 == 0.1.0 -> not newer")
    check(UpdateChecker.isNewer("1.0.0", than: "0.9.9"), "1.0.0 > 0.9.9")
    check(UpdateChecker.isNewer("0.10.0", than: "0.9.0"), "0.10.0 > 0.9.0 (numeric, not lexical)")
    check(!UpdateChecker.isNewer("0.1.0", than: "0.2.0"), "0.1.0 < 0.2.0")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
