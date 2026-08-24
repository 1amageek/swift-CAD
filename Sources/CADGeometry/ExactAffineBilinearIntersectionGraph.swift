import CADCore
import Foundation

/// An exact graph certificate for an affine bilinear patch intersecting a rational bilinear patch.
///
/// The certificate is deliberately structural. It is available only when one operand is an exact
/// affine parallelogram and the other operand's plane equation has one sign on each side of a
/// parameter direction. The latter proves one and only one dependent parameter for every free
/// parameter. Exact expansion signs also prove that the resulting rational quadratic curve remains
/// inside the affine patch.
struct ExactAffineBilinearIntersectionGraph: Sendable {
    enum PlaneRelation: Sendable, Equatable {
        case coincident
        case disjoint
        case transverse
    }

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

    enum BoundedIntersection: Sendable {
        case disjoint
        case point(SurfaceIntersectionParameterPair)
        case segment(ExactAffineBilinearIntersectionGraph)
    }

    private struct ExactRatio {
        let numerator: [Double]
        let denominator: [Double]

        init?(numerator: [Double], denominator: [Double]) {
            switch FloatingPointExpansion.sign(denominator) {
            case .positive:
                self.numerator = numerator
                self.denominator = denominator
            case .negative:
                self.numerator = numerator.map { -$0 }
                self.denominator = denominator.map { -$0 }
            case .zero, .indeterminate:
                return nil
            }
        }

        func compared(to other: ExactRatio) -> RobustSign {
            FloatingPointExpansion.sign(FloatingPointExpansion.subtract(
                FloatingPointExpansion.product(numerator, other.denominator),
                FloatingPointExpansion.product(other.numerator, denominator)
            ))
        }

        var estimate: Double {
            FloatingPointExpansion.estimate(numerator)
                / FloatingPointExpansion.estimate(denominator)
        }
    }

    private struct SectionEndpoint {
        let point: HomogeneousExpansion
        let coordinate: ExactRatio
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

    private enum Mapping: Sendable {
        case candidate(CandidateGraph)
        case affineSegment(
            lower: SurfaceIntersectionParameterPair,
            upper: SurfaceIntersectionParameterPair
        )
    }

    let freeParameter: SurfaceIntersectionParameterCoordinate
    let normalizedBounds: [(lower: Double, upper: Double)]
    private let mapping: Mapping

    var exactAffineSegmentEndpoints: (
        lower: SurfaceIntersectionParameterPair,
        upper: SurfaceIntersectionParameterPair
    )? {
        guard case let .affineSegment(lower, upper) = mapping else {
            return nil
        }
        return (lower, upper)
    }

    static func planeRelation(
        first: BSplineSurface3D,
        second: BSplineSurface3D
    ) -> PlaneRelation? {
        guard isSingleBilinearBezier(first),
              isSingleBilinearBezier(second),
              let firstAffine = exactAffinePatch(first),
              let secondAffine = exactAffinePatch(second) else {
            return nil
        }
        let secondUDistance = sign(exactTriple(
            firstAffine.exactU,
            firstAffine.exactV,
            secondAffine.exactU
        ))
        let secondVDistance = sign(exactTriple(
            firstAffine.exactU,
            firstAffine.exactV,
            secondAffine.exactV
        ))
        guard secondUDistance != .indeterminate,
              secondVDistance != .indeterminate else {
            return nil
        }
        guard secondUDistance == .zero,
              secondVDistance == .zero else {
            return .transverse
        }
        let originDistance = sign(exactTriple(
            firstAffine.exactU,
            firstAffine.exactV,
            exactDifference(secondAffine.origin, firstAffine.origin)
        ))
        guard originDistance != .indeterminate else { return nil }
        return originDistance == .zero ? .coincident : .disjoint
    }

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
        if let firstAffine, let secondAffine {
            switch try boundedAffineIntersection(
                first: firstAffine,
                second: secondAffine,
                tolerance: tolerance
            ) {
            case let .segment(graph):
                return graph
            case .disjoint, .point:
                return nil
            }
        }
        if let affine = firstAffine,
           let graph = exactCandidateGraph(
               affine: affine,
               candidate: second,
               affineIsFirst: true
           ) {
            return ExactAffineBilinearIntersectionGraph(
                freeParameter: graph.freeIsU ? .secondU : .secondV,
                normalizedBounds: Array(
                    repeating: (lower: 0.0, upper: 1.0),
                    count: 4
                ),
                mapping: .candidate(graph)
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
                normalizedBounds: Array(
                    repeating: (lower: 0.0, upper: 1.0),
                    count: 4
                ),
                mapping: .candidate(graph)
            )
        }
        return nil
    }

