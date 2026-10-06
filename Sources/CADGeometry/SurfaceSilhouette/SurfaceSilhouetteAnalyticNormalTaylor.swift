import CADCore

/// Original analytic direction gauges with their collapsed metric factors removed.
struct SurfaceSilhouetteAnalyticNormalTaylor {
    static func normal(of surface: Surface3D, over box: SurfaceParameterBox,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet? {
        typealias Scalar = SurfaceAreaIntervalTaylorScalarJet
        typealias Vector = SurfaceAreaIntervalTaylorVectorJet
        guard case .analytic(let source) = surface else { return nil }
        switch source {
        case .sphere:
            return try SurfaceSilhouetteAnalyticTaylor.sphereDirection(over: box,
                tolerance: tolerance, order: 3, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .cone:
            let unit = try ScalarInterval(lower: 1, upper: 1)
            guard let original = try SurfaceSilhouetteAnalyticTaylor.surface(surface,
                over: SurfaceParameterBox(u: box.u, v: unit), tolerance: tolerance, order: 4,
                consumeWork: consumeWork, consumeStorage: consumeStorage) else {
                throw GeometryConversionError.invalidInput("Original cone silhouette lost its native linear-V law.")
            }
            let factored = try original.differentiated(alongU: true, consumeWork: consumeWork, consumeStorage: consumeStorage)
                .cross(original.differentiated(alongU: false, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
            func independentV(_ original: Scalar) throws -> Scalar {
                var result = try Scalar(order: 3, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
                for u in 0...3 {
                    try consumeWork(); try result.set(original.coefficient(u, 0), u, 0)
                }
                return result
            }
            return try Vector(x: independentV(factored.x), y: independentV(factored.y), z: independentV(factored.z))
        default: return nil
        }
    }
}
