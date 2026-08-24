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
        self.uPeriod = Self.period(of: surface.uDomain)
        self.vPeriod = Self.period(of: surface.vDomain)
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
        case let .procedural(.offset(offset)):
            return uSingularVValues(on: offset.source)
        case .plane, .cylinder, .bSpline, .procedural(.ruled):
            return []
        }
    }
}
