import SwiftUI

// Building blocks shared by the setup steps: the usage mode cards and the checklist rows.

// One way of using Overhead, picked by clicking the card.
struct ModeCard: View {
    let mode: UsageMode
    let icon: String
    let title: String
    let detail: String
    @Binding var selection: UsageMode

    var body: some View {
        let selected = selection == mode
        Button { selection = mode } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon).font(.system(size: 18)).foregroundColor(.accentColor)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                }
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SetupRow<Action: View>: View {
    let icon: String
    let title: String
    let detail: String
    let done: Bool
    var optional = false
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(.medium)
                    if optional { Text(tr("Optional")).font(.caption).foregroundColor(.secondary) }
                }
                Text(detail).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(done ? .green : Color(nsColor: .tertiaryLabelColor))
                .accessibilityLabel(done ? tr("Done") : tr("To do"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
