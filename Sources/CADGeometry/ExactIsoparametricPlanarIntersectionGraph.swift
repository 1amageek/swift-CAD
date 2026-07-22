import CADCore
import Foundation

/// A complete graph certificate for an internal isocurve that is the unique intersection with a
/// rational affine-plane patch.
///
/// The source surface contract is intentionally strict: a quadratic two-span parameter direction
/// has one exactly coplanar middle control layer, the two lower layers are strictly on one side,
/// and the two upper layers are strictly on the other side. Nonnegative B-spline basis functions
/// then prove that the middle knot is the entire zero locus. The planar patch contract requires an
/// exact parallelogram and positive rational weights. Its Jacobian numerator has four strictly
/// positive Bernstein coefficients, proving a bijection between its parameter square and affine
/// plane coordinates.
struct ExactIsoparametricPlanarIntersectionGraph: Sendable {
    struct Cell: Sendable {
        let normalizedBounds: [(lower: Double, upper: Double)]
        let freeParameter: SurfaceIntersectionParameterCoordinate
        fileprivate let sourceULower: Double
        fileprivate let sourceUUpper: Double
    }

    private struct ExpansionVector3 {
        let x: [Double]
        let y: [Double]
        let z: [Double]
    }

    private struct ExactPlanePatch {
        let origin: Point3D
        let u: Vector3D
        let v: Vector3D
        let exactU: ExpansionVector3
        let exactV: ExpansionVector3
        let gramUU: [Double]
        let gramUV: [Double]
        let gramVV: [Double]
        let gramDeterminant: [Double]
        let weights: [[Double]]
    }

    private struct SourceSurface {
        let surface: BSplineSurface3D
        let fixedV: Double
        let lowerV: Double
        let uSpans: [(lower: Double, upper: Double)]
    }

    let cells: [Cell]
    private let sourceIsFirst: Bool
    private let source: SourceSurface
    private let plane: ExactPlanePatch

