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
        try Task.checkCancellation()
        try surface.validate(tolerance: tolerance)
        guard Self.accepts(surface), case .bSpline(let start) = surface.startBoundary,
              case .bSpline(let end) = surface.endBoundary else {
            throw GeometryConversionError.invalidInput("Original polynomial ruled admission requires exact matching stored Bezier bases.")
        }
        self.surface = surface
        let spans = (start.controlPointCount - 1) / start.degree
        var values: [PolynomialConversionTargetPatch] = []
        values.reserveCapacity(spans)
        for span in 0..<spans {
            try Task.checkCancellation()
            let offset = span * start.degree
            values.append(try PolynomialConversionTargetPatch(
                u: ScalarInterval(lower: start.knots[offset + start.degree], upper: start.knots[offset + start.degree + 1]),
                v: ScalarInterval(lower: 0, upper: 1), uDegree: start.degree, vDegree: 1
            ) { u, v in
                v == 0 ? start.controlPoints[offset + u] : end.controlPoints[offset + u]
            })
        }
        patches = values
        try Task.checkCancellation()
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

    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        try Task.checkCancellation()
        try validate(over: parameters, tolerance: tolerance)
        typealias Vector = PolynomialConversionTargetPatch.Vector
        var position: Vector?, tangentU: Vector?, tangentV: Vector?
        var secondUU: Vector?, secondUV: Vector?, secondVV: Vector?
        for patch in patches {
            try Task.checkCancellation()
            let lower = max(parameters.u.lower, patch.u.lower), upper = min(parameters.u.upper, patch.u.upper)
            guard lower <= upper else { continue }
            let box = SurfaceParameterBox(u: try ScalarInterval(lower: lower, upper: upper), v: parameters.v)
            position = Self.union(position, try patch.derivative(uOrder: 0, vOrder: 0, over: box))
            tangentU = Self.union(tangentU, try patch.derivative(uOrder: 1, vOrder: 0, over: box))
            tangentV = Self.union(tangentV, try patch.derivative(uOrder: 0, vOrder: 1, over: box))
            secondUU = Self.union(secondUU, try patch.derivative(uOrder: 2, vOrder: 0, over: box))
            secondUV = Self.union(secondUV, try patch.derivative(uOrder: 1, vOrder: 1, over: box))
            secondVV = Self.union(secondVV, try patch.derivative(uOrder: 0, vOrder: 2, over: box))
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
        try Task.checkCancellation()
        return result
    }

    private static func union(_ first: PolynomialConversionTargetPatch.Vector?,
                              _ second: PolynomialConversionTargetPatch.Vector) -> PolynomialConversionTargetPatch.Vector {
        guard let first else { return second }
        return .init(x: first.x.union(second.x), y: first.y.union(second.y), z: first.z.union(second.z))
    }
}
