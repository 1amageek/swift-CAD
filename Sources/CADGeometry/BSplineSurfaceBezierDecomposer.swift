import CADCore

struct BSplineSurfaceBezierDecomposer {
    func surfacePatches(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierSurfacePatch3D] {
        let refined = try bezierRefined(surface: surface, tolerance: tolerance)
        let uBreaks = distinctKnots(refined.uKnots, domain: refined.uDomain)
        let vBreaks = distinctKnots(refined.vKnots, domain: refined.vDomain)
        let uSpanCount = uBreaks.count - 1
        let vSpanCount = vBreaks.count - 1
        try validateBezierLayout(
            refined,
            uSpanCount: uSpanCount,
            vSpanCount: vSpanCount,
            tolerance: tolerance
        )
        var result: [RationalBezierSurfacePatch3D] = []
        result.reserveCapacity(uSpanCount * vSpanCount)
        for vSpan in 0..<vSpanCount {
            for uSpan in 0..<uSpanCount {
                let uStart = uSpan * refined.uDegree
                let vStart = vSpan * refined.vDegree
                let rowRange = vStart...(vStart + refined.vDegree)
                let columnRange = uStart...(uStart + refined.uDegree)
                result.append(RationalBezierSurfacePatch3D(
                    controlPoints: rowRange.map { row in
                        columnRange.map { refined.controlPoints[row][$0] }
                    },
                    weights: rowRange.map { row in
                        columnRange.map { refined.weights[row][$0] }
                    },
                    uLower: uBreaks[uSpan],
                    uUpper: uBreaks[uSpan + 1],
                    vLower: vBreaks[vSpan],
                    vUpper: vBreaks[vSpan + 1]
                ))
            }
        }
        return result
    }

    func scalarDistancePatches(
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        tolerance: ModelingTolerance
    ) throws -> [RationalScalarBezierPatch] {
        let refined = try bezierRefined(surface: surface, tolerance: tolerance)
        let uBreaks = distinctKnots(refined.uKnots, domain: refined.uDomain)
        let vBreaks = distinctKnots(refined.vKnots, domain: refined.vDomain)
        let uSpanCount = uBreaks.count - 1
        let vSpanCount = vBreaks.count - 1
        try validateBezierLayout(
            refined,
            uSpanCount: uSpanCount,
            vSpanCount: vSpanCount,
            tolerance: tolerance
        )

        var result: [RationalScalarBezierPatch] = []
        result.reserveCapacity(uSpanCount * vSpanCount)
        for vSpan in 0..<vSpanCount {
            for uSpan in 0..<uSpanCount {
                let uStart = uSpan * refined.uDegree
                let vStart = vSpan * refined.vDegree
                var numerator: [[Double]] = []
                var weights: [[Double]] = []
                numerator.reserveCapacity(refined.vDegree + 1)
                weights.reserveCapacity(refined.vDegree + 1)
                for localV in 0...refined.vDegree {
                    var numeratorRow: [Double] = []
                    var weightRow: [Double] = []
                    numeratorRow.reserveCapacity(refined.uDegree + 1)
                    weightRow.reserveCapacity(refined.uDegree + 1)
                    for localU in 0...refined.uDegree {
                        let row = vStart + localV
                        let column = uStart + localU
                        let point = refined.controlPoints[row][column]
                        let weight = refined.weights[row][column]
                        numeratorRow.append(weight * signedDistance(point, plane: plane))
                        weightRow.append(weight)
                    }
                    numerator.append(numeratorRow)
                    weights.append(weightRow)
                }
                result.append(RationalScalarBezierPatch(
                    numerator: numerator,
                    weights: weights,
                    uLower: uBreaks[uSpan],
                    uUpper: uBreaks[uSpan + 1],
                    vLower: vBreaks[vSpan],
                    vUpper: vBreaks[vSpan + 1]
                ))
            }
        }
        return result
    }

    private func bezierRefined(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        var result = surface
        let originalUKnots = interiorDistinctKnots(surface.uKnots, domain: surface.uDomain)
        for knot in originalUKnots {
            while knotMultiplicity(knot, in: result.uKnots) < result.uDegree {
                result = try result.insertingKnot(
                    direction: .u,
                    value: knot,
                    tolerance: tolerance
                )
            }
        }
        let originalVKnots = interiorDistinctKnots(surface.vKnots, domain: surface.vDomain)
        for knot in originalVKnots {
            while knotMultiplicity(knot, in: result.vKnots) < result.vDegree {
                result = try result.insertingKnot(
                    direction: .v,
                    value: knot,
                    tolerance: tolerance
                )
            }
        }
        return result
    }

    private func validateBezierLayout(
        _ surface: BSplineSurface3D,
        uSpanCount: Int,
        vSpanCount: Int,
        tolerance: ModelingTolerance
    ) throws {
        guard uSpanCount > 0,
              vSpanCount > 0,
              surface.uControlPointCount == uSpanCount * surface.uDegree + 1,
              surface.vControlPointCount == vSpanCount * surface.vDegree + 1 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline to Bezier decomposition produced an inconsistent control net."
            )
        }
    }

    private func distinctKnots(_ knots: [Double], domain: ParameterDomain) -> [Double] {
        let bounds = closedBounds(domain)
        var result: [Double] = []
        for knot in knots where knot >= bounds.lower && knot <= bounds.upper {
            if result.last != knot {
                result.append(knot)
            }
        }
        return result
    }

    private func interiorDistinctKnots(
        _ knots: [Double],
        domain: ParameterDomain
    ) -> [Double] {
        let bounds = closedBounds(domain)
        return distinctKnots(knots, domain: domain).filter {
            $0 > bounds.lower && $0 < bounds.upper
        }
    }

    private func closedBounds(_ domain: ParameterDomain) -> (lower: Double, upper: Double) {
        switch domain {
        case let .closed(lower, upper):
            return (lower, upper)
        case .periodic, .unbounded:
            return (0.0, 0.0)
        }
    }

    private func knotMultiplicity(_ knot: Double, in knots: [Double]) -> Int {
        knots.reduce(0) { $0 + ($1 == knot ? 1 : 0) }
    }

    private func signedDistance(
        _ point: Point3D,
        plane: CanonicalAnalyticSurface.Plane
    ) -> Double {
        (point - plane.origin).dot(plane.normal)
    }
}
