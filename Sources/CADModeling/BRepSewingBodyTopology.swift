import CADCore
import CADGeometry
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
            components.flatMap { $0.shellStableIDs }
        case .sheet(let shellStableIDs):
            shellStableIDs
        }
    }

    func validate(
        shells: [BRepSewingShell],
        tolerance: ModelingTolerance
    ) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try validate(shells: shells, tolerance: tolerance, using: &execution)
    }

    func validate(
        shells: [BRepSewingShell],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        var declaredShellStableIDs: [String] = []
        switch self {
        case .sheet(let identifiers):
            declaredShellStableIDs = identifiers
        case .solid(let components):
            for component in components {
                try sewingAppend(component.outerShellStableID, to: &declaredShellStableIDs, using: &execution)
                for identifier in component.voidShellStableIDs {
                    try sewingAppend(identifier, to: &declaredShellStableIDs, using: &execution)
                }
            }
        }
        try execution.retainStorage(count: shells.count, stride: MemoryLayout<String>.stride)
        try execution.retainStorage(count: shells.count, stride: MemoryLayout<String>.stride)
        try execution.retainStorage(count: declaredShellStableIDs.count, stride: MemoryLayout<String>.stride)
        try execution.retainStorage(count: declaredShellStableIDs.count, stride: MemoryLayout<String>.stride)
        let availableShellStableIDs = shells.map { $0.stableID }
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
        try execution.retainStorage(count: shells.count, stride: MemoryLayout<(String,BRepSewingShell)>.stride)
        try execution.retainStorage(count: shells.count, stride: MemoryLayout<(String,BRepSewingShell)>.stride)
        let shellsByStableID = Dictionary(uniqueKeysWithValues: shells.map {
            ($0.stableID, $0)
        })
        for component in components {
            try execution.consumeWork(1)
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
