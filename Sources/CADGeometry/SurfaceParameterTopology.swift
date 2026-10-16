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

    public init(surface: Surface3D) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(surface: surface, using: &execution)
    }

    public init<A: ExactScalarAdmission & ~Copyable>(surface: Surface3D,
        using execution: inout A) throws {
        try execution.consumeWork(1)
        let periods = try Self.periods(on: surface, using: &execution)
        self.uPeriod = periods.u; self.vPeriod = periods.v
        self.uSingularVValues = try Self.uSingularVValues(on: surface, using: &execution)
    }

    public func isUSingular(
        _ parameter: SurfaceParameter,
        tolerance: ModelingTolerance
    ) -> Bool {
        uSingularVValues.contains { Self.isUSingular(parameter, at: $0, tolerance: tolerance) }
    }

    public func isUSingular<A: ExactScalarAdmission & ~Copyable>(_ parameter: SurfaceParameter,
        tolerance: ModelingTolerance, using execution: inout A) throws -> Bool {
        try uSingularVValues.contains { value in
            try execution.consumeWork(1)
            return Self.isUSingular(parameter, at: value, tolerance: tolerance)
        }
    }

    private static func isUSingular(_ parameter: SurfaceParameter, at value: Double,
        tolerance: ModelingTolerance) -> Bool {
        abs(parameter.v - value) <= max(tolerance.distance, tolerance.angle)
    }

    private static func periods<A: ExactScalarAdmission & ~Copyable>(on surface: Surface3D,
        using execution: inout A) throws -> (u: Double?, v: Double?) {
        try execution.consumeWork(1)
        switch surface {
        case .procedural(.originalRevolution(let revolution)): return (revolution.originalAngularPeriod,nil)
        case .procedural(.originalImage(let image)):
            let original = try periods(on: image.source, using: &execution)
            return (image.swapAxes ? original.v.map { $0 / abs(image.uGain) } : original.u.map { $0 / abs(image.uGain) },
                    image.swapAxes ? original.u.map { $0 / abs(image.vGain) } : original.v.map { $0 / abs(image.vGain) })
        case .procedural(.offset(let offset)): return try periods(on: offset.source, using: &execution)
        default: return (period(of:surface.uDomain),period(of:surface.vDomain))
        }
    }

    private static func period(of domain: ParameterDomain) -> Double? {
        guard case let .periodic(period) = domain else { return nil }
        return period
    }

    private static func uSingularVValues<A: ExactScalarAdmission & ~Copyable>(on surface: Surface3D,
        using execution: inout A) throws -> [Double] {
        try execution.consumeWork(1)
        switch surface {
        case let .analytic(analytic):
            switch analytic {
            case .sphere:
                return try singularValues(-Double.pi * 0.5, Double.pi * 0.5, using: &execution)
            case .cone:
                return try singularValues(0.0, using: &execution)
            case .plane, .cylinder, .torus:
                return []
            }
        case let .procedural(.originalAngularTransport(image)):
            return image.vTransport.isIntrinsic ? try uSingularVValues(on: image.source, using: &execution) : []
        case let .procedural(.originalAffineWord(image)):
            return try uSingularVValues(on: image.source, using: &execution)
        case let .procedural(.originalImage(image)):
            guard !image.swapAxes else { return [] }
            let sourceValues = try uSingularVValues(on: image.source, using: &execution)
            return try OriginalCoefficientAllocation.map(elements: sourceValues, using: &execution) { value, _ in
                (value - image.vOffset) / image.vGain
            }
        case let .procedural(.offset(offset)):
            return try uSingularVValues(on: offset.source, using: &execution)
        case .procedural(.originalRevolution(let revolution)):
            let first = revolution.hasOriginalAxisEndpoint(atEnd: false)
            let second = revolution.hasOriginalAxisEndpoint(atEnd: true)
            if first { return try singularValues(0, second ? 1 : nil, using: &execution) }
            if second { return try singularValues(1, using: &execution) }
            return []
        case .plane, .cylinder, .bSpline, .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            return []
        }
    }
    private static func singularValues<A: ExactScalarAdmission & ~Copyable>(_ first: Double,
        _ second: Double? = nil, using execution: inout A) throws -> [Double] {
        try OriginalCoefficientAllocation.reserve(count: second == nil ? 1 : 2, of: Double.self, using: &execution)
        if let second { return [first, second] }
        return [first]
    }

}
