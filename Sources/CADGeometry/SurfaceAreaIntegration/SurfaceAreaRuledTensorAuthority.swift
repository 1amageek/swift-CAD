import CADCore

/// An original same-denominator ruled chart, represented without conversion.
struct SurfaceAreaRuledTensorAuthority: Sendable {
    let original: RuledSurface3D
    let tensor: BSplineSurface3D
    private let translatesAlongV: Bool

    init?(original: RuledSurface3D, maximumControlPointCount: Int,
          tolerance: ModelingTolerance) throws {
        try Task.checkCancellation()
        guard case .bSpline(let start) = original.startBoundary,
              case .bSpline(let end) = original.endBoundary else { return nil }
        let limit = maximumControlPointCount
        guard limit > 0, limit <= 1_048_576 else {
            throw Self.failure(.resourceLimitExceeded, tolerance, "Ruled tensor control admission has no finite limit.")
        }
        for rail in [start, end] {
            guard rail.controlPoints.count <= limit, rail.weights.count <= limit,
                  rail.knots.count <= 2 * limit + 1 else {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Original ruled rail dimensions exceed area admission.")
            }
            guard rail.degree >= 1, rail.degree < rail.controlPoints.count,
                  rail.knots.count == rail.controlPoints.count + rail.degree + 1,
                  rail.weights.count == rail.controlPoints.count else {
                throw Self.failure(.invalidInput, tolerance, "Original ruled rail dimensions are inconsistent.")
            }
        }
        try original.validate(tolerance: tolerance)
        guard !start.isPeriodic, !end.isPeriodic, start.degree == end.degree,
              start.knots == end.knots, start.weights == end.weights,
              start.domain == end.domain, original.uDomain == start.domain else { return nil }
        // With identical original basis/weights, both rails have the same W.
        // The tensor numerator is (1-v)N0+v*N1, and its denominator stays W.
        // Original rows retain their COW buffers; only two row owners are made.
        let count = start.controlPoints.count
        guard count <= limit / 2 else {
            throw Self.failure(.resourceLimitExceeded, tolerance, "Original ruled tensor controls exceed area admission.")
        }
        var expanded = 1
        for factor in [count - start.degree, start.degree + 1, 2] {
            guard factor > 0, factor <= limit / expanded else {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Original ruled tensor native span preparation exceeds area admission.")
            }
            expanded *= factor
        }
        try Task.checkCancellation()
        self.original = original
        translatesAlongV = SurfaceAreaTranslationCertificate.direction(of: .procedural(.ruled(original))) == .v
        tensor = BSplineSurface3D(uDegree: start.degree, vDegree: 1,
            uKnots: start.knots, vKnots: [0, 0, 1, 1],
            controlPoints: [start.controlPoints, end.controlPoints],
            weights: [start.weights, end.weights])
    }

