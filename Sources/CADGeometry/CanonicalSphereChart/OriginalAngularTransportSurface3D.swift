import CADCore

/// Original angular-coordinate transport retaining physical-radian expressions.
public struct OriginalAngularTransportSurface3D: Hashable, Sendable {
    public let source: Surface3D
    public let uTransport: OriginalAngularParameterTransport
    public let vTransport: OriginalAngularParameterTransport
    package let preparedIdentity: PreparedOriginalAffineOperationWord
    package let coefficients: OriginalAffineWordHarmonicSurfaceCoefficients

    // FIXME(INCOMPLETE_IMPLEMENTATION): Authored physical-radian surface charts
    // consume direct cylinder/sphere/torus harmonic sources. Source DI now retains exact physical latitude boundaries and cone slope
    // laws. General inverse/image relation consumers still require migration before
    // full foreign angular relation consumption can be declared complete.
    public init<B: RationalAlgebraAdmitting>(source: Surface3D, uTransport: OriginalAngularParameterTransport,
        vTransport: OriginalAngularParameterTransport, tolerance: ModelingTolerance, usage: inout B) throws {
        try tolerance.validate(); try uTransport.validate(usage: &usage); try vTransport.validate(usage: &usage)
        self.source = source; self.uTransport = uTransport; self.vTransport = vTransport
        if case .cylinder = source, !vTransport.isIntrinsic { throw GeometryConversionError.invalidInput("Cylinder height is not an angular coordinate.") }
        if case .analytic(.cone) = source, !vTransport.isIntrinsic { throw GeometryConversionError.invalidInput("Cone V is an original scalar coordinate.") }
        if case .analytic(.cylinder) = source, !vTransport.isIntrinsic { throw GeometryConversionError.invalidInput("Cylinder height is not an angular coordinate.") }
        if case .analytic(.sphere) = source,vTransport.isNormalizedArc {
            try vTransport.requireSphereLatitude(over:.init(lower:0,upper:1),consumeWork:{ try usage.consumeExactWork(1) })
        }
        let identity = try OriginalAffineOperationWord(operation: .forward(try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)), tolerance: tolerance,
            maximumDepth: 0, usage: &usage).prepared(usage: &usage)
        preparedIdentity = identity
        guard let prepared = try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(source: source, word: identity,
            tolerance: tolerance, usage: &usage, admitPhysicalMetric: false) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original angular support requires a direct periodic ideal primitive.")
        }
        coefficients = prepared.replacingTransports(u: uTransport, v: vTransport)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
    }
    public var uDomain: ParameterDomain { uTransport.isIntrinsic ? source.uDomain : (uTransport.isNormalizedArc ? .closed(0, 1) : .unbounded) }
    public var vDomain: ParameterDomain { vTransport.isIntrinsic ? source.vDomain : (vTransport.isNormalizedArc ? .closed(0, 1) : .unbounded) }
    public static func == (a: Self, b: Self) -> Bool { a.source == b.source && a.uTransport == b.uTransport && a.vTransport == b.vTransport }
    public func hash(into hasher: inout Hasher) { hasher.combine(source); hasher.combine(uTransport); hasher.combine(vTransport) }
    public func validate(tolerance: ModelingTolerance) throws {
        var usage = OriginalAffineImageLegacyUsage(); try validateOriginalRelation(tolerance: tolerance, usage: &usage)
    }
    package func validateOriginalRelation<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance, usage: inout B) throws {
        try tolerance.validate(); try uTransport.validate(usage: &usage); try vTransport.validate(usage: &usage)
        let identity = try OriginalAffineOperationWord(operation: .forward(try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)), tolerance: tolerance,
            maximumDepth: 0, usage: &usage).prepared(usage: &usage)
        guard try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(source: source, word: identity, tolerance: tolerance, usage: &usage) != nil else {
            throw GeometryConversionError.invalidInput("Original angular support lost its admitted primitive.")
        }
    }
    package func intervalTaylorJet(over box: SurfaceParameterBox, throughOrder order: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try coefficients.intervalTaylorJet(over: box, throughOrder: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
    }
    package func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        try intervalTaylorJet(over: box, throughOrder: 3, tolerance: tolerance, consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
    }
    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let q = try intervalTaylorJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
            throughOrder: 0, tolerance: tolerance, consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
        return try .init(x: q.x.coefficient(0, 0).midpoint, y: q.y.coefficient(0, 0).midpoint, z: q.z.coefficient(0, 0).midpoint)
    }
  public func parameterDerivativesThroughThirdOrder(u: Double, v: Double,
    tolerance: ModelingTolerance) throws -> SurfaceParameterThirdOrderDerivatives {
    var usage = OriginalAffineImageLegacyUsage()
    do {
      let jet = try coefficients.intervalTaylorJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        throughOrder: 3, tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) }).intervalJet()
      return .init(position: .init(x: jet.x.value.midpoint, y: jet.y.value.midpoint, z: jet.z.value.midpoint),
        tangentU: .init(x: jet.x.derivativeU.midpoint, y: jet.y.derivativeU.midpoint, z: jet.z.derivativeU.midpoint),
        tangentV: .init(x: jet.x.derivativeV.midpoint, y: jet.y.derivativeV.midpoint, z: jet.z.derivativeV.midpoint),
        secondDerivativeUU: .init(x: jet.x.secondDerivativeUU.midpoint, y: jet.y.secondDerivativeUU.midpoint, z: jet.z.secondDerivativeUU.midpoint),
        secondDerivativeUV: .init(x: jet.x.secondDerivativeUV.midpoint, y: jet.y.secondDerivativeUV.midpoint, z: jet.z.secondDerivativeUV.midpoint),
        secondDerivativeVV: .init(x: jet.x.secondDerivativeVV.midpoint, y: jet.y.secondDerivativeVV.midpoint, z: jet.z.secondDerivativeVV.midpoint),
        thirdDerivativeUUU: .init(x: jet.x.thirdDerivativeUUU.midpoint, y: jet.y.thirdDerivativeUUU.midpoint, z: jet.z.thirdDerivativeUUU.midpoint),
        thirdDerivativeUUV: .init(x: jet.x.thirdDerivativeUUV.midpoint, y: jet.y.thirdDerivativeUUV.midpoint, z: jet.z.thirdDerivativeUUV.midpoint),
        thirdDerivativeUVV: .init(x: jet.x.thirdDerivativeUVV.midpoint, y: jet.y.thirdDerivativeUVV.midpoint, z: jet.z.thirdDerivativeUVV.midpoint),
        thirdDerivativeVVV: .init(x: jet.x.thirdDerivativeVVV.midpoint, y: jet.y.thirdDerivativeVVV.midpoint, z: jet.z.thirdDerivativeVVV.midpoint))
    }
  }
  public func parameterDerivatives(u: Double, v: Double, tolerance: ModelingTolerance)
    throws -> SurfaceParameterDerivatives {
    let q = try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance)
    return .init(position: q.position, tangentU: q.tangentU, tangentV: q.tangentV,
      secondDerivativeUU: q.secondDerivativeUU, secondDerivativeUV: q.secondDerivativeUV,
      secondDerivativeVV: q.secondDerivativeVV)
  }
  func taylorJet(u: Double, v: Double, throughOrder order: Int,
    tolerance: ModelingTolerance) throws -> SurfaceTaylorVectorJet {
    do {
      let jet = try coefficients.intervalTaylorJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        throughOrder: order, tolerance: tolerance, consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
      var x = try SurfaceTaylorScalarJet(order: order), y = try SurfaceTaylorScalarJet(order: order), z = try SurfaceTaylorScalarJet(order: order)
      for total in 0...order { for a in 0...total {
        try CurrentTaskCancellationChecker().checkCancellation(); let b = total-a
        try x.setCoefficient(jet.x.coefficient(a,b).midpoint, uOrder: a, vOrder: b)
        try y.setCoefficient(jet.y.coefficient(a,b).midpoint, uOrder: a, vOrder: b)
        try z.setCoefficient(jet.z.coefficient(a,b).midpoint, uOrder: a, vOrder: b)
      } }
      return try .init(x: x, y: y, z: z)
    }
  }
}
