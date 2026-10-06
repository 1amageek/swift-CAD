import CADCore

extension SurfaceParameterCurve {
    /// Complete normalized value hull, without demanding higher join continuity.
    package func originalParameterBounds(on surface: Surface3D? = nil, over range: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil)
        throws -> SurfaceParameterBox {
        if let surface {
            try validateOriginalSource(on: surface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: { _ in try consumeWork() }, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        } else {
            try consumeWork(); try tolerance.validate()
            switch self {
            case .bSpline(let original):
                try original.validate(tolerance: tolerance, consumeWork: consumeWork)
            case .originalBSplineContinuation(let original):
                guard original.certificationTolerance == tolerance else {
                    throw GeometryConversionError.invalidInput("Original continuation query requires its retained tolerance.")
                }
                try original.original.validate(tolerance: tolerance, consumeWork: consumeWork)
            case .affine, .constantU, .constantV, .harmonic, .polyline:
                // These standalone 2D value producers validate their finite
                // original coefficient/point law without a surface relation.
                // The complete lower query below consumes this same allowance.
                break
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Standalone hosting-dependent
                // pcurve value callers must supply their actual retained support
                // before bounded original relation validation can authorize them.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original pcurve bounds require the actual hosting surface for this source relation.")
            }
        }
        let value = try OriginalParameterCurveHigherTaylor.enclosure(self, over: range, order: 0,
            tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        let u = try value.u.coefficient(0, 0), v = try value.v.coefficient(0, 0)
        return try .init(u: .init(lower: u.lower, upper: u.upper), v: .init(lower: v.lower, upper: v.upper))
    }
}