    static func boundedAffineIntersection(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> BoundedIntersection? {
        try tolerance.validate()
        guard isSingleBilinearBezier(first),
              isSingleBilinearBezier(second),
              let firstAffine = exactAffinePatch(first),
              let secondAffine = exactAffinePatch(second),
              planeRelation(first: first, second: second) == .transverse else {
            return nil
        }
        return try boundedAffineIntersection(
            first: firstAffine,
            second: secondAffine,
            tolerance: tolerance
        )
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
        let clamped = min(max(fraction, 0.0), 1.0)
        switch mapping {
        case let .affineSegment(lower, upper):
            return try SurfaceIntersectionParameterPair(values: zip(
                lower.values,
                upper.values
            ).map { lowerValue, upperValue in
                lowerValue + (upperValue - lowerValue) * clamped
            })
        case let .candidate(graph):
            return try candidateParameterPair(
                graph: graph,
                free: clamped,
                tolerance: tolerance
            )
        }
    }

    private func candidateParameterPair(
        graph: CandidateGraph,
        free: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntersectionParameterPair {
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
              Self.matches(
                  parameterBox: parameterBox,
                  normalizedBounds: normalizedBounds,
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

    func certifiedImplicitCurve(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionCurve {
        let domains = try BoundedSurfaceParameterDomainMap(
            first: first,
            second: second,
            tolerance: tolerance
        )
        let lower = domains.actual(normalizedBounds.map(\.lower))
        let upper = domains.actual(normalizedBounds.map(\.upper))
        let anchors = try [0.0, 0.5, 1.0].map {
            try actualParameterPair(
                at: $0,
                first: first,
                second: second,
                tolerance: tolerance
            )
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: lower[0], upper: upper[0]),
                firstV: try ScalarInterval(lower: lower[1], upper: upper[1]),
                secondU: try ScalarInterval(lower: lower[2], upper: upper[2]),
                secondV: try ScalarInterval(lower: lower[3], upper: upper[3])
            ),
            freeParameter: freeParameter,
            direction: .forward,
            lowerAnchor: anchors[0],
            midpointAnchor: anchors[1],
            upperAnchor: anchors[2],
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
        return try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [cell],
            isClosed: false,
            tolerance: tolerance
        )
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
        guard let parameterization = ExactAffineBSplineSurfacePatch(surface) else {
            return nil
        }
        let p00 = parameterization.origin
        let p10 = surface.controlPoints[0][1]
        let p01 = surface.controlPoints[1][0]
        let exactU = exactDifference(p10, p00)
        let exactV = exactDifference(p01, p00)
        let gramUU = exactDot(exactU, exactU)
        let gramUV = exactDot(exactU, exactV)
        let gramVV = exactDot(exactV, exactV)
        let determinant = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(gramUU, gramVV),
            FloatingPointExpansion.product(gramUV, gramUV)
        )
        return AffinePatch(
            surface: surface,
            origin: p00,
            u: parameterization.uDirection,
            v: parameterization.vDirection,
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

    private static func matches(
        parameterBox: SurfaceIntersectionParameterBox,
        normalizedBounds: [(lower: Double, upper: Double)],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let domains = [first.uDomain, first.vDomain, second.uDomain, second.vDomain]
        guard normalizedBounds.count == domains.count else { return false }
        return zip(
            zip(parameterBox.intervals, normalizedBounds),
            domains
        ).allSatisfy { values, domain in
            let (interval, normalized) = values
            guard case let .closed(lower, upper) = domain else { return false }
            let span = upper - lower
            let expectedLower = lower + span * normalized.lower
            let expectedUpper = lower + span * normalized.upper
            return abs(interval.lower - expectedLower) <= tolerance.relative
                && abs(interval.upper - expectedUpper) <= tolerance.relative
        }
    }

    private static func parameterDomainSpans(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        try [first.uDomain, first.vDomain, second.uDomain, second.vDomain].map { domain in
            guard case let .closed(lower, upper) = domain,
                  upper - lower > tolerance.relative else {
                throw certificateFailure(
                    tolerance: tolerance,
                    message: "An exact affine graph requires non-degenerate closed parameter domains."
                )
            }
            return upper - lower
        }
    }

    private static func boundedAffineIntersection(
        first: AffinePatch,
        second: AffinePatch,
        tolerance: ModelingTolerance
    ) throws -> BoundedIntersection {
        let firstSection = try exactSection(
            patch: first,
            cuttingPlane: second,
            tolerance: tolerance
        )
        let secondSection = try exactSection(
            patch: second,
            cuttingPlane: first,
            tolerance: tolerance
        )
        guard firstSection.isEmpty == false,
              secondSection.isEmpty == false else {
            return .disjoint
        }

        let allPoints = firstSection + secondSection
        let coordinateIndex = try nonconstantFirstPatchCoordinate(
            points: allPoints,
            first: first,
            tolerance: tolerance
        )
        let firstRange = try sectionRange(
            points: firstSection,
            coordinateIndex: coordinateIndex,
            first: first,
            tolerance: tolerance
        )
        let secondRange = try sectionRange(
            points: secondSection,
            coordinateIndex: coordinateIndex,
            first: first,
            tolerance: tolerance
        )
        let lower = try maximumEndpoint(
            firstRange.lower,
            secondRange.lower,
            tolerance: tolerance
        )
        let upper = try minimumEndpoint(
            firstRange.upper,
            secondRange.upper,
            tolerance: tolerance
        )
        switch lower.coordinate.compared(to: upper.coordinate) {
        case .positive:
            return .disjoint
        case .zero:
            return .point(try normalizedParameterPair(
                for: lower.point,
                first: first,
                second: second,
                tolerance: tolerance
            ))
        case .negative:
            break
        case .indeterminate:
            throw certificateFailure(
                tolerance: tolerance,
                message: "Exact affine bounded-intersection ordering was indeterminate."
            )
        }

        let lowerValues = try normalizedParameterPair(
            for: lower.point,
            first: first,
            second: second,
            tolerance: tolerance
        ).values
        let upperValues = try normalizedParameterPair(
            for: upper.point,
            first: first,
            second: second,
            tolerance: tolerance
        ).values
        let spans = zip(lowerValues, upperValues).map { abs($0.1 - $0.0) }
        let domainSpans = try parameterDomainSpans(
            first: first.surface,
            second: second.surface,
            tolerance: tolerance
        )
        let actualSpans = zip(spans, domainSpans).map { $0.0 * $0.1 }
        guard let freeIndex = actualSpans.indices.max(by: {
            actualSpans[$0] < actualSpans[$1]
        }), actualSpans[freeIndex] > 0.0 else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An exact nonzero affine segment could not be represented in Double parameters."
            )
        }
        let orderedLower: [Double]
        let orderedUpper: [Double]
        if lowerValues[freeIndex] <= upperValues[freeIndex] {
            orderedLower = lowerValues
            orderedUpper = upperValues
        } else {
            orderedLower = upperValues
            orderedUpper = lowerValues
        }
        let normalizedBounds = try certifiedBounds(
            lower: orderedLower,
            upper: orderedUpper,
            surfaces: [first.surface, second.surface],
            freeIndex: freeIndex,
            tolerance: tolerance
        )
        guard let freeParameter = SurfaceIntersectionParameterCoordinate(
            rawValue: freeIndex
        ) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An exact affine segment selected an invalid free parameter."
            )
        }
        return .segment(ExactAffineBilinearIntersectionGraph(
            freeParameter: freeParameter,
            normalizedBounds: normalizedBounds,
            mapping: .affineSegment(
                lower: try SurfaceIntersectionParameterPair(values: orderedLower),
                upper: try SurfaceIntersectionParameterPair(values: orderedUpper)
            )
        ))
    }

