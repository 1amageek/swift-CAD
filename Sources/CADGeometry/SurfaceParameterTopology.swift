import CADCore

/// Topological properties of a surface parameter chart.
///
/// Geometry owns chart periodicity and parameter singularities. Consumers in
/// topology and modeling use this value instead of rediscovering those facts
/// from concrete surface cases.
public struct SurfaceParameterTopology: Hashable, Sendable {
    public let uPeriod: Double?
    public let vPeriod: Double?
    public let uSingularVValues: [Double]

    public init(surface: Surface3D) {
        let periods = Self.periods(on: surface)
        self.uPeriod = periods.u; self.vPeriod = periods.v
        self.uSingularVValues = Self.uSingularVValues(on: surface)
    }

    public func isUSingular(
        _ parameter: SurfaceParameter,
        tolerance: ModelingTolerance
    ) -> Bool {
        uSingularVValues.contains {
            abs(parameter.v - $0) <= max(tolerance.distance, tolerance.angle)
        }
    }

    private static func periods(on surface:Surface3D)->(u:Double?,v:Double?) {
        switch surface {
        case .procedural(.originalRevolution(let revolution)): return (revolution.originalAngularPeriod,nil)
        case .procedural(.originalImage(let image)):
            let original = periods(on:image.source)
            return (image.swapAxes ? original.v.map { $0 / abs(image.uGain) } : original.u.map { $0 / abs(image.uGain) },
                    image.swapAxes ? original.u.map { $0 / abs(image.vGain) } : original.v.map { $0 / abs(image.vGain) })
        case .procedural(.offset(let offset)): return periods(on:offset.source)
        default: return (period(of:surface.uDomain),period(of:surface.vDomain))
        }
    }

    private static func period(of domain: ParameterDomain) -> Double? {
        guard case let .periodic(period) = domain else { return nil }
        return period
    }

    private static func uSingularVValues(on surface: Surface3D) -> [Double] {
        switch surface {
        case let .analytic(analytic):
            switch analytic {
            case .sphere:
                return [-Double.pi * 0.5, Double.pi * 0.5]
            case .cone:
                return [0.0]
            case .plane, .cylinder, .torus:
                return []
            }
        case let .procedural(.originalAngularTransport(image)):
            return image.vTransport.isIntrinsic ? uSingularVValues(on: image.source) : []
        case let .procedural(.originalAffineWord(image)):
            return uSingularVValues(on: image.source)
        case let .procedural(.originalImage(image)):
            guard !image.swapAxes else { return [] }
            return uSingularVValues(on: image.source).map { ($0 - image.vOffset) / image.vGain }
        case let .procedural(.offset(offset)):
            return uSingularVValues(on: offset.source)
        case .procedural(.originalRevolution(let revolution)):
            return (revolution.hasOriginalAxisEndpoint(atEnd:false) ? [0] : [])
                + (revolution.hasOriginalAxisEndpoint(atEnd:true) ? [1] : [])
        case .plane, .cylinder, .bSpline, .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            return []
        }
    }
}
