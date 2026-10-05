import CADCore

extension SurfaceParameterCurve {
    /// Complete normalized value hull, without demanding higher join continuity.
    package func originalParameterBounds(over range: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil)
        throws -> SurfaceParameterBox {
        try validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: { _ in try consumeWork() }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        let value = try OriginalParameterCurveHigherTaylor.enclosure(self, over: range, order: 0,
            tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        let u = try value.u.coefficient(0, 0), v = try value.v.coefficient(0, 0)
        return try .init(u: .init(lower: u.lower, upper: u.upper), v: .init(lower: v.lower, upper: v.upper))
    }
}
