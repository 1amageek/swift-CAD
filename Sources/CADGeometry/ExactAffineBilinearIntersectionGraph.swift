import CADCore

/// An exact graph certificate for an affine bilinear patch intersecting a rational bilinear patch.
///
/// The certificate is deliberately structural. It is available only when one operand is an exact
/// affine parallelogram and the other operand's plane equation has one sign on each side of a
/// parameter direction. The latter proves one and only one dependent parameter for every free
/// parameter. Exact expansion signs also prove that the resulting rational quadratic curve remains
/// inside the affine patch.
struct ExactAffineBilinearIntersectionGraph: Sendable {
    private struct ExpansionVector3 {
        let x: [Double]
        let y: [Double]
        let z: [Double]
    }

    private struct HomogeneousExpansion {
        let x: [Double]
        let y: [Double]
        let z: [Double]
        let weight: [Double]

        func scaled(by scalar: [Double]) -> HomogeneousExpansion {
            HomogeneousExpansion(
                x: FloatingPointExpansion.product(x, scalar),
                y: FloatingPointExpansion.product(y, scalar),
                z: FloatingPointExpansion.product(z, scalar),
                weight: FloatingPointExpansion.product(weight, scalar)
            )
        }

        func adding(_ other: HomogeneousExpansion) -> HomogeneousExpansion {
            HomogeneousExpansion(
                x: FloatingPointExpansion.sum(x, other.x),
                y: FloatingPointExpansion.sum(y, other.y),
                z: FloatingPointExpansion.sum(z, other.z),
                weight: FloatingPointExpansion.sum(weight, other.weight)
            )
        }

        func subtracting(_ other: HomogeneousExpansion) -> HomogeneousExpansion {
            HomogeneousExpansion(
                x: FloatingPointExpansion.subtract(x, other.x),
                y: FloatingPointExpansion.subtract(y, other.y),
                z: FloatingPointExpansion.subtract(z, other.z),
                weight: FloatingPointExpansion.subtract(weight, other.weight)
            )
        }
    }

    private struct AffinePatch {
        let surface: BSplineSurface3D
        let origin: Point3D
        let u: Vector3D
        let v: Vector3D
        let exactU: ExpansionVector3
        let exactV: ExpansionVector3
        let gramUU: [Double]
        let gramUV: [Double]
        let gramVV: [Double]
        let gramDeterminant: [Double]
    }

    private struct CandidateGraph {
        let affineIsFirst: Bool
        let freeIsU: Bool
        let affine: AffinePatch
        let candidate: BSplineSurface3D
        let lowerPlaneValues: [Double]
        let upperPlaneValues: [Double]
    }

    let freeParameter: SurfaceIntersectionParameterCoordinate
    private let graph: CandidateGraph

