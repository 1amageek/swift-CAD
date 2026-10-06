import CADCore

/// Authored physical-angle source without a rounded pi-ratio coefficient.
public struct OriginalAngularTransportCurve3D: Hashable, Sendable {
    public let source: Curve3D
    public let transport: OriginalAngularParameterTransport
    package let coefficients: OriginalAffineWordCircularCoefficients

    // FIXME(INCOMPLETE_IMPLEMENTATION): Foreign authored angle ingress consumes
    // this direct ideal conic transport. Spatial word coefficient preparation is
    // connected; generic conic images, inverse phase charts and non-binary pole
    // endpoint carriers remain required before full foreign angular completion.
    public init<B: RationalAlgebraAdmitting>(source: Curve3D, transport: OriginalAngularParameterTransport,
        tolerance: ModelingTolerance, usage: inout B) throws {
        try tolerance.validate(); try transport.validate(usage: &usage)
        self.source = source; self.transport = transport
        let identity = try OriginalAffineOperationWord(operation: .forward(try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)),
            tolerance: tolerance, maximumDepth: 0, usage: &usage).prepared(usage: &usage)
        guard let prepared = try OriginalAffineWordCircularCoefficients.prepare(source: source, word: identity,
            tolerance: tolerance, usage: &usage, admitPhysicalMetric: false) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original physical-radian curve requires a direct ideal circular source.")
        }
        coefficients = prepared.replacingTransport(transport, parameterDomain: Self.domain(source: source, transport: transport))
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
    }
    private static func domain(source: Curve3D, transport: OriginalAngularParameterTransport) -> ParameterDomain {
        if transport.isIntrinsic { return source.parameterDomain }
        if transport.isNormalizedArc { return .closed(0, 1) }
        if case .analytic(.arc(_, _, _, let first, let last)) = source { return .closed(first, last) }
        return .unbounded
    }
    public var parameterDomain: ParameterDomain { Self.domain(source: source, transport: transport) }
    public static func == (a: Self, b: Self) -> Bool { a.source == b.source && a.transport == b.transport }
    public func hash(into hasher: inout Hasher) { hasher.combine(source); hasher.combine(transport) }

    public func validate(tolerance: ModelingTolerance) throws {
        var usage = OriginalAffineImageLegacyUsage()
        try validateOriginalRelation(tolerance: tolerance, usage: &usage)
    }
    package func validateOriginalRelation<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance, usage: inout B) throws {
        try tolerance.validate(); try transport.validate(usage: &usage)
        let identity = try OriginalAffineOperationWord(operation: .forward(try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)), tolerance: tolerance,
            maximumDepth: 0, usage: &usage).prepared(usage: &usage)
        guard try OriginalAffineWordCircularCoefficients.prepare(source: source, word: identity,
            tolerance: tolerance, usage: &usage) != nil else {
            throw GeometryConversionError.invalidInput("Original angular curve lost its admitted primitive source.")
        }
    }
    package func intervalTaylorJet(over range: ScalarInterval, throughOrder order: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try coefficients.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }
    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let q = try intervalTaylorJet(over: .init(lower: parameter, upper: parameter), throughOrder: 0,
            tolerance: tolerance, consumeWork: { try Task.checkCancellation() })
        let x = try q.x.coefficient(0, 0), y = try q.y.coefficient(0, 0), z = try q.z.coefficient(0, 0)
        guard x.isFinite, y.isFinite, z.isFinite else { throw GeometryConversionError.resourceLimitExceeded("Original physical-angle point has no finite representative.") }
        return .init(x: x.midpoint, y: y.midpoint, z: z.midpoint)
    }
    package func differentialGeometry(at parameter: Double, tolerance: ModelingTolerance) throws -> Curve3D.DifferentialGeometry {
        let q = try intervalTaylorJet(over: .init(lower: parameter, upper: parameter), throughOrder: 2,
            tolerance: tolerance, consumeWork: { try Task.checkCancellation() })
        return try Curve3D.differentialGeometry(position: point(at: parameter, tolerance: tolerance),
            firstDerivative: .init(x: q.x.coefficient(1, 0).midpoint, y: q.y.coefficient(1, 0).midpoint, z: q.z.coefficient(1, 0).midpoint),
            secondDerivative: .init(x: (q.x.coefficient(2, 0) * .exact(2)).midpoint, y: (q.y.coefficient(2, 0) * .exact(2)).midpoint, z: (q.z.coefficient(2, 0) * .exact(2)).midpoint), tolerance: tolerance)
    }
}
