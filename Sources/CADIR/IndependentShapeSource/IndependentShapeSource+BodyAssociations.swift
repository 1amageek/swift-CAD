import CADCore
import CADGeometry

public extension IndependentShapeSource {
    /// A new graph edit's allowance; immutable original geometry was validated by its owner.
    func validateBodySourceAssociations(in graph: DesignGraph,
        limits: IndependentShapeSourceLimits = .standard,
        check: () throws -> Void = {}) throws {
        var execution = try IndependentShapeSourceExecutionOwner.execution(limits: limits)
        func validate(_ reference: IndependentShapeReference) throws {
            try CurrentTaskCancellationChecker().checkCancellation(); try check()
            try IndependentShapeSourceExecutionOwner.charge(work: 1, using: &execution)
            if case .body(let selector) = reference {
                try IndependentShapeBodySourceAuthority.validate(selector, in: graph) { records, work in
                    try IndependentShapeSourceExecutionOwner.charge(records: records, work: work, using: &execution)
                }
            }
        }
        for root in roots { try validate(root) }
        for representation in representations {
            try IndependentShapeSourceExecutionOwner.charge(work: 1, using: &execution)
            for member in representation.members { try validate(member) }
        }
        for group in groups {
            try IndependentShapeSourceExecutionOwner.charge(work: 1, using: &execution)
            for member in group.members { try validate(member) }
        }
        try CurrentTaskCancellationChecker().checkCancellation(); try check()
    }
}
