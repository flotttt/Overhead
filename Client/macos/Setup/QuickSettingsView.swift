import SwiftUI

// The short panel: what people rebind in ten seconds — the notch on or off, the way Overhead is used,
// and the permissions a macOS update can drop. The full assistant stays one click away.
struct QuickSettingsView: View {
    @ObservedObject var checks: SetupChecks
    @ObservedObject var model: HeadphonesModel
    @ObservedObject var settings: AppSettings
    let openFullSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(tr("Mode"), selection: $settings.usageMode) {
                Text(tr("Notch")).tag(UsageMode.notchOnly)
                Text(tr("Headphones")).tag(UsageMode.headphonesOnly)
                Text(tr("Both")).tag(UsageMode.both)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if settings.usageMode.usesNotch {
                Toggle(tr("Show Notch"), isOn: $settings.showNotch)
                    .toggleStyle(.switch)
            }

            // The same rows as the assistant's permissions step: one source, both places.
            PermissionsStepView(checks: checks, model: model, settings: settings)

            HStack {
                Spacer()
                Button(tr("Full setup…"), action: openFullSetup)
            }
        }
        .padding(20)
        .frame(width: 420)
        .animation(.easeInOut(duration: 0.2), value: settings.usageMode)
    }
}