    static func certified(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> ExactIsoparametricPlanarIntersectionGraph? {
        try tolerance.validate()
        if let plane = exactPlanePatch(second),
           let source = exactSourceSurface(first, intersecting: plane) {
            return make(source: source, plane: plane, sourceIsFirst: true)
        }
        if let plane = exactPlanePatch(first),
           let source = exactSourceSurface(second, intersecting: plane) {
            return make(source: source, plane: plane, sourceIsFirst: false)
        }
        return nil
    }

    func normalizedParameterPair(
        in cell: Cell,
        at fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntersectionParameterPair {
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clamped = min(max(fraction, 0.0), 1.0)
        let sourceU = cell.sourceULower
            + (cell.sourceUUpper - cell.sourceULower) * clamped
        let point = try source.surface.point(
            u: sourceU,
            v: source.fixedV,
            tolerance: tolerance
        )
        let planeParameters = try planarParameters(
            for: point,
            tolerance: tolerance
        )
        let sourceNormalized = [
            Self.normalizedParameter(sourceU, in: source.surface.uDomain),
            Self.normalizedParameter(source.fixedV, in: source.surface.vDomain),
        ]
        let planeNormalized = [planeParameters.u, planeParameters.v]
        return try SurfaceIntersectionParameterPair(
            values: sourceIsFirst
                ? sourceNormalized + planeNormalized
                : planeNormalized + sourceNormalized
        )
    }

    func actualParameterPair(
        in cell: Cell,
        at fraction: Double,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntersectionParameterPair {
        let normalized = try normalizedParameterPair(
            in: cell,
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
        for cell in cells where cell.freeParameter == freeParameter {
            guard Self.matches(
                parameterBox,
                normalizedBounds: cell.normalizedBounds,
                first: first,
                second: second,
                tolerance: tolerance
            ) else {
                continue
            }
            let expected = try [0.0, 0.5, 1.0].map {
                try actualParameterPair(
                    in: cell,
                    at: $0,
                    first: first,
                    second: second,
                    tolerance: tolerance
                )
            }
            return zip([lowerAnchor, midpointAnchor, upperAnchor], expected)
                .allSatisfy { stored, reproduced in
                    zip(stored.values, reproduced.values).allSatisfy {
                        abs($0.0 - $0.1) <= tolerance.relative
                    }
                }
        }
        return false
    }

    private static func make(
        source: SourceSurface,
        plane: ExactPlanePatch,
        sourceIsFirst: Bool
    ) -> ExactIsoparametricPlanarIntersectionGraph {
        let fixedV = normalizedParameter(source.fixedV, in: source.surface.vDomain)
        let lowerV = normalizedParameter(source.lowerV, in: source.surface.vDomain)
        let cells = source.uSpans.map { span in
            let sourceBounds = [
                (
                    lower: normalizedParameter(span.lower, in: source.surface.uDomain),
                    upper: normalizedParameter(span.upper, in: source.surface.uDomain)
                ),
                (lower: lowerV, upper: fixedV),
            ]
            let planeBounds = [
                (lower: 0.0, upper: 1.0),
                (lower: 0.0, upper: 1.0),
            ]
            return Cell(
                normalizedBounds: sourceIsFirst
                    ? sourceBounds + planeBounds
                    : planeBounds + sourceBounds,
                freeParameter: sourceIsFirst ? .firstU : .secondU,
                sourceULower: span.lower,
                sourceUUpper: span.upper
            )
        }
        return ExactIsoparametricPlanarIntersectionGraph(
            cells: cells,
            sourceIsFirst: sourceIsFirst,
            source: source,
            plane: plane
        )
    }

    private static func exactSourceSurface(
        _ surface: BSplineSurface3D,
        intersecting plane: ExactPlanePatch
    ) -> SourceSurface? {
        guard surface.vDegree == 2,
              surface.vControlPointCount == 5,
              surface.vKnots.count == 8,
              surface.weights.flatMap({ $0 }).allSatisfy({
                  $0.isFinite && $0 > 0.0
              }) else {
            return nil
        }
        let knots = surface.vKnots
        let lower = knots[0]
        let middle = knots[3]
        let upper = knots[5]
        guard lower.isFinite,
              middle.isFinite,
              upper.isFinite,
              lower < middle,
              middle < upper,
              knots[0] == lower,
              knots[1] == lower,
              knots[2] == lower,
              knots[3] == middle,
              knots[4] == middle,
              knots[5] == upper,
              knots[6] == upper,
              knots[7] == upper else {
            return nil
        }
        let signs = surface.controlPoints.map { row in
            row.map {
                FloatingPointExpansion.sign(planeValue($0, plane: plane))
            }
        }
        let crossesForward = signs[0].allSatisfy({ $0 == .negative })
            && signs[1].allSatisfy({ $0 == .negative })
            && signs[3].allSatisfy({ $0 == .positive })
            && signs[4].allSatisfy({ $0 == .positive })
        let crossesReverse = signs[0].allSatisfy({ $0 == .positive })
            && signs[1].allSatisfy({ $0 == .positive })
            && signs[3].allSatisfy({ $0 == .negative })
            && signs[4].allSatisfy({ $0 == .negative })
        guard signs[2].allSatisfy({ $0 == .zero }),
              crossesForward || crossesReverse else {
            return nil
        }
        guard surface.controlPoints[2].allSatisfy({
            exactAffineCoordinatesContain($0, plane: plane)
        }) else {
            return nil
        }
        let uSpans = nonzeroSpans(
            knots: surface.uKnots,
            degree: surface.uDegree
        )
        guard uSpans.isEmpty == false else { return nil }
        return SourceSurface(
            surface: surface,
            fixedV: middle,
            lowerV: lower,
            uSpans: uSpans
        )
    }

    private static func exactPlanePatch(
        _ surface: BSplineSurface3D
    ) -> ExactPlanePatch? {
        guard surface.uDegree == 1,
              surface.vDegree == 1,
              surface.uControlPointCount == 2,
              surface.vControlPointCount == 2,
              isSingleLinearBezier(surface.uKnots),
              isSingleLinearBezier(surface.vKnots) else {
            return nil
        }
        let weights = surface.weights
        let flatWeights = weights.flatMap { $0 }
        let jacobianCoefficients = [
            flatWeights[0] * flatWeights[1] * flatWeights[2],
            flatWeights[0] * flatWeights[1] * flatWeights[3],
            flatWeights[0] * flatWeights[2] * flatWeights[3],
            flatWeights[1] * flatWeights[2] * flatWeights[3],
        ]
        guard flatWeights.allSatisfy({
            $0.isFinite && $0 > 0.0
        }), jacobianCoefficients.allSatisfy({
            $0.isFinite && $0 > 0.0
        }) else {
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
            .allSatisfy({ FloatingPointExpansion.sign($0) == .zero }) else {
            return nil
        }
        let gramUU = exactDot(exactU, exactU)
        let gramUV = exactDot(exactU, exactV)
        let gramVV = exactDot(exactV, exactV)
        let determinant = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(gramUU, gramVV),
            FloatingPointExpansion.product(gramUV, gramUV)
        )
        guard FloatingPointExpansion.sign(determinant) == .positive else {
            return nil
        }
        return ExactPlanePatch(
            origin: p00,
            u: p10 - p00,
            v: p01 - p00,
            exactU: exactU,
            exactV: exactV,
            gramUU: gramUU,
            gramUV: gramUV,
            gramVV: gramVV,
            gramDeterminant: determinant,
            weights: weights
        )
    }

    private func planarParameters(
        for point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Double, v: Double) {
        let offset = point - plane.origin
        let uu = plane.u.dot(plane.u)
        let uv = plane.u.dot(plane.v)
        let vv = plane.v.dot(plane.v)
        let determinant = uu * vv - uv * uv
        guard determinant.isFinite,
              determinant > 0.0 else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar graph lost its affine inverse."
            )
        }
        let offsetU = offset.dot(plane.u)
        let offsetV = offset.dot(plane.v)
        let affineU = (offsetU * vv - offsetV * uv) / determinant
        let affineV = (offsetV * uu - offsetU * uv) / determinant
        let parameters = try inversePlanarMap(
            affineU: affineU,
            affineV: affineV,
            tolerance: tolerance
        )
        let u = parameters.u
        let v = parameters.v
        guard u.isFinite,
              v.isFinite,
              u >= -tolerance.relative,
              u <= 1.0 + tolerance.relative,
              v >= -tolerance.relative,
              v <= 1.0 + tolerance.relative else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                residual: max(-u, u - 1.0, -v, v - 1.0),
                message: "An exact isoparametric-planar graph left the planar patch."
            )
        }
        return (min(max(u, 0.0), 1.0), min(max(v, 0.0), 1.0))
    }

