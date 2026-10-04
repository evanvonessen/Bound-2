import SwiftUI

/// Embed directly in a Form; no second source of truth or extra feedback generator.
struct BoundAppearanceSettings: View {
    @AppStorage(BoundAppearancePreferences.screenLayoutKey) private var screenLayoutRaw = BoundScreenLayout.delta.rawValue
    @AppStorage(BoundAppearancePreferences.themeKey) private var themeRaw = BoundTheme.delta.rawValue
    @AppStorage(Settings.Name.isButtonHapticFeedbackEnabled.rawValue) private var buttons = true
    @AppStorage(Settings.Name.isThumbstickHapticFeedbackEnabled.rawValue) private var sticks = true
    var body: some View {
        Section("Screen layout") {
            Picker("Screen arrangement", selection: Binding(get: {
                BoundScreenLayout(rawValue: screenLayoutRaw) ?? .delta
            }, set: { BoundAppearancePreferences().screenLayout = $0 })) {
                ForEach(BoundScreenLayout.allCases, id: \.rawValue) { layout in Text(layout.title).tag(layout) }
            }.accessibilityIdentifier("bound.screen-layout")
            Text("Delta Default preserves Delta's original screen geometry and shows the companion as PiP. Bound places the companion above gameplay in portrait and uses full-height gameplay with PiP in landscape.").font(.footnote).foregroundStyle(.secondary)
            Button("Reset screen layout to Delta Default") { BoundAppearancePreferences().resetScreenLayout() }.accessibilityIdentifier("bound.reset-screen-layout")
            Text("Changing or resetting screen layout keeps your button placements, theme, feedback and PiP preferences.").font(.footnote).foregroundStyle(.secondary)
        }
        Section("Appearance") {
            Picker("Theme", selection: Binding(get: {
                BoundTheme(rawValue: themeRaw) ?? .delta
            }, set: { BoundAppearancePreferences().theme = $0 })) {
                ForEach(BoundTheme.allCases, id: \.rawValue) { theme in Text(theme.title).tag(theme) }
            }.accessibilityIdentifier("bound.theme")
            Text("Delta Default keeps Delta's original artwork. Minimal uses simple controls and follows your device's light or dark appearance.").font(.footnote).foregroundStyle(.secondary)
        }
        Section {
            Toggle("Button feedback", isOn: Binding(get: { buttons }, set: { Settings.isButtonHapticFeedbackEnabled = $0 }))
                .accessibilityIdentifier("bound.button-haptics")
            Toggle("Control stick feedback", isOn: Binding(get: { sticks }, set: { Settings.isThumbstickHapticFeedbackEnabled = $0 }))
                .accessibilityIdentifier("bound.stick-haptics")
        } header: { Text("Touch feedback") } footer: {
            Text("Uses Delta's native touch feedback. Both are on by default. Physical controllers do not trigger touch feedback; this device may not support vibration.")
        }
        Section("About Bound 2") {
            LabeledContent("Version", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")")
            Text("Built on Delta. Delta and its emulator dependencies retain their original copyright and license notices.").font(.footnote).foregroundStyle(.secondary)
            Link("Delta source and license", destination: URL(string: "https://github.com/rileytestut/Delta")!)
        }
        Section {
            Button("Reset appearance and feedback to Delta defaults") {
                BoundAppearancePreferences().reset()
                Settings.isButtonHapticFeedbackEnabled = true
                Settings.isThumbstickHapticFeedbackEnabled = true
            }.accessibilityIdentifier("bound.reset-appearance")
        }
    }
}
