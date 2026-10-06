import CADCore

/// Taylor coefficients of the authored endpoint correction polynomial.
package struct OriginalEndpointCorrectionTaylor {
    package static func jet(basis: OriginalEndpointCorrectionBasis, over parameters: ScalarInterval,
        throughOrder order: Int, tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorScalarJet {
        var t = try SurfaceAreaIntervalTaylorScalarJet.constant(
            .init(lower: parameters.lower, upper: parameters.upper), order: order, axis: .u,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        if order > 0 { try consumeWork(); try t.set(.exact(1), 1, 0) }
        var result = try SurfaceAreaIntervalTaylorScalarJet.constant(.exact(0), order: order, axis: .u,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        for power in (0...basis.degree).reversed() {
            result = try result.multiplied(by: t, consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(.constant(.exact(basis.coefficient(at: power)), order: order, axis: .u,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        return result
    }
}
