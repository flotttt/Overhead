import Foundation

// L'enchaînement des étapes de la configuration. Pur, sans interface: testé dans LogicTests, qui ne
// compile que des sources Foundation — ne rien importer d'autre ici.
// Les étapes dépendent du mode d'usage, qui se choisit à la première d'entre elles.
enum SetupStep: String, CaseIterable {
    case mode, permissions, notch, headphones, done
}

struct SetupFlow {
    // Onboarding: on avance avec Suivant. Révision (rouvert depuis Setup…): on clique l'étape voulue.
    let revisiting: Bool
    private(set) var steps: [SetupStep]
    private(set) var current: SetupStep

    init(mode: UsageMode, revisiting: Bool) {
        self.revisiting = revisiting
        steps = Self.steps(for: mode)
        current = steps[0]
    }

    static func steps(for mode: UsageMode) -> [SetupStep] {
        var steps: [SetupStep] = [.mode, .permissions]
        if mode.usesNotch { steps.append(.notch) }
        if mode.usesHeadphones { steps.append(.headphones) }
        steps.append(.done)
        return steps
    }

    var isFirstStep: Bool { current == steps.first }
    var isLastStep: Bool { current == steps.last }

    // Le mode change la liste. Si l'étape courante disparaît, on retombe sur la suivante encore présente.
    mutating func setMode(_ mode: UsageMode) {
        let previous = steps
        steps = Self.steps(for: mode)
        guard !steps.contains(current) else { return }
        let index = previous.firstIndex(of: current) ?? 0
        current = previous.dropFirst(index).first(where: { steps.contains($0) }) ?? steps[steps.count - 1]
    }

    mutating func goNext() {
        guard let index = steps.firstIndex(of: current), index + 1 < steps.count else { return }
        current = steps[index + 1]
    }

    mutating func goBack() {
        guard let index = steps.firstIndex(of: current), index > 0 else { return }
        current = steps[index - 1]
    }

    // Saut direct, autorisé seulement en révision. Retourne false si le saut est refusé.
    @discardableResult
    mutating func go(to step: SetupStep) -> Bool {
        guard revisiting, steps.contains(step) else { return false }
        current = step
        return true
    }
}
