import CADCore

/// Original analytic direction gauges with their collapsed metric factors removed.
struct SurfaceSilhouetteAnalyticNormalTaylor {
    static func normal(of surface: Surface3D, over box: SurfaceParameterBox,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet? {
        typealias Scalar = SurfaceAreaIntervalTaylorScalarJet
        typealias Vector = SurfaceAreaIntervalTaylorVectorJet
        guard case .analytic(let source) = surface else { return nil }
        switch source {
        case .sphere:
            return try SurfaceSilhouetteAnalyticTaylor.sphereDirection(over: box,
                tolerance: tolerance, order: 3, using: &execution)
        case .cone:
            let unit = try ScalarInterval(lower: 1, upper: 1)
            guard let original = try SurfaceSilhouetteAnalyticTaylor.surface(surface,
                over: SurfaceParameterBox(u: box.u, v: unit), tolerance: tolerance, order: 4,
                using: &execution) else {
                throw GeometryConversionError.invalidInput("Original cone silhouette lost its native linear-V law.")
            }
            let factored = try original.differentiated(alongU: true, using: &execution)
                .cross(original.differentiated(alongU: false, using: &execution), using: &execution)
            func independentV(_ original: Scalar) throws -> Scalar {
                var result = try Scalar(order: 3, tolerance: tolerance, using: &execution)
                for u in 0...3 {
                    try execution.consumeWork(1); try result.set(original.coefficient(u, 0), u, 0)
                }
                return result
            }
            return try Vector(x: independentV(factored.x), y: independentV(factored.y), z: independentV(factored.z))
        default: return nil
        }
    }
}
