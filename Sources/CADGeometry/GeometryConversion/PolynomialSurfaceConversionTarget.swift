import CADCore

struct PolynomialSurfaceConversionTarget: GeometrySurfaceConversionSource {
    private let surface: BSplineSurface3D
    private let patch: PolynomialConversionTargetPatch

    static func accepts(_ surface: BSplineSurface3D) -> Bool {
        guard (1...3).contains(surface.uDegree), (1...3).contains(surface.vDegree),
              surface.uControlPointCount == surface.uDegree + 1, surface.vControlPointCount == surface.vDegree + 1,
              surface.uKnots.count == 2 * (surface.uDegree + 1), surface.vKnots.count == 2 * (surface.vDegree + 1),
              surface.weights.count == surface.vControlPointCount,
              let weight = surface.weights.first?.first, weight.isFinite, weight > 0 else { return false }
        for row in surface.weights where row.count != surface.uControlPointCount || !row.allSatisfy({ $0 == weight }) { return false }
        let uLower = surface.uKnots[0], uUpper = surface.uKnots[surface.uDegree + 1]
        let vLower = surface.vKnots[0], vUpper = surface.vKnots[surface.vDegree + 1]
        guard uLower.isFinite, uUpper.isFinite, vLower.isFinite, vUpper.isFinite,
              uLower < uUpper, vLower < vUpper else { return false }
        for i in 0...surface.uDegree where surface.uKnots[i] != uLower || surface.uKnots[i + surface.uDegree + 1] != uUpper { return false }
        for i in 0...surface.vDegree where surface.vKnots[i] != vLower || surface.vKnots[i + surface.vDegree + 1] != vUpper { return false }
        return true
    }

    init(_ surface: BSplineSurface3D, tolerance: ModelingTolerance) throws {
        try surface.validate(tolerance: tolerance)
        guard Self.accepts(surface) else {
            throw GeometryConversionError.invalidInput("Polynomial surface target requires one exact stored Bezier tensor through bicubic degree.")
        }
        self.surface = surface
        patch = try PolynomialConversionTargetPatch(
            u: ScalarInterval(lower: surface.uKnots[0], upper: surface.uKnots[surface.uDegree + 1]),
            v: ScalarInterval(lower: surface.vKnots[0], upper: surface.vKnots[surface.vDegree + 1]),
            uDegree: surface.uDegree, vDegree: surface.vDegree
        ) { u, v in surface.controlPoints[v][u] }
    }

    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws {
        try parameters.validateAssumingSurfaceValidated(for: .bSpline(surface), tolerance: tolerance)
    }

    func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try surface.point(u: u, v: v, tolerance: tolerance)
    }

    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance)
        return try .init(position: PolynomialConversionTargetPatch.coordinates(patch.derivative(uOrder: 0, vOrder: 0, over: parameters)),
            tangentU: PolynomialConversionTargetPatch.coordinates(patch.derivative(uOrder: 1, vOrder: 0, over: parameters)),
            tangentV: PolynomialConversionTargetPatch.coordinates(patch.derivative(uOrder: 0, vOrder: 1, over: parameters)),
            secondDerivativeUU: PolynomialConversionTargetPatch.coordinates(patch.derivative(uOrder: 2, vOrder: 0, over: parameters)),
            secondDerivativeUV: PolynomialConversionTargetPatch.coordinates(patch.derivative(uOrder: 1, vOrder: 1, over: parameters)),
            secondDerivativeVV: PolynomialConversionTargetPatch.coordinates(patch.derivative(uOrder: 0, vOrder: 2, over: parameters)))
    }
}
