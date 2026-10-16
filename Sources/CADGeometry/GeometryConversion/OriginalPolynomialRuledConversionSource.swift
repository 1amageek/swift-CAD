import CADCore

/// Encloses the original ruled law directly from its two stored polynomial rows.
struct OriginalPolynomialRuledConversionSource: GeometrySurfaceConversionSource {
    private let surface: RuledSurface3D
    private let patches: [PolynomialConversionTargetPatch]

    static func accepts(_ surface: RuledSurface3D) -> Bool {
        guard case .bSpline(let start) = surface.startBoundary,
              case .bSpline(let end) = surface.endBoundary else { return false }
        return start.degree == end.degree && start.knots == end.knots
            && PolynomialCurveConversionTarget.accepts(start)
            && PolynomialCurveConversionTarget.accepts(end)
    }

    init(_ surface: RuledSurface3D, tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(surface, tolerance: tolerance, using: &execution)
    }

    init(_ surface: RuledSurface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try Surface3D.procedural(.ruled(surface)).validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
        guard Self.accepts(surface), case .bSpline(let start) = surface.startBoundary,
              case .bSpline(let end) = surface.endBoundary else {
            throw GeometryConversionError.invalidInput("Original polynomial ruled admission requires exact matching stored Bezier bases.")
        }
        self.surface = surface
        let spans = (start.controlPointCount - 1) / start.degree
        try PolynomialConversionTargetPatch.chargePreparation(uDegree: start.degree, vDegree: 1,
            patches: spans, knots: start.knots.count + end.knots.count, using: &execution)
        var values: [PolynomialConversionTargetPatch] = []
        try OriginalCoefficientAllocation.reserve(count: spans, of: PolynomialConversionTargetPatch.self, using: &execution)
        values.reserveCapacity(spans)
        for span in 0..<spans {
            try CurrentTaskCancellationChecker().checkCancellation()
            let offset = span * start.degree
            values.append(try PolynomialConversionTargetPatch(
                u: ScalarInterval(lower: start.knots[offset + start.degree], upper: start.knots[offset + start.degree + 1]),
                v: ScalarInterval(lower: 0, upper: 1), uDegree: start.degree, vDegree: 1, using: &execution
            ) { u, v in
                v == 0 ? start.controlPoints[offset + u] : end.controlPoints[offset + u]
            })
        }
        patches = values
        try CurrentTaskCancellationChecker().checkCancellation()
    }

    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws {
        try parameters.validateAssumingSurfaceValidated(for: .procedural(.ruled(surface)), tolerance: tolerance)
        guard case .closed(let lower, let upper) = surface.uDomain,
              parameters.u.lower >= lower, parameters.u.upper <= upper,
              parameters.v.lower >= 0, parameters.v.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original ruled enclosures require the complete rectangle inside the unchanged native chart.")
        }
    }

    func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try surface.point(u: u, v: v, tolerance: tolerance)
    }

    private func evaluatedEnclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceDifferentialEnclosure {
        try CurrentTaskCancellationChecker().checkCancellation()
        try validate(over: parameters, tolerance: tolerance)
        typealias Vector = PolynomialConversionTargetPatch.Vector
        var position: Vector?, tangentU: Vector?, tangentV: Vector?
        var secondUU: Vector?, secondUV: Vector?, secondVV: Vector?
        for patch in patches {
            try CurrentTaskCancellationChecker().checkCancellation()
            let lower = max(parameters.u.lower, patch.u.lower), upper = min(parameters.u.upper, patch.u.upper)
            guard lower <= upper else { continue }
            let box = SurfaceParameterBox(u: try ScalarInterval(lower: lower, upper: upper), v: parameters.v)
            position = Self.union(position, try patch.derivative(uOrder: 0, vOrder: 0, over: box, using: &execution))
            tangentU = Self.union(tangentU, try patch.derivative(uOrder: 1, vOrder: 0, over: box, using: &execution))
            tangentV = Self.union(tangentV, try patch.derivative(uOrder: 0, vOrder: 1, over: box, using: &execution))
            secondUU = Self.union(secondUU, try patch.derivative(uOrder: 2, vOrder: 0, over: box, using: &execution))
            secondUV = Self.union(secondUV, try patch.derivative(uOrder: 1, vOrder: 1, over: box, using: &execution))
            secondVV = Self.union(secondVV, try patch.derivative(uOrder: 0, vOrder: 2, over: box, using: &execution))
        }
        guard let position, let tangentU, let tangentV, let secondUU, let secondUV, let secondVV else {
            throw GeometryConversionError.invalidInput("Original ruled enclosure lost a requested native span.")
        }
        let result = try SurfaceDifferentialEnclosure(
            position: PolynomialConversionTargetPatch.coordinates(position),
            tangentU: PolynomialConversionTargetPatch.coordinates(tangentU),
            tangentV: PolynomialConversionTargetPatch.coordinates(tangentV),
            secondDerivativeUU: PolynomialConversionTargetPatch.coordinates(secondUU),
            secondDerivativeUV: PolynomialConversionTargetPatch.coordinates(secondUV),
            secondDerivativeVV: PolynomialConversionTargetPatch.coordinates(secondVV))
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try validate(over: parameters, tolerance: tolerance)
    }

    func point(u: Double, v: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        let value = try enclosure(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
            tolerance: tolerance, using: &execution).position
        return .init(x: value.x.midpoint, y: value.y.midpoint, z: value.z.midpoint)
    }

    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceDifferentialEnclosure {
        guard case .bSpline(let start) = surface.startBoundary else {
            throw GeometryConversionError.invalidInput("Original polynomial ruled source lost its native boundary.")
        }
        try PolynomialConversionTargetPatch.chargeProbe(uDegree: start.degree, vDegree: 1, curve: false,
            patches: patches.count, scans: start.knots.count, using: &execution)
        let result = try evaluatedEnclosure(over: parameters, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try enclosure(over: parameters, tolerance: tolerance, using: &execution)
    }

    private static func union(_ first: PolynomialConversionTargetPatch.Vector?,
                              _ second: PolynomialConversionTargetPatch.Vector) -> PolynomialConversionTargetPatch.Vector {
        guard let first else { return second }
        return .init(x: first.x.union(second.x), y: first.y.union(second.y), z: first.z.union(second.z))
    }
}
