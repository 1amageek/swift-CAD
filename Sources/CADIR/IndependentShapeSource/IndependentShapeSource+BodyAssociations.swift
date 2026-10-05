import CADCore

public extension IndependentShapeSource {
    /// A new graph edit's allowance; immutable original geometry was validated by its owner.
    func validateBodySourceAssociations(in graph: DesignGraph,
        limits: IndependentShapeSourceLimits = .standard,
        check: () throws -> Void = {}) throws {
        var budget = try IndependentShapeSourceBudget(limits: limits)
        func validate(_ reference: IndependentShapeReference) throws {
            try CurrentTaskCancellationChecker().checkCancellation(); try check()
            try budget.charge(work: 1)
            if case .body(let selector) = reference {
                try IndependentShapeBodySourceAuthority.validate(selector, in: graph) { records, work in
                    try budget.charge(records: records, work: work)
                }
            }
        }
        for root in roots { try validate(root) }
        for representation in representations {
            try budget.charge(work: 1)
            for member in representation.members { try validate(member) }
        }
        for group in groups {
            try budget.charge(work: 1)
            for member in group.members { try validate(member) }
        }
        try CurrentTaskCancellationChecker().checkCancellation(); try check()
    }
}
