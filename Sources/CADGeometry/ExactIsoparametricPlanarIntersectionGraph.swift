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

    func parameterDerivativeBounds(
        parameterBox: SurfaceIntersectionParameterBox,
        freeParameter: SurfaceIntersectionParameterCoordinate,
        direction: CertifiedImplicitIntersectionDirection,
        lowerAnchor: SurfaceIntersectionParameterPair,
        midpointAnchor: SurfaceIntersectionParameterPair,
        upperAnchor: SurfaceIntersectionParameterPair,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [ScalarInterval]? {
        guard try certifies(
            parameterBox: parameterBox,
            freeParameter: freeParameter,
            lowerAnchor: lowerAnchor,
            midpointAnchor: midpointAnchor,
            upperAnchor: upperAnchor,
            first: first,
            second: second,
            tolerance: tolerance
        ), let cell = cells.first(where: {
            $0.freeParameter == freeParameter
                && Self.matches(
                    parameterBox,
                    normalizedBounds: $0.normalizedBounds,
                    first: first,
                    second: second,
                    tolerance: tolerance
                )
        }) else {
            return nil
        }

        let sourceCurve = try source.surface.uIsoparametricCurve(
            atV: source.fixedV,
            tolerance: tolerance
        )
        let sourceInterval = try ScalarInterval(
            lower: cell.sourceULower,
            upper: cell.sourceUUpper
        )
        let patches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: sourceCurve,
            intersecting: sourceInterval,
            tolerance: tolerance
        )
        guard patches.count == 1,
              let sourcePatch = patches.first,
              sourcePatch.lower == cell.sourceULower,
              sourcePatch.upper == cell.sourceUUpper else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar graph lost its source Bezier span."
            )
        }
        let sourceJet = try RationalBezierCurveJetEncloser().enclosure(
            of: sourcePatch,
            tolerance: tolerance
        )
        let sourceScale = OutwardScalarInterval(
            parameterBox.interval(for: freeParameter).width
        )
        let tangent = IntervalVector3DBounds(
            x: sourceJet.x.derivativeU * sourceScale,
            y: sourceJet.y.derivativeU * sourceScale,
            z: sourceJet.z.derivativeU * sourceScale
        )
        let affineDerivative = try affineCoordinateDerivativeBounds(
            tangent: tangent,
            tolerance: tolerance
        )
        let planarJacobian = try planarMapJacobianBounds(tolerance: tolerance)
        guard let planeUNormalized = (
            affineDerivative.u * planarJacobian.dv.y
                - affineDerivative.v * planarJacobian.dv.x
        ).divided(by: planarJacobian.determinant),
              let planeVNormalized = (
                  affineDerivative.v * planarJacobian.du.x
                      - affineDerivative.u * planarJacobian.du.y
              ).divided(by: planarJacobian.determinant) else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar graph lost its certified planar inverse derivative."
            )
        }

        let sourceU = sourceScale
        let zero = OutwardScalarInterval(lower: 0.0, upper: 0.0)
        let planeUCoordinate: SurfaceIntersectionParameterCoordinate = sourceIsFirst
            ? .secondU
            : .firstU
        let planeVCoordinate: SurfaceIntersectionParameterCoordinate = sourceIsFirst
            ? .secondV
            : .firstV
        let planeU = planeUNormalized * OutwardScalarInterval(
            parameterBox.interval(for: planeUCoordinate).width
        )
        let planeV = planeVNormalized * OutwardScalarInterval(
            parameterBox.interval(for: planeVCoordinate).width
        )
        let forward = sourceIsFirst
            ? [sourceU, zero, planeU, planeV]
            : [planeU, planeV, sourceU, zero]
        let directed = direction == .forward
            ? forward
            : forward.map { Self.negated($0) }
        guard directed.allSatisfy(\.isFinite) else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar graph derivative exceeded finite interval arithmetic."
            )
        }
        return try directed.map {
            try ScalarInterval(lower: $0.lower, upper: $0.upper)
        }
    }

    func restrictedBounds(
        parameterBox: SurfaceIntersectionParameterBox,
        freeParameter: SurfaceIntersectionParameterCoordinate,
        direction: CertifiedImplicitIntersectionDirection,
        lowerAnchor: SurfaceIntersectionParameterPair,
        midpointAnchor: SurfaceIntersectionParameterPair,
        upperAnchor: SurfaceIntersectionParameterPair,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionGraphSubcell? {
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= 0.0,
              upperFraction <= 1.0,
              upperFraction - lowerFraction > tolerance.relative,
              try certifies(
                  parameterBox: parameterBox,
                  freeParameter: freeParameter,
                  lowerAnchor: lowerAnchor,
                  midpointAnchor: midpointAnchor,
                  upperAnchor: upperAnchor,
                  first: first,
                  second: second,
                  tolerance: tolerance
              ), let cell = cells.first(where: {
                  $0.freeParameter == freeParameter
                      && Self.matches(
                          parameterBox,
                          normalizedBounds: $0.normalizedBounds,
                          first: first,
                          second: second,
                          tolerance: tolerance
                      )
              }) else {
            return nil
        }

        let directedLower = direction == .forward
            ? lowerFraction
            : 1.0 - upperFraction
        let directedUpper = direction == .forward
            ? upperFraction
            : 1.0 - lowerFraction
        let sourceLower = cell.sourceULower
            + (cell.sourceUUpper - cell.sourceULower) * directedLower
        let sourceUpper = cell.sourceULower
            + (cell.sourceUUpper - cell.sourceULower) * directedUpper
        let sourceCurve = try source.surface.uIsoparametricCurve(
            atV: source.fixedV,
            tolerance: tolerance
        )
        let sourceInterval = try ScalarInterval(
            lower: sourceLower,
            upper: sourceUpper
        )
        let patches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: sourceCurve,
            intersecting: sourceInterval,
            tolerance: tolerance
        )
        guard patches.count == 1, let sourcePatch = patches.first else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar subcell crossed a source Bezier span."
            )
        }
        let sourceJet = try RationalBezierCurveJetEncloser().enclosure(
            of: sourcePatch,
            over: sourceInterval,
            tolerance: tolerance
        )
        let affine = try affineCoordinateBounds(
            position: IntervalVector3DBounds(
                x: sourceJet.x.value,
                y: sourceJet.y.value,
                z: sourceJet.z.value
            ),
            tolerance: tolerance
        )
        let normalizedPlane = try inversePlanarMapBounds(
            affineU: affine.u,
            affineV: affine.v,
            tolerance: tolerance
        )
        let normalizedPlaneU = normalizedPlane.u
        let normalizedPlaneV = normalizedPlane.v
        let sourceU = try containingInterval(
            sourceLower,
            sourceUpper,
            in: source.surface.uDomain,
            tolerance: tolerance
        )
        let sourceV = try containingInterval(
            source.fixedV,
            source.fixedV,
            in: source.surface.vDomain,
            tolerance: tolerance
        )
        let planeSurface = sourceIsFirst ? second : first
        let planeU = try actualInterval(
            normalizedPlaneU,
            in: planeSurface.uDomain,
            tolerance: tolerance
        )
        let planeV = try actualInterval(
            normalizedPlaneV,
            in: planeSurface.vDomain,
            tolerance: tolerance
        )
        let intervals = sourceIsFirst
            ? [sourceU, sourceV, planeU, planeV]
            : [planeU, planeV, sourceU, sourceV]

        let sourceSpan = sourceUpper - sourceLower
        let traversalSign = direction == .forward ? 1.0 : -1.0
        let tangentScale = OutwardScalarInterval(sourceSpan * traversalSign)
        let tangent = IntervalVector3DBounds(
            x: sourceJet.x.derivativeU * tangentScale,
            y: sourceJet.y.derivativeU * tangentScale,
            z: sourceJet.z.derivativeU * tangentScale
        )
        let affineDerivative = try affineCoordinateDerivativeBounds(
            tangent: tangent,
            tolerance: tolerance
        )
        let planarJacobian = try planarMapJacobianBounds(
            u: normalizedPlaneU,
            v: normalizedPlaneV,
            tolerance: tolerance
        )
        guard let planeUNormalized = (
            affineDerivative.u * planarJacobian.dv.y
                - affineDerivative.v * planarJacobian.dv.x
        ).divided(by: planarJacobian.determinant),
              let planeVNormalized = (
                  affineDerivative.v * planarJacobian.du.x
                      - affineDerivative.u * planarJacobian.du.y
              ).divided(by: planarJacobian.determinant) else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar subcell lost its local inverse derivative."
            )
        }
        let zero = OutwardScalarInterval(0.0)
        let planeUDomainWidth = Self.domainWidth(planeSurface.uDomain)
        let planeVDomainWidth = Self.domainWidth(planeSurface.vDomain)
        let sourceDerivatives = [
            OutwardScalarInterval(sourceSpan * traversalSign),
            zero,
        ]
        let planeDerivatives = [
            planeUNormalized * OutwardScalarInterval(planeUDomainWidth),
            planeVNormalized * OutwardScalarInterval(planeVDomainWidth),
        ]
        let derivativeIntervals = sourceIsFirst
            ? sourceDerivatives + planeDerivatives
            : planeDerivatives + sourceDerivatives
        guard derivativeIntervals.allSatisfy(\.isFinite) else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar subcell derivative exceeded finite arithmetic."
            )
        }
        return CertifiedImplicitIntersectionGraphSubcell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: intervals[0],
                firstV: intervals[1],
                secondU: intervals[2],
                secondV: intervals[3]
            ),
            parameterDerivativeBounds: try derivativeIntervals.map {
                try ScalarInterval(lower: $0.lower, upper: $0.upper)
            }
        )
    }

    func planarAffineFluxTraversal(
        curve: CertifiedImplicitSurfaceParameterCurve,
        surface: BSplineSurface3D,
        reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedPlanarAffineFluxTraversal? {
        let planeSurface = sourceIsFirst
            ? curve.intersection.secondSurface
            : curve.intersection.firstSurface
        let planeRole: SurfaceIntersectionSurfaceRole = sourceIsFirst
            ? .second
            : .first
        guard curve.role == planeRole, surface == planeSurface else { return nil }

        let sourceCurve = try source.surface.uIsoparametricCurve(
            atV: source.fixedV,
            tolerance: tolerance
        )
        let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: sourceCurve,
            tolerance: tolerance
        )
        guard sourcePatches.count == cells.count,
              zip(sourcePatches, cells).allSatisfy({ patch, cell in
                  patch.lower == cell.sourceULower
                      && patch.upper == cell.sourceUUpper
              }) else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact planar flux traversal lost its source Bezier spans."
            )
        }

        let traversalSegments = try curve.canonicalTraversalSegments(
            tolerance: tolerance
        )
        let cellCount = Double(cells.count)
        var resultPatches: [CertifiedPlanarAffineFluxTraversal.Patch] = []
        for traversal in traversalSegments {
            for index in cells.indices {
                let cellLower = Double(index) / cellCount
                let cellUpper = Double(index + 1) / cellCount
                let overlapLower = max(
                    traversal.canonicalLowerFraction,
                    cellLower
                )
                let overlapUpper = min(
                    traversal.canonicalUpperFraction,
                    cellUpper
                )
                guard overlapUpper > overlapLower else { continue }
                let localLower = min(
                    max((overlapLower - cellLower) * cellCount, 0.0),
                    1.0
                )
                let localUpper = min(
                    max((overlapUpper - cellLower) * cellCount, 0.0),
                    1.0
                )
                let patch = sourcePatches[index]
                let controls = try patch.controlPoints.indices.map { controlIndex in
                    let affine = try affineCoordinates(
                        of: patch.controlPoints[controlIndex],
                        tolerance: tolerance
                    )
                    let weight = OutwardScalarInterval(patch.weights[controlIndex])
                    return AffineHomogeneousControl(
                        x: affine.u * weight,
                        y: affine.v * weight,
                        weight: weight
                    )
                }
                var restricted = try restrictedControls(
                    controls,
                    lower: localLower,
                    upper: localUpper,
                    tolerance: tolerance
                )
                if traversal.direction == .reversed {
                    restricted.reverse()
                }
                resultPatches.append(CertifiedPlanarAffineFluxTraversal.Patch(
                    controls: try restricted.map {
                        CertifiedPlanarAffineFluxTraversal.HomogeneousControl(
                            x: try ScalarInterval(
                                lower: $0.x.lower,
                                upper: $0.x.upper
                            ),
                            y: try ScalarInterval(
                                lower: $0.y.lower,
                                upper: $0.y.upper
                            ),
                            weight: try ScalarInterval(
                                lower: $0.weight.lower,
                                upper: $0.weight.upper
                            )
                        )
                    }
                ))
            }
        }
        guard resultPatches.isEmpty == false else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact planar flux traversal produced no active curve patches."
            )
        }
        let relative = Self.exactDifference(plane.origin, reference)
        let scaleNumerator = Self.interval(Self.exactTriple(
            plane.exactU,
            plane.exactV,
            relative
        ))
        guard let scale = scaleNumerator.divided(
            by: OutwardScalarInterval(3.0)
        ), scale.isFinite else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact planar flux traversal lost its finite flux scale."
            )
        }
        return CertifiedPlanarAffineFluxTraversal(
            patches: resultPatches,
            fluxScale: try ScalarInterval(lower: scale.lower, upper: scale.upper)
        )
    }

    private struct AffineHomogeneousControl {
        let x: OutwardScalarInterval
        let y: OutwardScalarInterval
        let weight: OutwardScalarInterval

        func interpolated(
            to other: AffineHomogeneousControl,
            parameter: OutwardScalarInterval
        ) -> AffineHomogeneousControl {
            let complement = OutwardScalarInterval(1.0) - parameter
            return AffineHomogeneousControl(
                x: x * complement + other.x * parameter,
                y: y * complement + other.y * parameter,
                weight: weight * complement + other.weight * parameter
            )
        }
    }

    private func affineCoordinates(
        of point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> (u: OutwardScalarInterval, v: OutwardScalarInterval) {
        let relative = Self.exactDifference(point, plane.origin)
        let dotU = Self.exactDot(relative, plane.exactU)
        let dotV = Self.exactDot(relative, plane.exactV)
        let uNumerator = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(dotU, plane.gramVV),
            FloatingPointExpansion.product(dotV, plane.gramUV)
        )
        let vNumerator = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(dotV, plane.gramUU),
            FloatingPointExpansion.product(dotU, plane.gramUV)
        )
        let determinant = Self.interval(plane.gramDeterminant)
        guard let u = Self.interval(uNumerator).divided(by: determinant),
              let v = Self.interval(vNumerator).divided(by: determinant),
              u.isFinite,
              v.isFinite else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact planar flux traversal lost its affine control coordinates."
            )
        }
        return (u, v)
    }

    private func restrictedControls(
        _ controls: [AffineHomogeneousControl],
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> [AffineHomogeneousControl] {
        guard controls.count >= 2,
              lower >= 0.0,
              upper <= 1.0,
              upper > lower else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact planar flux traversal received an invalid Bezier restriction."
            )
        }
        let upperControls = upper == 1.0
            ? controls
            : splitControls(
                controls,
                parameter: OutwardScalarInterval(lower: upper, upper: upper)
            ).lower
        guard lower > 0.0 else { return upperControls }
        guard let normalizedLower = OutwardScalarInterval(
            lower: lower,
            upper: lower
        ).divided(by: OutwardScalarInterval(lower: upper, upper: upper)) else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact planar flux traversal could not normalize its Bezier restriction."
            )
        }
        return splitControls(
            upperControls,
            parameter: normalizedLower
        ).upper
    }

    private func splitControls(
        _ controls: [AffineHomogeneousControl],
        parameter: OutwardScalarInterval
    ) -> (
        lower: [AffineHomogeneousControl],
        upper: [AffineHomogeneousControl]
    ) {
        var levels = [controls]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].interpolated(
                    to: previous[index + 1],
                    parameter: parameter
                )
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
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

    private func affineCoordinateDerivativeBounds(
        tangent: IntervalVector3DBounds,
        tolerance: ModelingTolerance
    ) throws -> (u: OutwardScalarInterval, v: OutwardScalarInterval) {
        let exactU = Self.intervalVector(plane.exactU)
        let exactV = Self.intervalVector(plane.exactV)
        let dotU = tangent.x * exactU.x
            + tangent.y * exactU.y
            + tangent.z * exactU.z
        let dotV = tangent.x * exactV.x
            + tangent.y * exactV.y
            + tangent.z * exactV.z
        let gramUU = Self.interval(plane.gramUU)
        let gramUV = Self.interval(plane.gramUV)
        let gramVV = Self.interval(plane.gramVV)
        let determinant = Self.interval(plane.gramDeterminant)
        guard determinant.lower > 0.0,
              let u = (dotU * gramVV - dotV * gramUV).divided(by: determinant),
              let v = (dotV * gramUU - dotU * gramUV).divided(by: determinant) else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar graph lost its certified affine derivative inverse."
            )
        }
        return (u, v)
    }

    private func affineCoordinateBounds(
        position: IntervalVector3DBounds,
        tolerance: ModelingTolerance
    ) throws -> (u: OutwardScalarInterval, v: OutwardScalarInterval) {
        let relative = IntervalVector3DBounds(
            x: position.x - OutwardScalarInterval(plane.origin.x),
            y: position.y - OutwardScalarInterval(plane.origin.y),
            z: position.z - OutwardScalarInterval(plane.origin.z)
        )
        return try affineCoordinateDerivativeBounds(
            tangent: relative,
            tolerance: tolerance
        )
    }

    private func inversePlanarMapBounds(
        affineU: OutwardScalarInterval,
        affineV: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (u: OutwardScalarInterval, v: OutwardScalarInterval) {
        let targetU = OutwardScalarInterval(
            lower: max(0.0, affineU.lower),
            upper: min(1.0, affineU.upper)
        )
        let targetV = OutwardScalarInterval(
            lower: max(0.0, affineV.lower),
            upper: min(1.0, affineV.upper)
        )
        guard targetU.lower <= targetU.upper,
              targetV.lower <= targetV.upper else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar subcell left the affine plane domain."
            )
        }
        let targetMidpointU = targetU.lower
            + (targetU.upper - targetU.lower) * 0.5
        let targetMidpointV = targetV.lower
            + (targetV.upper - targetV.lower) * 0.5
        let center = try inversePlanarMap(
            affineU: targetMidpointU,
            affineV: targetMidpointV,
            tolerance: tolerance
        )
        let centerMap = Self.planarMap(
            u: center.u,
            v: center.v,
            weights: plane.weights
        )
        let centerDeterminant = centerMap.du.x * centerMap.dv.y
            - centerMap.dv.x * centerMap.du.y
        guard centerDeterminant.isFinite,
              centerDeterminant > Double.leastNonzeroMagnitude else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact planar inverse enclosure encountered a singular midpoint Jacobian."
            )
        }
        let inverse00 = centerMap.dv.y / centerDeterminant
        let inverse01 = -centerMap.dv.x / centerDeterminant
        let inverse10 = -centerMap.du.y / centerDeterminant
        let inverse11 = centerMap.du.x / centerDeterminant
        // The positive-weight bilinear patch is a bijection from the parameter
        // square onto the affine square. Along the inverse image of the line
        // from the computed center to any target point, the inverse derivative
        // is J^-1. A global interval bound for J^-1 therefore gives a certified
        // Lipschitz box without a resolution-dependent two-dimensional search.
        let weights = plane.weights.flatMap { $0 }
        let weightHull = OutwardScalarInterval.enclosing(weights)
        let a = OutwardScalarInterval(plane.weights[0][0])
        let b = OutwardScalarInterval(plane.weights[0][1])
        let c = OutwardScalarInterval(plane.weights[1][0])
        let d = OutwardScalarInterval(plane.weights[1][1])
        let determinantNumerator = OutwardScalarInterval.enclosing([
            a * b * c,
            a * b * d,
            a * c * d,
            b * c * d,
        ])
        let maximumWeightProduct = weightHull * weightHull * weightHull
        let crossWeight = a * d - b * c
        guard determinantNumerator.lower > 0.0,
              let diagonalMagnitude = maximumWeightProduct.divided(
                  by: OutwardScalarInterval(
                      lower: determinantNumerator.lower,
                      upper: determinantNumerator.lower.nextUp
                  )
              ), let crossMagnitude = (
                  OutwardScalarInterval(
                      max(abs(crossWeight.lower), abs(crossWeight.upper))
                  ) * weightHull * OutwardScalarInterval(0.25)
              ).divided(
                  by: OutwardScalarInterval(
                      lower: determinantNumerator.lower,
                      upper: determinantNumerator.lower.nextUp
                  )
              ) else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact planar inverse lost its global inverse-Jacobian bound."
            )
        }
        let targetRadiusU = max(
            abs(targetU.lower - centerMap.u),
            abs(targetU.upper - centerMap.u)
        ).nextUp
        let targetRadiusV = max(
            abs(targetV.lower - centerMap.v),
            abs(targetV.upper - centerMap.v)
        ).nextUp
        let diagonalBound = max(
            abs(diagonalMagnitude.lower),
            abs(diagonalMagnitude.upper)
        ).nextUp
        let crossBound = max(
            abs(crossMagnitude.lower),
            abs(crossMagnitude.upper)
        ).nextUp
        let uRadius = (
            diagonalBound * targetRadiusU
                + crossBound * targetRadiusV
        ).nextUp
        let vRadius = (
            crossBound * targetRadiusU
                + diagonalBound * targetRadiusV
        ).nextUp
        var u = OutwardScalarInterval(
            lower: max(0.0, (center.u - uRadius).nextDown),
            upper: min(1.0, (center.u + uRadius).nextUp)
        )
        var v = OutwardScalarInterval(
            lower: max(0.0, (center.v - vRadius).nextDown),
            upper: min(1.0, (center.v + vRadius).nextUp)
        )
        let one = OutwardScalarInterval(lower: 1.0, upper: 1.0)
        for _ in 0..<16 {
            let jacobian = try planarMapJacobianBounds(
                u: u,
                v: v,
                tolerance: tolerance
            )
            let residualU = OutwardScalarInterval(centerMap.u) - targetU
            let residualV = OutwardScalarInterval(centerMap.v) - targetV
            let baseU = OutwardScalarInterval(center.u)
                - OutwardScalarInterval(inverse00) * residualU
                - OutwardScalarInterval(inverse01) * residualV
            let baseV = OutwardScalarInterval(center.v)
                - OutwardScalarInterval(inverse10) * residualU
                - OutwardScalarInterval(inverse11) * residualV
            let remainder00 = one
                - OutwardScalarInterval(inverse00) * jacobian.du.x
                - OutwardScalarInterval(inverse01) * jacobian.du.y
            let remainder01 = -OutwardScalarInterval(inverse00) * jacobian.dv.x
                - OutwardScalarInterval(inverse01) * jacobian.dv.y
            let remainder10 = -OutwardScalarInterval(inverse10) * jacobian.du.x
                - OutwardScalarInterval(inverse11) * jacobian.du.y
            let remainder11 = one
                - OutwardScalarInterval(inverse10) * jacobian.dv.x
                - OutwardScalarInterval(inverse11) * jacobian.dv.y
            let deltaU = u - OutwardScalarInterval(center.u)
            let deltaV = v - OutwardScalarInterval(center.v)
            let candidateU = baseU + remainder00 * deltaU + remainder01 * deltaV
            let candidateV = baseV + remainder10 * deltaU + remainder11 * deltaV
            let nextU = OutwardScalarInterval(
                lower: max(u.lower, candidateU.lower, 0.0),
                upper: min(u.upper, candidateU.upper, 1.0)
            )
            let nextV = OutwardScalarInterval(
                lower: max(v.lower, candidateV.lower, 0.0),
                upper: min(v.upper, candidateV.upper, 1.0)
            )
            guard nextU.lower <= nextU.upper,
                  nextV.lower <= nextV.upper else {
                throw Self.certificateFailure(
                    tolerance: tolerance,
                    message: "An exact planar inverse interval excluded its certified source curve."
                )
            }
            let improvement = max(
                (u.upper - u.lower) - (nextU.upper - nextU.lower),
                (v.upper - v.lower) - (nextV.upper - nextV.lower)
            )
            u = nextU
            v = nextV
            if improvement <= tolerance.relative { break }
        }
        return (u, v)
    }

    private func actualInterval(
        _ normalized: OutwardScalarInterval,
        in domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard case let .closed(lower, upper) = domain else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact planar subcell requires a closed parameter domain."
            )
        }
        return try containingInterval(
            lower + (upper - lower) * normalized.lower,
            lower + (upper - lower) * normalized.upper,
            in: domain,
            tolerance: tolerance
        )
    }

    private func containingInterval(
        _ requestedLower: Double,
        _ requestedUpper: Double,
        in domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard case let .closed(domainLower, domainUpper) = domain else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar subcell requires a closed parameter domain."
            )
        }
        let scale = max(1.0, abs(domainLower), abs(domainUpper))
        let minimumWidth = min(
            domainUpper - domainLower,
            max(
                tolerance.relative * scale * 4.0,
                Double.ulpOfOne * scale * 4_096.0
            )
        )
        var lower = max(domainLower, min(requestedLower, requestedUpper).nextDown)
        var upper = min(domainUpper, max(requestedLower, requestedUpper).nextUp)
        if upper - lower < minimumWidth {
            let midpoint = lower + (upper - lower) * 0.5
            lower = max(domainLower, midpoint - minimumWidth * 0.5)
            upper = min(domainUpper, lower + minimumWidth)
            lower = max(domainLower, upper - minimumWidth)
        }
        guard upper > lower else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact isoparametric-planar subcell could not construct a positive parameter interval."
            )
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func planarMapJacobianBounds(
        tolerance: ModelingTolerance
    ) throws -> (
        du: (x: OutwardScalarInterval, y: OutwardScalarInterval),
        dv: (x: OutwardScalarInterval, y: OutwardScalarInterval),
        determinant: OutwardScalarInterval
    ) {
        try planarMapJacobianBounds(
            u: OutwardScalarInterval(lower: 0.0, upper: 1.0),
            v: OutwardScalarInterval(lower: 0.0, upper: 1.0),
            tolerance: tolerance
        )
    }

    private func planarMapJacobianBounds(
        u: OutwardScalarInterval,
        v: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (
        du: (x: OutwardScalarInterval, y: OutwardScalarInterval),
        dv: (x: OutwardScalarInterval, y: OutwardScalarInterval),
        determinant: OutwardScalarInterval
    ) {
        let one = OutwardScalarInterval(lower: 1.0, upper: 1.0)
        let a = OutwardScalarInterval(plane.weights[0][0])
        let b = OutwardScalarInterval(plane.weights[0][1])
        let c = OutwardScalarInterval(plane.weights[1][0])
        let d = OutwardScalarInterval(plane.weights[1][1])
        let lowerUWeight = a * (one - v) + c * v
        let upperUWeight = b * (one - v) + d * v
        let lowerVWeight = a * (one - u) + b * u
        let upperVWeight = c * (one - u) + d * u
        let evaluatedDenominator = (one - u) * lowerUWeight + u * upperUWeight
        let weightHull = OutwardScalarInterval.enclosing(
            plane.weights.flatMap { $0 }
        )
        let denominator = OutwardScalarInterval(
            lower: max(evaluatedDenominator.lower, weightHull.lower),
            upper: min(evaluatedDenominator.upper, weightHull.upper)
        )
        let numeratorU = u * upperUWeight
        let numeratorV = v * upperVWeight
        let denominatorU = upperUWeight - lowerUWeight
        let denominatorV = upperVWeight - lowerVWeight
        let numeratorUU = upperUWeight
        let numeratorUV = u * (d - b)
        let numeratorVU = v * (d - c)
        let numeratorVV = upperVWeight
        let denominatorSquared = denominator * denominator
        guard denominator.lower > 0.0,
              let duX = (
                  numeratorUU * denominator - numeratorU * denominatorU
              ).divided(by: denominatorSquared),
              let duY = (
                  numeratorVU * denominator - numeratorV * denominatorU
              ).divided(by: denominatorSquared),
              let dvX = (
                  numeratorUV * denominator - numeratorU * denominatorV
              ).divided(by: denominatorSquared),
              let dvY = (
                  numeratorVV * denominator - numeratorV * denominatorV
              ).divided(by: denominatorSquared) else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact rational planar map lost its positive weight enclosure."
            )
        }

        let jacobianNumerator = OutwardScalarInterval.enclosing([
            a * b * c,
            a * b * d,
            a * c * d,
            b * c * d,
        ])
        let denominatorCubed = denominatorSquared * denominator
        guard jacobianNumerator.lower > 0.0,
              let determinant = jacobianNumerator.divided(by: denominatorCubed),
              determinant.lower > 0.0 else {
            throw Self.certificateFailure(
                tolerance: tolerance,
                message: "An exact rational planar map lost its positive Jacobian enclosure."
            )
        }
        return (
            du: (x: duX, y: duY),
            dv: (x: dvX, y: dvY),
            determinant: determinant
        )
    }

    private static func intervalVector(
        _ value: ExpansionVector3
    ) -> (
        x: OutwardScalarInterval,
        y: OutwardScalarInterval,
        z: OutwardScalarInterval
    ) {
        (
            x: interval(value.x),
            y: interval(value.y),
            z: interval(value.z)
        )
    }

    private static func interval(_ expansion: [Double]) -> OutwardScalarInterval {
        expansion.reduce(
            OutwardScalarInterval(lower: 0.0, upper: 0.0)
        ) { result, component in
            result + OutwardScalarInterval(component)
        }
    }

    private static func domainWidth(_ domain: ParameterDomain) -> Double {
        guard case let .closed(lower, upper) = domain else { return .nan }
        return upper - lower
    }

    private static func negated(
        _ interval: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: (-interval.upper).nextDown,
            upper: (-interval.lower).nextUp
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
