import CADCore
import CADTopology

/// Explicit shell ownership at the stable-identity sewing boundary.
public enum BRepSewingBodyTopology: Equatable, Sendable {
    case solid(components: [BRepSewingSolidComponent])
    case sheet(shellStableIDs: [String])

    public var bodyKind: BodyKind {
        switch self {
        case .solid:
            .solid
        case .sheet:
            .sheet
        }
    }

    public var shellStableIDs: [String] {
        switch self {
        case .solid(let components):
            components.flatMap(\.shellStableIDs)
        case .sheet(let shellStableIDs):
            shellStableIDs
        }
    }

    func validate(
        shells: [BRepSewingShell],
        tolerance: ModelingTolerance
    ) throws {
        let declaredShellStableIDs = shellStableIDs
        let availableShellStableIDs = shells.map(\.stableID)
        guard declaredShellStableIDs.isEmpty == false,
              Set(declaredShellStableIDs).count == declaredShellStableIDs.count,
              Set(declaredShellStableIDs) == Set(availableShellStableIDs) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-rep sewing topology must own every shell exactly once."
            )
        }
        guard case .solid(let components) = self else {
            return
        }
        guard components.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Solid sewing requires at least one explicit material component."
            )
        }
        let shellsByStableID = Dictionary(uniqueKeysWithValues: shells.map {
            ($0.stableID, $0)
        })
        for component in components {
            guard component.outerShellStableID.isEmpty == false,
                  component.voidShellStableIDs.allSatisfy({ $0.isEmpty == false }),
                  shellsByStableID[component.outerShellStableID]?.orientation == .forward else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A sewing solid component requires one forward outer shell."
                )
            }
            guard component.voidShellStableIDs.allSatisfy({
                shellsByStableID[$0]?.orientation == .reversed
            }) else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Every sewing void shell must be reversed and explicitly owned by one component."
                )
            }
        }
    }
}