    private func inversePlanarMap(
        affineU: Double,
        affineV: Double,
        tolerance: ModelingTolerance
    ) throws -> (u: Double, v: Double) {
        var u = min(max(affineU, 0.0), 1.0)
        var v = min(max(affineV, 0.0), 1.0)
        var previousResidual = Double.infinity
        for _ in 0..<32 {
            let evaluation = Self.planarMap(
                u: u,
                v: v,
                weights: plane.weights
            )
            let residualU = evaluation.u - affineU
            let residualV = evaluation.v - affineV
            let residual = hypot(residualU, residualV)
            if residual <= tolerance.relative {
                return (u, v)
            }
            let determinant = evaluation.du.x * evaluation.dv.y
                - evaluation.dv.x * evaluation.du.y
            guard determinant.isFinite,
                  determinant > Double.leastNonzeroMagnitude else {
                throw Self.certificateFailure(
                    tolerance: tolerance,
                    residual: residual,
                    message: "An exact rational planar inverse encountered a singular Jacobian."
                )
            }
            let deltaU = (-residualU * evaluation.dv.y
                + residualV * evaluation.dv.x) / determinant
            let deltaV = (-evaluation.du.x * residualV
                + evaluation.du.y * residualU) / determinant
            var accepted: (u: Double, v: Double, residual: Double)?
            var scale = 1.0
            for _ in 0..<16 {
                let candidateU = min(max(u + deltaU * scale, 0.0), 1.0)
                let candidateV = min(max(v + deltaV * scale, 0.0), 1.0)
                let candidate = Self.planarMap(
                    u: candidateU,
                    v: candidateV,
                    weights: plane.weights
                )
                let candidateResidual = hypot(
                    candidate.u - affineU,
                    candidate.v - affineV
                )
                if candidateResidual < residual {
                    accepted = (candidateU, candidateV, candidateResidual)
                    break
                }
                scale *= 0.5
            }
            guard let accepted else {
                throw Self.certificateFailure(
                    tolerance: tolerance,
                    residual: residual,
                    message: "An exact rational planar inverse did not decrease its residual."
                )
            }
            u = accepted.u
            v = accepted.v
            previousResidual = accepted.residual
        }
        throw Self.certificateFailure(
            tolerance: tolerance,
            residual: previousResidual,
            message: "An exact rational planar inverse exceeded its iteration limit."
        )
    }