    static func certified(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> ExactAffineBilinearIntersectionGraph? {
        try tolerance.validate()
        guard isSingleBilinearBezier(first),
              isSingleBilinearBezier(second) else {
            return nil
        }
        let firstAffine = exactAffinePatch(first)
        let secondAffine = exactAffinePatch(second)
        // Two affine patches are already covered by the general full-graph proof. Keeping that
        // path preserves its explicit numerical root-budget contract.
        if firstAffine != nil, secondAffine != nil { return nil }
        if let affine = firstAffine,
           let graph = exactCandidateGraph(
               affine: affine,
               candidate: second,
               affineIsFirst: true
           ) {
            return ExactAffineBilinearIntersectionGraph(
                freeParameter: graph.freeIsU ? .secondU : .secondV,
                graph: graph
            )
        }
        if let affine = secondAffine,
           let graph = exactCandidateGraph(
               affine: affine,
               candidate: first,
               affineIsFirst: false
           ) {
            return ExactAffineBilinearIntersectionGraph(
                freeParameter: graph.freeIsU ? .firstU : .firstV,
                graph: graph
            )
        }
        return nil
    }

    func normalizedParameterPair(
        at fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntersectionParameterPair {
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let free = min(max(fraction, 0.0), 1.0)
        let lower = Self.linearBernstein(graph.lowerPlaneValues, at: free)
        let upper = Self.linearBernstein(graph.upperPlaneValues, at: free)
        let denominator = upper - lower
        guard denominator.isFinite,
              denominator > 0.0 else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact affine-bilinear graph lost its strictly positive root denominator."
            )
        }
        let dependent = -lower / denominator
        guard dependent.isFinite,
              dependent >= -tolerance.relative,
              dependent <= 1.0 + tolerance.relative else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                residual: max(-dependent, dependent - 1.0),
                message: "An exact affine-bilinear graph left the candidate parameter domain."
            )
        }
        let candidateU = graph.freeIsU ? free : dependent
        let candidateV = graph.freeIsU ? dependent : free
        let candidatePoint = try graph.candidate.point(
            u: Self.actualParameter(candidateU, in: graph.candidate.uDomain),
            v: Self.actualParameter(candidateV, in: graph.candidate.vDomain),
            tolerance: tolerance
        )
        let affineParameters = try Self.affineParameters(
            for: candidatePoint,
            on: graph.affine,
            tolerance: tolerance
        )
        let affinePair = [affineParameters.u, affineParameters.v]
        let candidatePair = [candidateU, candidateV]
        return try SurfaceIntersectionParameterPair(
            values: graph.affineIsFirst
                ? affinePair + candidatePair
                : candidatePair + affinePair
        )
    }

    func actualParameterPair(
        at fraction: Double,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntersectionParameterPair {
        let normalized = try normalizedParameterPair(
            at: fraction,
            tolerance: tolerance
        ).values
        return try SurfaceIntersectionParameterPair(values: [
            Self.actualParameter(normalized[0], in: first.uDomain),
            Self.actualParameter(normalized[1], in: first.vDomain),
            Self.actualParameter(normalized[2], in: second.uDomain),
            Self.actualParameter(normalized[3], in: second.vDomain),
        ])
    }

    func certifies(
        parameterBox: SurfaceIntersectionParameterBox,
        freeParameter: SurfaceIntersectionParameterCoordinate,
        lowerAnchor: SurfaceIntersectionParameterPair,
        midpointAnchor: SurfaceIntersectionParameterPair,
        upperAnchor: SurfaceIntersectionParameterPair,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard freeParameter == self.freeParameter,
              Self.matchesFullDomain(
                  parameterBox: parameterBox,
                  first: first,
                  second: second,
                  tolerance: tolerance
              ) else {
            return false
        }
        let expected = try [0.0, 0.5, 1.0].map {
            try actualParameterPair(
                at: $0,
                first: first,
                second: second,
                tolerance: tolerance
            )
        }
        return zip([lowerAnchor, midpointAnchor, upperAnchor], expected)
            .allSatisfy { stored, reproduced in
                zip(stored.values, reproduced.values).allSatisfy { value, expectedValue in
                    abs(value - expectedValue) <= tolerance.relative
                }
            }
    }

    private static func exactCandidateGraph(
        affine: AffinePatch,
        candidate: BSplineSurface3D,
        affineIsFirst: Bool
    ) -> CandidateGraph? {
        guard candidate.weights.flatMap({ $0 }).allSatisfy({
            $0.isFinite && $0 > 0.0
        }) else {
            return nil
        }
        for freeIsU in [true, false] {
            let lowCorners = freeIsU
                ? [(v: 0, u: 0), (v: 0, u: 1)]
                : [(v: 0, u: 0), (v: 1, u: 0)]
            let highCorners = freeIsU
                ? [(v: 1, u: 0), (v: 1, u: 1)]
                : [(v: 0, u: 1), (v: 1, u: 1)]
            var low = lowCorners.map {
                planeValue(
                    point: candidate.controlPoints[$0.v][$0.u],
                    weight: candidate.weights[$0.v][$0.u],
                    affine: affine
                )
            }
            var high = highCorners.map {
                planeValue(
                    point: candidate.controlPoints[$0.v][$0.u],
                    weight: candidate.weights[$0.v][$0.u],
                    affine: affine
                )
            }
            guard low.allSatisfy({ sign($0) != .indeterminate }),
                  high.allSatisfy({ sign($0) != .indeterminate }) else {
                continue
            }
            if low.allSatisfy(isNonnegative),
               high.allSatisfy(isNonpositive) {
                low = low.map(negated)
                high = high.map(negated)
            }
            guard low.allSatisfy(isNonpositive),
                  high.allSatisfy(isNonnegative),
                  zip(low, high).allSatisfy({
                      sign(FloatingPointExpansion.subtract($0.1, $0.0)) == .positive
                  }) else {
                continue
            }
            let lowHomogeneous = lowCorners.map {
                homogeneous(
                    point: candidate.controlPoints[$0.v][$0.u],
                    weight: candidate.weights[$0.v][$0.u]
                )
            }
            let highHomogeneous = highCorners.map {
                homogeneous(
                    point: candidate.controlPoints[$0.v][$0.u],
                    weight: candidate.weights[$0.v][$0.u]
                )
            }
            let curveControls = rationalQuadraticControls(
                lowHomogeneous: lowHomogeneous,
                highHomogeneous: highHomogeneous,
                lowPlaneValues: low,
                highPlaneValues: high
            )
            guard curveControls.allSatisfy({
                exactAffineParameterBoundsContain(
                    homogeneousPoint: $0,
                    affine: affine
                )
            }) else {
                continue
            }
            return CandidateGraph(
                affineIsFirst: affineIsFirst,
                freeIsU: freeIsU,
                affine: affine,
                candidate: candidate,
                lowerPlaneValues: low.map(FloatingPointExpansion.estimate),
                upperPlaneValues: high.map(FloatingPointExpansion.estimate)
            )
        }
        return nil
    }

    private static func exactAffinePatch(
        _ surface: BSplineSurface3D
    ) -> AffinePatch? {
        let weights = surface.weights.flatMap { $0 }
        guard let weight = weights.first,
              weight.isFinite,
              weight > 0.0,
              weights.allSatisfy({ $0 == weight }) else {
            return nil
        }
        let p00 = surface.controlPoints[0][0]
        let p10 = surface.controlPoints[0][1]
        let p01 = surface.controlPoints[1][0]
        let p11 = surface.controlPoints[1][1]
        let exactU = exactDifference(p10, p00)
        let exactV = exactDifference(p01, p00)
        let parallelogramResidual = exactDifference(
            exactDifference(p11, p10),
            exactDifference(p01, p00)
        )
        guard [parallelogramResidual.x, parallelogramResidual.y, parallelogramResidual.z]
            .allSatisfy({ sign($0) == .zero }) else {
            return nil
        }
        let gramUU = exactDot(exactU, exactU)
        let gramUV = exactDot(exactU, exactV)
        let gramVV = exactDot(exactV, exactV)
        let determinant = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(gramUU, gramVV),
            FloatingPointExpansion.product(gramUV, gramUV)
        )
        guard sign(determinant) == .positive else { return nil }
        return AffinePatch(
            surface: surface,
            origin: p00,
            u: p10 - p00,
            v: p01 - p00,
            exactU: exactU,
            exactV: exactV,
            gramUU: gramUU,
            gramUV: gramUV,
            gramVV: gramVV,
            gramDeterminant: determinant
        )
    }

    private static func exactAffineParameterBoundsContain(
        homogeneousPoint: HomogeneousExpansion,
        affine: AffinePatch
    ) -> Bool {
        guard sign(homogeneousPoint.weight) == .positive else { return false }
        let relative = ExpansionVector3(
            x: FloatingPointExpansion.subtract(
                homogeneousPoint.x,
                FloatingPointExpansion.product([affine.origin.x], homogeneousPoint.weight)
            ),
            y: FloatingPointExpansion.subtract(
                homogeneousPoint.y,
                FloatingPointExpansion.product([affine.origin.y], homogeneousPoint.weight)
            ),
            z: FloatingPointExpansion.subtract(
                homogeneousPoint.z,
                FloatingPointExpansion.product([affine.origin.z], homogeneousPoint.weight)
            )
        )
        let dotU = exactDot(relative, affine.exactU)
        let dotV = exactDot(relative, affine.exactV)
        let uNumerator = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(dotU, affine.gramVV),
            FloatingPointExpansion.product(dotV, affine.gramUV)
        )
        let vNumerator = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(dotV, affine.gramUU),
            FloatingPointExpansion.product(dotU, affine.gramUV)
        )
        let denominator = FloatingPointExpansion.product(
            homogeneousPoint.weight,
            affine.gramDeterminant
        )
        return isNonnegative(uNumerator)
            && isNonnegative(FloatingPointExpansion.subtract(denominator, uNumerator))
            && isNonnegative(vNumerator)
            && isNonnegative(FloatingPointExpansion.subtract(denominator, vNumerator))
    }

    private static func rationalQuadraticControls(
        lowHomogeneous: [HomogeneousExpansion],
        highHomogeneous: [HomogeneousExpansion],
        lowPlaneValues: [[Double]],
        highPlaneValues: [[Double]]
    ) -> [HomogeneousExpansion] {
        let first = lowHomogeneous[0]
            .scaled(by: highPlaneValues[0])
            .subtracting(highHomogeneous[0].scaled(by: lowPlaneValues[0]))
        let middleSum = lowHomogeneous[0].scaled(by: highPlaneValues[1])
            .adding(lowHomogeneous[1].scaled(by: highPlaneValues[0]))
            .subtracting(highHomogeneous[0].scaled(by: lowPlaneValues[1]))
            .subtracting(highHomogeneous[1].scaled(by: lowPlaneValues[0]))
        let middle = middleSum.scaled(by: [0.5])
        let last = lowHomogeneous[1]
            .scaled(by: highPlaneValues[1])
            .subtracting(highHomogeneous[1].scaled(by: lowPlaneValues[1]))
        return [first, middle, last]
    }

    private static func planeValue(
        point: Point3D,
        weight: Double,
        affine: AffinePatch
    ) -> [Double] {
        FloatingPointExpansion.product(
            exactTriple(
                affine.exactU,
                affine.exactV,
                exactDifference(point, affine.origin)
            ),
            [weight]
        )
    }

    private static func homogeneous(
        point: Point3D,
        weight: Double
    ) -> HomogeneousExpansion {
        HomogeneousExpansion(
            x: FloatingPointExpansion.product([point.x], [weight]),
            y: FloatingPointExpansion.product([point.y], [weight]),
            z: FloatingPointExpansion.product([point.z], [weight]),
            weight: [weight]
        )
    }

    private static func affineParameters(
        for point: Point3D,
        on affine: AffinePatch,
        tolerance: ModelingTolerance
    ) throws -> (u: Double, v: Double) {
        let offset = point - affine.origin
        let uu = affine.u.dot(affine.u)
        let uv = affine.u.dot(affine.v)
        let vv = affine.v.dot(affine.v)
        let determinant = uu * vv - uv * uv
        guard determinant.isFinite,
              determinant > 0.0 else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An exact affine-bilinear graph lost its affine parameter inverse."
            )
        }
        let offsetU = offset.dot(affine.u)
        let offsetV = offset.dot(affine.v)
        let u = (offsetU * vv - offsetV * uv) / determinant
        let v = (offsetV * uu - offsetU * uv) / determinant
        guard u.isFinite,
              v.isFinite,
              u >= -tolerance.relative,
              u <= 1.0 + tolerance.relative,
              v >= -tolerance.relative,
              v <= 1.0 + tolerance.relative else {
            throw certificateFailure(
                tolerance: tolerance,
                residual: max(-u, u - 1.0, -v, v - 1.0),
                message: "An exact affine-bilinear graph left the affine parameter domain."
            )
        }
        return (min(max(u, 0.0), 1.0), min(max(v, 0.0), 1.0))
    }

    private static func matchesFullDomain(
        parameterBox: SurfaceIntersectionParameterBox,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let expected = [first.uDomain, first.vDomain, second.uDomain, second.vDomain]
        return zip(parameterBox.intervals, expected).allSatisfy { interval, domain in
            guard case let .closed(lower, upper) = domain else { return false }
            return abs(interval.lower - lower) <= tolerance.relative
                && abs(interval.upper - upper) <= tolerance.relative
        }
    }

    private static func actualParameter(
        _ normalized: Double,
        in domain: ParameterDomain
    ) -> Double {
        guard case let .closed(lower, upper) = domain else { return .nan }
        return lower + (upper - lower) * normalized
    }

    private static func linearBernstein(
        _ coefficients: [Double],
        at parameter: Double
    ) -> Double {
        coefficients[0] * (1.0 - parameter) + coefficients[1] * parameter
    }

    private static func isSingleBilinearBezier(
        _ surface: BSplineSurface3D
    ) -> Bool {
        surface.uDegree == 1
            && surface.vDegree == 1
            && surface.uControlPointCount == 2
            && surface.vControlPointCount == 2
            && isSingleBezierKnotVector(surface.uKnots)
            && isSingleBezierKnotVector(surface.vKnots)
    }

    private static func isSingleBezierKnotVector(_ knots: [Double]) -> Bool {
        guard knots.count == 4,
              let lower = knots.first,
              let upper = knots.last,
              lower.isFinite,
              upper.isFinite,
              upper > lower else {
            return false
        }
        return knots[0] == lower
            && knots[1] == lower
            && knots[2] == upper
            && knots[3] == upper
    }

    private static func exactDifference(
        _ lhs: Point3D,
        _ rhs: Point3D
    ) -> ExpansionVector3 {
        ExpansionVector3(
            x: FloatingPointExpansion.difference(lhs.x, rhs.x),
            y: FloatingPointExpansion.difference(lhs.y, rhs.y),
            z: FloatingPointExpansion.difference(lhs.z, rhs.z)
        )
    }

    private static func exactDifference(
        _ lhs: ExpansionVector3,
        _ rhs: ExpansionVector3
    ) -> ExpansionVector3 {
        ExpansionVector3(
            x: FloatingPointExpansion.subtract(lhs.x, rhs.x),
            y: FloatingPointExpansion.subtract(lhs.y, rhs.y),
            z: FloatingPointExpansion.subtract(lhs.z, rhs.z)
        )
    }

    private static func exactDot(
        _ lhs: ExpansionVector3,
        _ rhs: ExpansionVector3
    ) -> [Double] {
        FloatingPointExpansion.sum(
            FloatingPointExpansion.sum(
                FloatingPointExpansion.product(lhs.x, rhs.x),
                FloatingPointExpansion.product(lhs.y, rhs.y)
            ),
            FloatingPointExpansion.product(lhs.z, rhs.z)
        )
    }

    private static func exactTriple(
        _ first: ExpansionVector3,
        _ second: ExpansionVector3,
        _ third: ExpansionVector3
    ) -> [Double] {
        let crossX = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(second.y, third.z),
            FloatingPointExpansion.product(second.z, third.y)
        )
        let crossY = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(second.z, third.x),
            FloatingPointExpansion.product(second.x, third.z)
        )
        let crossZ = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(second.x, third.y),
            FloatingPointExpansion.product(second.y, third.x)
        )
        return FloatingPointExpansion.sum(
            FloatingPointExpansion.sum(
                FloatingPointExpansion.product(first.x, crossX),
                FloatingPointExpansion.product(first.y, crossY)
            ),
            FloatingPointExpansion.product(first.z, crossZ)
        )
    }

    private static func sign(_ value: [Double]) -> RobustSign {
        FloatingPointExpansion.sign(value)
    }

    private static func isNonnegative(_ value: [Double]) -> Bool {
        let valueSign = sign(value)
        return valueSign == .positive || valueSign == .zero
    }

    private static func isNonpositive(_ value: [Double]) -> Bool {
        let valueSign = sign(value)
        return valueSign == .negative || valueSign == .zero
    }

    private static func negated(_ value: [Double]) -> [Double] {
        value.map { -$0 }
    }

    private static func certificateFailure(
        tolerance: ModelingTolerance,
        residual: Double? = nil,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