    /// Integrates the original rational line image, never converted coefficients.
    func rectangleIntegral(rectangle: SurfaceParameterBox, fraction: ScalarInterval,
                           nativeLower: Double, nativeUpper: Double,
                           reference: Point3D, tolerance: ModelingTolerance)
        throws -> [OutwardScalarInterval]? {
        try Task.checkCancellation()
        guard case .bSpline(let start) = original.startBoundary,
              case .bSpline(let end) = original.endBoundary, start.degree == 1,
              translatesAlongV else {
            return nil
        }
        guard fraction.lower.isFinite, fraction.upper.isFinite,
              fraction.lower >= 0, fraction.upper <= 1, fraction.lower <= fraction.upper,
              rectangle.u.lower >= nativeLower, rectangle.u.upper <= nativeUpper,
              rectangle.v.lower >= 0, rectangle.v.upper <= 1,
              reference.x.isFinite, reference.y.isFinite, reference.z.isFinite else {
            throw Self.failure(.invalidInput, tolerance, "Original ruled rectangle parameters are outside their retained authority.")
        }
        // Native knot indices select the original two active controls. Matching a
        // prepared span alone cannot authorize unrelated extracted coefficients.
        var owner: Int?
        for index in 1..<start.controlPoints.count {
            if start.knots[index] == nativeLower, start.knots[index + 1] == nativeUpper,
               nativeLower < nativeUpper {
                owner = index
                break
            }
        }
        guard let owner else {
            throw Self.failure(.invalidInput, tolerance, "Ruled rectangle has no matching original native knot owner.")
        }
        let p0 = start.controlPoints[owner - 1], p1 = start.controlPoints[owner]
        let q0 = end.controlPoints[owner - 1]
        let w0 = OutwardScalarInterval.exact(start.weights[owner - 1])
        let w1 = OutwardScalarInterval.exact(start.weights[owner])
        guard w0.lower > 0, w1.lower > 0, w0.isFinite, w1.isFinite else {
            throw Self.failure(.invalidInput, tolerance, "Original ruled rectangle weights are not finite and positive.")
        }
        func vector(_ point: Point3D) -> IntervalVector3DBounds {
            IntervalVector3DBounds(x: .exact(point.x), y: .exact(point.y), z: .exact(point.z))
        }
        let origin = vector(p0)
        let displacement = vector(p1) - origin
        let translation = vector(q0) - origin
        let cross = displacement.cross(translation)
        let norm = OutwardScalarInterval(lower: cross.lengthLowerBound, upper: cross.lengthUpperBound)
        guard norm.isFinite, norm.lower > 0 else {
            throw Self.failure(.singularSystem, tolerance, "Original ruled rectangle has no certified positive area density.")
        }
        let width = OutwardScalarInterval.exact(rectangle.u.upper) - .exact(rectangle.u.lower)
        guard width.isFinite, width.lower > 0 else {
            throw Self.failure(.classificationFailure, tolerance, "Original ruled rectangle width is not finite and positive.")
        }
        func originalParameter(_ f: Double) throws -> OutwardScalarInterval {
            if f == 0 { return .exact(rectangle.u.lower) }
            if f == 1 { return .exact(rectangle.u.upper) }
            let value = OutwardScalarInterval.exact(rectangle.u.lower) + width * .exact(f)
            guard value.isFinite, value.lower <= rectangle.u.upper, value.upper >= rectangle.u.lower else {
                throw Self.failure(.classificationFailure, tolerance, "Original ruled rectangle fraction has no finite native image.")
            }
            // The actual fraction is already certified inside [0,1]. Intersection
            // removes only outward arithmetic overhang of this original rectangle.
            return OutwardScalarInterval(lower: max(rectangle.u.lower, value.lower),
                                         upper: min(rectangle.u.upper, value.upper))
        }
        func h(_ u: OutwardScalarInterval) throws -> OutwardScalarInterval {
            if u.lower == nativeLower, u.upper == nativeLower { return .exact(0) }
            if u.lower == nativeUpper, u.upper == nativeUpper { return .exact(1) }
            let first = u - .exact(nativeLower)
            let last = OutwardScalarInterval.exact(nativeUpper) - u
            let numerator = w1 * first
            let denominator = w0 * last + numerator
            guard denominator.isFinite, denominator.lower > 0 else {
                throw Self.failure(.classificationFailure, tolerance, "Original ruled rational endpoint lost its positive denominator.")
            }
            guard let result = numerator.divided(by: denominator), result.isFinite else {
                throw Self.failure(.classificationFailure, tolerance, "Original ruled rational endpoint exceeded finite arithmetic.")
            }
            return result
        }
        let h0 = try h(originalParameter(fraction.lower))
        let h1 = try h(originalParameter(fraction.upper))
        let band = OutwardScalarInterval.exact(rectangle.v.upper) - .exact(rectangle.v.lower)
        let area = norm * (h1 - h0) * band
        let meanH = (h0 + h1) * .exact(0.5)
        let meanV = (OutwardScalarInterval.exact(rectangle.v.lower) + .exact(rectangle.v.upper)) * .exact(0.5)
        let center = [origin.x + displacement.x * meanH + translation.x * meanV,
                      origin.y + displacement.y * meanH + translation.y * meanV,
                      origin.z + displacement.z * meanH + translation.z * meanV]
        let referenceCoordinates = [reference.x, reference.y, reference.z]
        let result = [area] + center.indices.map { area * (center[$0] - .exact(referenceCoordinates[$0])) }
        guard result.allSatisfy(\.isFinite) else {
            throw Self.failure(.classificationFailure, tolerance, "Original ruled rectangle integral exceeded finite arithmetic.")
        }
        try Task.checkCancellation()
        return result
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                                _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