    private static func planarMap(
        u: Double,
        v: Double,
        weights: [[Double]]
    ) -> (u: Double, v: Double, du: Point2D, dv: Point2D) {
        let a = weights[0][0]
        let b = weights[0][1]
        let c = weights[1][0]
        let d = weights[1][1]
        let lowerUWeight = a * (1.0 - v) + c * v
        let upperUWeight = b * (1.0 - v) + d * v
        let lowerVWeight = a * (1.0 - u) + b * u
        let upperVWeight = c * (1.0 - u) + d * u
        let denominator = (1.0 - u) * lowerUWeight + u * upperUWeight
        let numeratorU = u * upperUWeight
        let numeratorV = v * upperVWeight
        let denominatorU = upperUWeight - lowerUWeight
        let denominatorV = upperVWeight - lowerVWeight
        let numeratorUU = upperUWeight
        let numeratorUV = u * (d - b)
        let numeratorVU = v * (d - c)
        let numeratorVV = upperVWeight
        let denominatorSquared = denominator * denominator
        return (
            numeratorU / denominator,
            numeratorV / denominator,
            Point2D(
                x: (numeratorUU * denominator - numeratorU * denominatorU)
                    / denominatorSquared,
                y: (numeratorVU * denominator - numeratorV * denominatorU)
                    / denominatorSquared
            ),
            Point2D(
                x: (numeratorUV * denominator - numeratorU * denominatorV)
                    / denominatorSquared,
                y: (numeratorVV * denominator - numeratorV * denominatorV)
                    / denominatorSquared
            )
        )
    }

    private static func exactAffineCoordinatesContain(
        _ point: Point3D,
        plane: ExactPlanePatch
    ) -> Bool {
        let relative = exactDifference(point, plane.origin)
        let dotU = exactDot(relative, plane.exactU)
        let dotV = exactDot(relative, plane.exactV)
        let uNumerator = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(dotU, plane.gramVV),
            FloatingPointExpansion.product(dotV, plane.gramUV)
        )
        let vNumerator = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(dotV, plane.gramUU),
            FloatingPointExpansion.product(dotU, plane.gramUV)
        )
        return isNonnegative(uNumerator)
            && isNonnegative(FloatingPointExpansion.subtract(
                plane.gramDeterminant,
                uNumerator
            ))
            && isNonnegative(vNumerator)
            && isNonnegative(FloatingPointExpansion.subtract(
                plane.gramDeterminant,
                vNumerator
            ))
    }

    private static func planeValue(
        _ point: Point3D,
        plane: ExactPlanePatch
    ) -> [Double] {
        exactTriple(
            plane.exactU,
            plane.exactV,
            exactDifference(point, plane.origin)
        )
    }

    private static func nonzeroSpans(
        knots: [Double],
        degree: Int
    ) -> [(lower: Double, upper: Double)] {
        guard degree >= 0,
              knots.count >= 2 * (degree + 1) else {
            return []
        }
        var result: [(lower: Double, upper: Double)] = []
        for index in degree..<(knots.count - degree - 1) {
            let lower = knots[index]
            let upper = knots[index + 1]
            if lower.isFinite,
               upper.isFinite,
               upper > lower {
                result.append((lower, upper))
            }
        }
        return result
    }

    private static func isSingleLinearBezier(_ knots: [Double]) -> Bool {
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

    private static func matches(
        _ parameterBox: SurfaceIntersectionParameterBox,
        normalizedBounds: [(lower: Double, upper: Double)],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let domains = [first.uDomain, first.vDomain, second.uDomain, second.vDomain]
        return zip(
            parameterBox.intervals,
            zip(normalizedBounds, domains)
        ).allSatisfy { interval, expectedAndDomain in
            let expected = expectedAndDomain.0
            let domain = expectedAndDomain.1
            let lower = actualParameter(expected.lower, in: domain)
            let upper = actualParameter(expected.upper, in: domain)
            return abs(interval.lower - lower) <= tolerance.relative
                && abs(interval.upper - upper) <= tolerance.relative
        }
    }

    private static func normalizedParameter(
        _ actual: Double,
        in domain: ParameterDomain
    ) -> Double {
        guard case let .closed(lower, upper) = domain else { return .nan }
        return (actual - lower) / (upper - lower)
    }

    private static func actualParameter(
        _ normalized: Double,
        in domain: ParameterDomain
    ) -> Double {
        guard case let .closed(lower, upper) = domain else { return .nan }
        return lower + (upper - lower) * normalized
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

    private static func isNonnegative(_ value: [Double]) -> Bool {
        let sign = FloatingPointExpansion.sign(value)
        return sign == .positive || sign == .zero
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
