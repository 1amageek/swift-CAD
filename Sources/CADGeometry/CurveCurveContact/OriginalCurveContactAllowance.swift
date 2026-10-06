import CADCore

/// One caller-owned ledger; preparing or querying another original chart does not reset it.
public struct OriginalCurveContactAllowance: Sendable {
    var budget: NativeCurveCurveContactBudget

    public var maximumAlgebraicDepth: Int { budget.maximumAlgebraicDepth }
    public var maximumSubdivisionDepth: Int { budget.maximumSubdivisionDepth }
    public var remainingSourceDepth: Int { budget.remainingSourceDepth }

    /// Admits visits to caller source/event entries as work units.
    public mutating func reserveEntries(_ count: Int) throws {
        try budget.work(count)
    }

    /// Reserves an original payload expressed in canonical UInt32 words.
    public mutating func reserveStorageWords(_ count: Int) throws {
        try budget.retainExactStorage(count)
    }

    /// Reserves a typed caller buffer before allocation or capacity growth.
    public mutating func reserveStorage<Entry>(_ count: Int, of type: Entry.Type) throws {
        try RationalAlgebraStorage.retain(count, of: type, usage: &budget)
    }

    public init(maximumSubdivisionDepth: Int = 32, maximumSubdivisionCells: Int = 1_048_576,
                maximumWork: Int = 1_048_576, tolerance: ModelingTolerance,
                admission: OriginalCurveContactAdmission? = nil,
                maximumAlgebraicDepth: Int = 32, remainingSourceDepth: Int = 32) throws {
        try tolerance.validate()
        budget = try NativeCurveCurveContactBudget(maximumDepth: maximumSubdivisionDepth,
            maximumCells: maximumSubdivisionCells, maximumWork: maximumWork, tolerance: tolerance,
            admission: admission, maximumAlgebraicDepth: maximumAlgebraicDepth,
            remainingSourceDepth: remainingSourceDepth)
    }
}