    private static func exactSection(
        patch: AffinePatch,
        cuttingPlane: AffinePatch,
        tolerance: ModelingTolerance
    ) throws -> [HomogeneousExpansion] {
        let p00 = patch.surface.controlPoints[0][0]
        let p10 = patch.surface.controlPoints[0][1]
        let p01 = patch.surface.controlPoints[1][0]
        let p11 = patch.surface.controlPoints[1][1]
        let corners = [p00, p10, p11, p01]
        let values = corners.map {
            planeValue(point: $0, weight: 1.0, affine: cuttingPlane)
        }
        guard values.allSatisfy({ sign($0) != .indeterminate }) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "Exact affine boundary signs were indeterminate."
            )
        }
        var endpoints: [HomogeneousExpansion] = []
        for index in corners.indices {
            let next = (index + 1) % corners.count
            let firstSign = sign(values[index])
            let secondSign = sign(values[next])
            if firstSign == .zero {
                appendUnique(homogeneous(point: corners[index], weight: 1.0), to: &endpoints)
            }
            if secondSign == .zero {
                appendUnique(homogeneous(point: corners[next], weight: 1.0), to: &endpoints)
            }
            if (firstSign == .negative && secondSign == .positive)
                || (firstSign == .positive && secondSign == .negative) {
                let denominator = FloatingPointExpansion.subtract(
                    values[next],
                    values[index]
                )
                var root = HomogeneousExpansion(
                    x: FloatingPointExpansion.subtract(
                        FloatingPointExpansion.product([corners[index].x], values[next]),
                        FloatingPointExpansion.product([corners[next].x], values[index])
                    ),
                    y: FloatingPointExpansion.subtract(
                        FloatingPointExpansion.product([corners[index].y], values[next]),
                        FloatingPointExpansion.product([corners[next].y], values[index])
                    ),
                    z: FloatingPointExpansion.subtract(
                        FloatingPointExpansion.product([corners[index].z], values[next]),
                        FloatingPointExpansion.product([corners[next].z], values[index])
                    ),
                    weight: denominator
                )
                if sign(root.weight) == .negative {
                    root = root.scaled(by: [-1.0])
                }
                guard sign(root.weight) == .positive else {
                    throw certificateFailure(
                        tolerance: tolerance,
                        message: "Exact affine edge interpolation lost its positive denominator."
                    )
                }
                appendUnique(root, to: &endpoints)
            }
        }
        guard endpoints.count <= 2 else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "A transverse plane produced more than two affine section endpoints."
            )
        }
        return endpoints
    }

    private static func appendUnique(
        _ candidate: HomogeneousExpansion,
        to endpoints: inout [HomogeneousExpansion]
    ) {
        guard endpoints.contains(where: { exactlyEqual($0, candidate) }) == false else {
            return
        }
        endpoints.append(candidate)
    }

    private static func exactlyEqual(
        _ first: HomogeneousExpansion,
        _ second: HomogeneousExpansion
    ) -> Bool {
        [
            (first.x, second.x),
            (first.y, second.y),
            (first.z, second.z),
        ].allSatisfy { firstCoordinate, secondCoordinate in
            sign(FloatingPointExpansion.subtract(
                FloatingPointExpansion.product(firstCoordinate, second.weight),
                FloatingPointExpansion.product(secondCoordinate, first.weight)
            )) == .zero
        }
    }

    private static func affineParameterRatios(
        for point: HomogeneousExpansion,
        on patch: AffinePatch,
        tolerance: ModelingTolerance
    ) throws -> (u: ExactRatio, v: ExactRatio) {
        guard sign(point.weight) == .positive else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An exact affine endpoint had a nonpositive homogeneous weight."
            )
        }
        let relative = ExpansionVector3(
            x: FloatingPointExpansion.subtract(
                point.x,
                FloatingPointExpansion.product([patch.origin.x], point.weight)
            ),
            y: FloatingPointExpansion.subtract(
                point.y,
                FloatingPointExpansion.product([patch.origin.y], point.weight)
            ),
            z: FloatingPointExpansion.subtract(
                point.z,
                FloatingPointExpansion.product([patch.origin.z], point.weight)
            )
        )
        let dotU = exactDot(relative, patch.exactU)
        let dotV = exactDot(relative, patch.exactV)
        let uNumerator = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(dotU, patch.gramVV),
            FloatingPointExpansion.product(dotV, patch.gramUV)
        )
        let vNumerator = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(dotV, patch.gramUU),
            FloatingPointExpansion.product(dotU, patch.gramUV)
        )
        let denominator = FloatingPointExpansion.product(
            point.weight,
            patch.gramDeterminant
        )
        guard let u = ExactRatio(numerator: uNumerator, denominator: denominator),
              let v = ExactRatio(numerator: vNumerator, denominator: denominator) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An exact affine endpoint lost its parameter denominator."
            )
        }
        return (u, v)
    }

    private static func nonconstantFirstPatchCoordinate(
        points: [HomogeneousExpansion],
        first: AffinePatch,
        tolerance: ModelingTolerance
    ) throws -> Int {
        let parameters = try points.map {
            try affineParameterRatios(for: $0, on: first, tolerance: tolerance)
        }
        for coordinateIndex in 0...1 {
            let values = parameters.map { coordinateIndex == 0 ? $0.u : $0.v }
            guard let reference = values.first else { continue }
            if values.dropFirst().contains(where: {
                reference.compared(to: $0) != .zero
            }) {
                return coordinateIndex
            }
        }
        return 0
    }

    private static func sectionRange(
        points: [HomogeneousExpansion],
        coordinateIndex: Int,
        first: AffinePatch,
        tolerance: ModelingTolerance
    ) throws -> (lower: SectionEndpoint, upper: SectionEndpoint) {
        let endpoints = try points.map { point in
            let parameters = try affineParameterRatios(
                for: point,
                on: first,
                tolerance: tolerance
            )
            return SectionEndpoint(
                point: point,
                coordinate: coordinateIndex == 0 ? parameters.u : parameters.v
            )
        }
        guard let firstEndpoint = endpoints.first else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An exact affine section unexpectedly had no endpoints."
            )
        }
        guard endpoints.count == 2 else {
            return (firstEndpoint, firstEndpoint)
        }
        switch endpoints[0].coordinate.compared(to: endpoints[1].coordinate) {
        case .negative, .zero:
            return (endpoints[0], endpoints[1])
        case .positive:
            return (endpoints[1], endpoints[0])
        case .indeterminate:
            throw certificateFailure(
                tolerance: tolerance,
                message: "Exact affine section ordering was indeterminate."
            )
        }
    }

    private static func maximumEndpoint(
        _ first: SectionEndpoint,
        _ second: SectionEndpoint,
        tolerance: ModelingTolerance
    ) throws -> SectionEndpoint {
        switch first.coordinate.compared(to: second.coordinate) {
        case .negative:
            return second
        case .zero, .positive:
            return first
        case .indeterminate:
            throw certificateFailure(
                tolerance: tolerance,
                message: "Exact affine lower-bound comparison was indeterminate."
            )
        }
    }

    private static func minimumEndpoint(
        _ first: SectionEndpoint,
        _ second: SectionEndpoint,
        tolerance: ModelingTolerance
    ) throws -> SectionEndpoint {
        switch first.coordinate.compared(to: second.coordinate) {
        case .negative, .zero:
            return first
        case .positive:
            return second
        case .indeterminate:
            throw certificateFailure(
                tolerance: tolerance,
                message: "Exact affine upper-bound comparison was indeterminate."
            )
        }
    }

    private static func normalizedParameterPair(
        for point: HomogeneousExpansion,
        first: AffinePatch,
        second: AffinePatch,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntersectionParameterPair {
        let firstParameters = try affineParameterRatios(
            for: point,
            on: first,
            tolerance: tolerance
        )
        let secondParameters = try affineParameterRatios(
            for: point,
            on: second,
            tolerance: tolerance
        )
        return try SurfaceIntersectionParameterPair(values: try [
            firstParameters.u,
            firstParameters.v,
            secondParameters.u,
            secondParameters.v,
        ].map {
            try normalizedEstimate($0, tolerance: tolerance)
        })
    }

    private static func normalizedEstimate(
        _ ratio: ExactRatio,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard isNonnegative(ratio.numerator),
              isNonnegative(FloatingPointExpansion.subtract(
                  ratio.denominator,
                  ratio.numerator
              )) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An exact affine intersection endpoint left a bounded patch."
            )
        }
        let value = ratio.estimate
        guard value.isFinite,
              value >= -tolerance.relative * 8.0,
              value <= 1.0 + tolerance.relative * 8.0 else {
            throw certificateFailure(
                tolerance: tolerance,
                residual: max(-value, value - 1.0),
                message: "An exact affine endpoint could not be materialized in Double parameters."
            )
        }
        return min(max(value, 0.0), 1.0)
    }

    private static func certifiedBounds(
        lower: [Double],
        upper: [Double],
        surfaces: [BSplineSurface3D],
        freeIndex: Int,
        tolerance: ModelingTolerance
    ) throws -> [(lower: Double, upper: Double)] {
        let domainSpans = try parameterDomainSpans(
            first: surfaces[0],
            second: surfaces[1],
            tolerance: tolerance
        )
        return try lower.indices.map { index in
            var boundLower = min(lower[index], upper[index])
            var boundUpper = max(lower[index], upper[index])
            if index != freeIndex {
                let minimumWidth = max(
                    tolerance.relative * 4.0 / domainSpans[index],
                    Double.ulpOfOne * 1_024.0
                )
                if boundUpper - boundLower <= minimumWidth {
                    if boundLower <= minimumWidth {
                        boundLower = 0.0
                        boundUpper = max(boundUpper, minimumWidth)
                    } else if boundUpper >= 1.0 - minimumWidth {
                        boundLower = min(boundLower, 1.0 - minimumWidth)
                        boundUpper = 1.0
                    } else {
                        let midpoint = (boundLower + boundUpper) * 0.5
                        boundLower = midpoint - minimumWidth * 0.5
                        boundUpper = midpoint + minimumWidth * 0.5
                    }
                }
            }
            guard boundLower >= 0.0,
                  boundUpper <= 1.0,
                  boundUpper > boundLower else {
                throw certificateFailure(
                    tolerance: tolerance,
                    message: "An exact affine graph produced invalid certified bounds."
                )
            }
            return (boundLower, boundUpper)
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
