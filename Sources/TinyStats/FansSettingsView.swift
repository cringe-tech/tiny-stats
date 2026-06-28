import SwiftUI
import TinyStatsCore

/// Settings → Fans. Enables fan control (installing the privileged helper on first use behind a
/// risk disclaimer), picks a preset/curve and the driving sensor, and shows live fan state.
struct FansSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var showDisclaimer = false
    @State private var working = false
    @State private var errorText: String?

    private var settings: AppSettings { state.settings }
    private var fanStatus: FanControlStatus { state.fanStatus }

    var body: some View {
        Form {
            enableSection
            if let conflict = fanStatus.conflict {
                conflictWarning(conflict)
            }
            if settings.fanControlEnabled {
                fansSection
                controlSection
                if presetUsesSensor { sensorSection }
                if !HelperInstaller.isInstalled { helperWarningSection }
            } else if HelperInstaller.isInstalled {
                removeHelperSection
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshFanStatus() }
        .sheet(isPresented: $showDisclaimer) { disclaimerSheet }
    }

    // MARK: Enable

    private var enableSection: some View {
        Section {
            Toggle(isOn: enableBinding) {
                HStack(spacing: 8) {
                    Text(Loc.t(.enableFanControl))
                    experimentalBadge
                }
            }
            .disabled(working)
            Text(Loc.t(.fanControlHint))
                .font(.caption).foregroundStyle(.secondary)
            if working {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(Loc.t(.helperInstalling)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var experimentalBadge: some View {
        Text(Loc.t(.experimental).uppercased())
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(.orange)
    }

    /// Turning on routes through the disclaimer (first time) and helper install; turning off
    /// just disables (the helper stays installed for next time, removable below).
    private var enableBinding: Binding<Bool> {
        Binding(
            get: { settings.fanControlEnabled },
            set: { want in
                errorText = nil
                if want {
                    if !settings.fanControlAcknowledged { showDisclaimer = true }
                    else { Task { await ensureHelperThenEnable() } }
                } else {
                    setEnabled(false)
                }
            }
        )
    }

    private func ensureHelperThenEnable() async {
        if !HelperInstaller.isInstalled {
            working = true
            let result = await state.installFanHelper()
            working = false
            switch result {
            case .success:
                break
            case .failure(.cancelled):
                return                       // user dismissed the password prompt — stay off
            case .failure(let err):
                errorText = Loc.t(.fanInstallFailed, message(for: err))
                return
            }
        }
        setEnabled(true)
    }

    private func setEnabled(_ value: Bool) {
        var s = state.settings
        s.fanControlEnabled = value
        state.apply(s)
    }

    // MARK: Disclaimer

    private var disclaimerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(Loc.t(.fanRiskTitle), systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text(Loc.t(.fanRiskBody))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(Loc.t(.cancel)) { showDisclaimer = false }
                Button(Loc.t(.fanRiskAccept)) {
                    showDisclaimer = false
                    var s = state.settings
                    s.fanControlAcknowledged = true
                    state.apply(s)
                    Task { await ensureHelperThenEnable() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: Profile + curve (one panel, so the preset and its curve read together)

    private var controlSection: some View {
        Section(Loc.t(.fanProfile)) {
            Toggle(isOn: state.binding(\.fanTurboInGame)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t(.turboInGame))
                    Text(Loc.t(.turboInGameHint))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker(Loc.t(.fanProfile), selection: state.binding(\.fanPreset)) {
                ForEach(FanPreset.allCases) { Text(presetLabel($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            switch settings.fanPreset {
            case .auto:
                placeholder("gearshape.2.fill", Loc.t(.fanAutoExplain))
            case .turbo:
                placeholder("fanblades.fill", Loc.t(.fanTurboExplain))
            case .coolTouch, .balanced, .custom:
                FanCurveEditor(displayCurve: displayedCurve,
                               markerTempC: fanStatus.sourceTempC,
                               onCommit: commitCurve)
                    .frame(height: 180)
                    .padding(.vertical, 4)
                Text(settings.fanPreset == .custom ? Loc.t(.fanCurveHint) : Loc.t(.fanCurvePresetHint))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var presetUsesSensor: Bool {
        switch settings.fanPreset {
        case .auto, .turbo: return false
        case .coolTouch, .balanced, .custom: return true
        }
    }

    /// The curve to draw for the selected preset (its built-in shape, or the user's custom one).
    private var displayedCurve: FanCurve {
        if settings.fanPreset == .custom { return settings.fanCurve }
        return settings.fanPreset.builtInCurve ?? settings.fanCurve
    }

    /// Editing any preset's curve makes it the user's own — seed Custom from what they dragged.
    private func commitCurve(_ pts: [CurvePoint]) {
        var s = state.settings
        s.fanCurve = FanCurve(points: pts)
        if s.fanPreset != .custom { s.fanPreset = .custom }
        state.apply(s)
    }

    /// Stand-in shown instead of the curve when it isn't needed (Auto / Turbo). Sized to match
    /// the curve editor (180 + padding + hint row) so the panel height doesn't jump on switch.
    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text(text)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 212)
    }

    // MARK: Sensor source

    private var sensorSection: some View {
        Section(Loc.t(.fanSource)) {
            SensorSourcePicker(selection: state.binding(\.fanSensorSource))
                .padding(.vertical, 2)
            if let temp = fanStatus.sourceTempC {
                LabeledContent(sourceLabel(settings.fanSensorSource)) {
                    HStack(spacing: 6) {
                        Text(Format.temperature(temp, unit: settings.temperatureUnit.resolved))
                        if let pct = fanStatus.appliedPercent {
                            Text("→ \(Int(pct.rounded()))%").foregroundStyle(.secondary)
                        }
                    }
                    .monospacedDigit()
                }
            }
        }
    }

    // MARK: Live fan readout (own section, right under the enable toggle)

    private var fansSection: some View {
        Section(Loc.t(.fans)) {
            ForEach(fanStatus.fans) { fan in
                LabeledContent("Fan \(fan.index + 1)") {
                    Text("\(Int(fan.actualRPM.rounded())) RPM")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if fanStatus.fans.isEmpty {
                Text(Loc.t(.readingSensors))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Helper (shown only when it isn't running)

    private var helperWarningSection: some View {
        Section {
            HStack {
                Label(Loc.t(.helperNotRunning), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                Spacer()
                Button(Loc.t(.helperInstall)) {
                    Task {
                        working = true
                        _ = await state.installFanHelper()
                        working = false
                    }
                }
                .controlSize(.small)
                .disabled(working)
            }
        }
    }

    /// When fan control is off but the helper is still installed, offer to remove it.
    private var removeHelperSection: some View {
        Section {
            Button(Loc.t(.helperUninstall), role: .destructive) {
                Task {
                    working = true
                    _ = await state.uninstallFanHelper()
                    working = false
                }
            }
            .controlSize(.small)
            .disabled(working)
        }
    }

    private func conflictWarning(_ name: String) -> some View {
        Section {
            Label(Loc.t(.fanConflict, name), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: Labels

    private func presetLabel(_ p: FanPreset) -> String {
        switch p {
        case .auto: return Loc.t(.presetAuto)
        case .coolTouch: return Loc.t(.presetCoolTouch)
        case .balanced: return Loc.t(.presetBalanced)
        case .turbo: return Loc.t(.presetTurbo)
        case .custom: return Loc.t(.presetCustom)
        }
    }

    private func sourceLabel(_ s: FanSensorSource) -> String {
        switch s {
        case .cpu: return Loc.t(.cpu)
        case .gpu: return Loc.t(.gpu)
        case .powerBattery: return Loc.t(.sourcePower)
        }
    }

    private func message(for error: HelperError) -> String {
        switch error {
        case .helperMissing: return "helper binary not found in app bundle"
        case .cancelled: return "cancelled"
        case .failed(let m): return m
        }
    }
}

/// A richer alternative to a segmented control for choosing the driving sensor: three cards with
/// an icon and label that fill with the accent colour when selected.
private struct SensorSourcePicker: View {
    @Binding var selection: FanSensorSource

    private struct Option { let source: FanSensorSource; let symbol: String; let label: String }
    private var options: [Option] {
        [.init(source: .cpu, symbol: "cpu", label: Loc.t(.cpu)),
         .init(source: .gpu, symbol: "cpu.fill", label: Loc.t(.gpu)),
         .init(source: .powerBattery, symbol: "bolt.fill", label: Loc.t(.sourcePower))]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.source) { opt in
                card(opt)
            }
        }
    }

    private func card(_ opt: Option) -> some View {
        let selected = selection == opt.source
        return Button {
            if !selected { selection = opt.source; Haptic.tick() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: opt.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                Text(opt.label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.gray.opacity(0.12)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// Light haptic tick on selection, matching the rest of Settings.
    private enum Haptic {
        static func tick() {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
        }
    }
}
