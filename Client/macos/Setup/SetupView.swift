import SwiftUI

// The setup assistant. At first launch it walks through its steps in order and nothing else of the app
// runs until the last one; reopened from "Setup…" it shows the same steps, all reachable directly.
struct SetupView: View {
    @ObservedObject var checks: SetupChecks
    @ObservedObject var model: HeadphonesModel
    @ObservedObject var settings: AppSettings
    let showError: (String) -> Void
    let finish: () -> Void
    @State private var flow: SetupFlow

    init(checks: SetupChecks, model: HeadphonesModel, settings: AppSettings, revisiting: Bool,
         showError: @escaping (String) -> Void, finish: @escaping () -> Void) {
        self.checks = checks
        self.model = model
        self.settings = settings
        self.showError = showError
        self.finish = finish
        _flow = State(initialValue: SetupFlow(mode: settings.usageMode, revisiting: revisiting))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                header
                stepContent
                Spacer(minLength: 0)
                buttons
            }
            .padding(24)
            .frame(width: 560, alignment: .topLeading)
        }
        .frame(height: 520)
        .onChange(of: settings.usageMode) { mode in flow.setMode(mode) }
        .animation(.easeInOut(duration: 0.2), value: flow.current)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(flow.steps, id: \.self) { step in
                let isCurrent = step == flow.current
                let label = HStack(spacing: 8) {
                    Image(systemName: isCurrent ? "circle.inset.filled" : "circle")
                        .font(.system(size: 9))
                        .foregroundColor(isCurrent ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                    Text(Self.title(step)).fontWeight(isCurrent ? .semibold : .regular)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())

                if flow.revisiting {
                    Button { flow.go(to: step) } label: { label }.buttonStyle(.plain)
                } else {
                    label.foregroundColor(isCurrent ? .primary : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 160, alignment: .topLeading)
        .padding(.vertical, 18)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(flow.revisiting ? Self.title(flow.current) : tr("Welcome to Overhead"))
                    .font(.title2.weight(.semibold))
                if !flow.revisiting {
                    Text(tr("A few permissions and your headphones, and you're set."))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.current {
        case .mode:
            ModeStepView(settings: settings)
        case .permissions:
            PermissionsStepView(checks: checks, model: model, settings: settings)
        case .notch, .headphones:
            Text(tr("Coming next."))
        case .done:
            DoneStepView(settings: settings, showError: showError)
        }
    }

    private var buttons: some View {
        HStack {
            if flow.revisiting {
                Text(tr("You can open this window again with Setup… in the Overhead menu."))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Button(tr("Done"), action: finish).keyboardShortcut(.defaultAction)
            } else {
                Button(tr("Back")) { flow.goBack() }.disabled(flow.isFirstStep)
                Spacer()
                if flow.isLastStep {
                    Button(tr("Start using Overhead"), action: finish).keyboardShortcut(.defaultAction)
                } else {
                    Button(tr("Next")) { flow.goNext() }.keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private static func title(_ step: SetupStep) -> String {
        switch step {
        case .mode: return tr("Mode")
        case .permissions: return tr("Permissions")
        case .notch: return tr("Notch")
        case .headphones: return tr("Headphones")
        case .done: return tr("Finish")
        }
    }
}
