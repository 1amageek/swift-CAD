import CADCore
import CADGeometry
import CADIR

package struct ExactLoftGuideCurve: Sendable {
    package let curve: BSplineCurve3D
    package let boundaryLoopIndex: Int
    package let sectionPoints: [Point3D]
    package let sectionParameters: [Double]
}

package struct ExactLoftGuideCurveResolver {
    package init() {}

    package func resolve(
        guides: [LoftGuideReference],
        profiles: [Profile],
        context: EvaluationContext
    ) throws -> [ExactLoftGuideCurve] {
        guard guides.isEmpty == false else { return [] }
        let builder = ExactBSplineCurveSpanBuilder(tolerance: context.tolerance)
        return try resolve(guides: guides, sections: profiles.map {
            ExactLoftGuideSection(loops: try builder.profileLoopSpans(from: $0), plane: $0.plane)
        }, context: context)
    }

    package func resolve(
        guides: [LoftGuideReference],
        sections: [ExactLoftGuideSection],
        context: EvaluationContext
    ) throws -> [ExactLoftGuideCurve] {
        guard guides.isEmpty == false else { return [] }
        guard sections.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph(
                "Exact Loft guides require at least two sections."
            )
        }
        guard let boundaryLoopCount = sections.first?.loops.count,
              boundaryLoopCount > 0,
              sections.allSatisfy({
                  $0.loops.count == boundaryLoopCount && $0.loops.allSatisfy { !$0.isEmpty }
              }) else {
            throw KernelError(
                phase: .topology,
                code: .nonManifoldResult,
                tolerance: context.tolerance,
                message: "Every guided Loft section must preserve the same number of boundary loops."
            )
        }
        let chainBuilder = EvaluatedCurveChainBuilder(
            tolerance: context.tolerance
        )
        let spanBuilder = ExactBSplineCurveSpanBuilder(
            tolerance: context.tolerance
        )
        let compositeBuilder = ExactCompositeBSplineCurveBuilder()
        return try guides.map { guide in
            guard let sourceCurves = context.curves[guide.featureID] else {
                throw FeatureEvaluationError.missingInput(
                    "Missing Loft guide curve source \(guide.featureID)."
                )
            }
            let segments = try chainBuilder.openSegments(
                from: sourceCurves,
                operationName: "Loft guide"
            )
            let spans = try spanBuilder.pathSpans(from: segments)
            let source = try compositeBuilder.build(
                spans: spans.map(\.curve),
                tolerance: context.tolerance
            )
            let oriented = try oriented(
                source,
                guideFeatureID: guide.featureID,
                firstSection: sections[0],
                lastSection: sections[sections.index(before: sections.endIndex)],
                tolerance: context.tolerance
            )
            let contacts = try sectionContacts(
                curve: oriented.curve,
                boundaryLoopIndex: oriented.boundaryLoopIndex,
                guideFeatureID: guide.featureID,
                sections: sections,
                tolerance: context.tolerance
            )
            return ExactLoftGuideCurve(
                curve: oriented.curve,
                boundaryLoopIndex: oriented.boundaryLoopIndex,
                sectionPoints: contacts.map(\.point),
                sectionParameters: contacts.map(\.parameter)
            )
        }
    }

    private func oriented(
        _ curve: BSplineCurve3D,
        guideFeatureID: FeatureID,
        firstSection: ExactLoftGuideSection,
        lastSection: ExactLoftGuideSection,
        tolerance: ModelingTolerance
    ) throws -> (curve: BSplineCurve3D, boundaryLoopIndex: Int) {
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                featureID: guideFeatureID,
                tolerance: tolerance,
                message: "Exact Loft guide composition requires a bounded curve."
            )
        }
        let start = try curve.point(at: lower, tolerance: tolerance)
        let end = try curve.point(at: upper, tolerance: tolerance)
        let forwardStartLoop = try boundaryLoopIndex(
            containing: start,
            section: firstSection,
            tolerance: tolerance
        )
        let forwardEndLoop = try boundaryLoopIndex(
            containing: end,
            section: lastSection,
            tolerance: tolerance
        )
        let reverseStartLoop = try boundaryLoopIndex(
            containing: end,
            section: firstSection,
            tolerance: tolerance
        )
        let reverseEndLoop = try boundaryLoopIndex(
            containing: start,
            section: lastSection,
            tolerance: tolerance
        )
        let forwardMatches = forwardStartLoop != nil && forwardStartLoop == forwardEndLoop
        let reverseMatches = reverseStartLoop != nil && reverseStartLoop == reverseEndLoop
        guard !(forwardMatches && reverseMatches) else {
            throw KernelError(phase: .geometry, code: .ambiguousSelection,
                featureID: guideFeatureID, tolerance: tolerance,
                message: "Loft guide endpoints admit both traversal directions.")
        }
        if forwardMatches, let forwardStartLoop {
            return (curve, forwardStartLoop)
        }
        if let reverseStartLoop,
           reverseStartLoop == reverseEndLoop {
            return (
                try curve.reversed(tolerance: tolerance),
                reverseStartLoop
            )
        }
        throw KernelError(
            phase: .geometry,
            code: .invalidInput,
            featureID: guideFeatureID,
            tolerance: tolerance,
            message: "Exact Loft guide endpoints must lie on the exact first and last profile boundaries."
        )
    }

    private func sectionContacts(
        curve: BSplineCurve3D,
        boundaryLoopIndex: Int,
        guideFeatureID: FeatureID,
        sections: [ExactLoftGuideSection],
        tolerance: ModelingTolerance
    ) throws -> [(point: Point3D, parameter: Double)] {
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                featureID: guideFeatureID,
                tolerance: tolerance,
                message: "Exact Loft guide requires a bounded parameter domain."
            )
        }
        var contacts: [(point: Point3D, parameter: Double)] = []
        let resolution = max(
            tolerance.relative * max(abs(lower), abs(upper), 1.0),
            Double.ulpOfOne * max(abs(lower), abs(upper), 1.0) * 512.0
        )
        contacts.reserveCapacity(sections.count)
        contacts.append((
            try curve.point(at: lower, tolerance: tolerance),
            lower
        ))
        for section in sections.dropFirst().dropLast() {
            let intersections: [(point: Point3D, curveParameter: Double)]
            if let support = section.plane {
                intersections = try DefaultCurveSurfaceIntersector().intersections(
                    curve: .bSpline(curve),
                    surface: .plane(try plane(for: support, tolerance: tolerance)),
                    options: CurveSurfaceIntersectionOptions(
                        curveRange: try ScalarInterval(lower: lower, upper: upper)
                    ),
                    tolerance: tolerance
                ).map { ($0.point, $0.curveParameter) }
            } else {
                intersections = try section.loops[boundaryLoopIndex].flatMap {
                    try spatialContacts(guide: curve, boundary: $0.curve, tolerance: tolerance)
                }
            }
            var candidates: [(point: Point3D, parameter: Double)] = []
            for intersection in intersections {
                guard try boundaryContains(
                    intersection.point,
                    spans: section.loops[boundaryLoopIndex],
                    tolerance: tolerance
                ) else {
                    continue
                }
                if candidates.contains(where: { candidate in
                    abs(candidate.parameter - intersection.curveParameter) <= resolution
                    && candidate.point.isApproximatelyEqual(
                        to: intersection.point,
                        tolerance: tolerance.distance
                    )
                }) == false {
                    candidates.append((
                        intersection.point,
                        intersection.curveParameter
                    ))
                }
            }
            guard candidates.count == 1, let contact = candidates.first else {
                throw KernelError(
                    phase: .geometry,
                    code: candidates.isEmpty ? .intersectionFailure : .ambiguousSelection,
                    featureID: guideFeatureID,
                    tolerance: tolerance,
                    message: candidates.isEmpty
                        ? "A Loft guide must intersect every intermediate profile boundary."
                        : "A Loft guide must intersect each intermediate profile boundary exactly once."
                )
            }
            contacts.append(contact)
        }
        contacts.append((
            try curve.point(at: upper, tolerance: tolerance),
            upper
        ))
        guard zip(contacts, contacts.dropFirst()).allSatisfy({ pair in
            pair.1.parameter > pair.0.parameter + resolution
        }) else {
            throw KernelError(
                phase: .geometry,
                code: .nonManifoldResult,
                featureID: guideFeatureID,
                tolerance: tolerance,
                message: "Loft sections must meet each guide in strictly increasing guide order."
            )
        }
        return contacts
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Loft's spatial guide path resolves discrete
    // projected roots, but general coincident/tangent spatial loci can exhaust the
    // certified solver. Complete their classification before claiming all guide inputs.
    private func spatialContacts(
        guide: BSplineCurve3D, boundary: BSplineCurve3D, tolerance: ModelingTolerance
    ) throws -> [(point: Point3D, curveParameter: Double)] {
        guard case .closed(let a, let b) = guide.domain,
              case .closed(let c, let d) = boundary.domain else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance,
                message: "Spatial Loft contacts require bounded exact curves.")
        }
        // Coordinate selection only steers convergence. All roots and spatial
        // distances still require interval certification; no sampled contact is admitted.
        let normal = try guide.differentialGeometry(at: a + (b - a) * 0.5, tolerance: tolerance)
            .firstDerivative.cross(boundary.differentialGeometry(at: c + (d - c) * 0.5,
                tolerance: tolerance).firstDerivative)
        let axis = abs(normal.x) >= max(abs(normal.y), abs(normal.z)) ? 0
            : abs(normal.y) >= abs(normal.z) ? 1 : 2
        func projected(_ curve: BSplineCurve3D) -> BSplineCurve2D {
            BSplineCurve2D(degree: curve.degree, knots: curve.knots,
                controlPoints: curve.controlPoints.map {
                    switch axis {
                    case 0: Point2D(x: $0.y, y: $0.z)
                    case 1: Point2D(x: $0.x, y: $0.z)
                    default: Point2D(x: $0.x, y: $0.y)
                    }
                }, weights: curve.weights)
        }
        let encloser = DefaultCurveDifferentialEncloser()
        let limit = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
        func squaredDistance(_ root: RationalBSplineCurveIntersection2D) throws -> OutwardScalarInterval {
            // The root solver rounds its affine parameter map outward even at
            // a domain endpoint. Intersect with the known source domains before
            // enclosing curve values; this does not extrapolate either curve.
            let first = try encloser.enclosure(of: .bSpline(guide),
                over: ScalarInterval(lower: max(a, root.firstParameterEnclosure.lower),
                    upper: min(b, root.firstParameterEnclosure.upper)), tolerance: tolerance).position
            let second = try encloser.enclosure(of: .bSpline(boundary),
                over: ScalarInterval(lower: max(c, root.secondParameterEnclosure.lower),
                    upper: min(d, root.secondParameterEnclosure.upper)), tolerance: tolerance).position
            func squared(_ a: ScalarInterval, _ b: ScalarInterval) -> OutwardScalarInterval {
                let delta = OutwardScalarInterval(lower: a.lower, upper: a.upper)
                    - OutwardScalarInterval(lower: b.lower, upper: b.upper)
                let low = max(0, delta.absoluteLowerBound)
                let high = delta.absoluteUpperBound
                return OutwardScalarInterval(lower: max(0, (low * low).nextDown),
                    upper: (high * high).nextUp)
            }
            return squared(first.x, second.x) + squared(first.y, second.y) + squared(first.z, second.z)
        }
        let roots = try RationalBSplineCurveIntersector2D().intersections(
            first: projected(guide), second: projected(boundary),
            maximumSubdivisionDepth: 32, maximumSubdivisionCells: 1_048_576,
            accepting: { root in
                let distance = try squaredDistance(root)
                return distance.upper <= limit.lower || distance.lower > limit.upper
            }, tolerance: tolerance)
        return try roots.compactMap { root in
            guard try squaredDistance(root).upper <= limit.lower else { return nil }
            let parameter = try ScalarInterval(lower: max(a, root.firstParameterEnclosure.lower),
                upper: min(b, root.firstParameterEnclosure.upper)).midpoint
            return (try guide.point(at: parameter, tolerance: tolerance), parameter)
        }
    }

    private func boundaryLoopIndex(
        containing point: Point3D,
        section: ExactLoftGuideSection,
        tolerance: ModelingTolerance
    ) throws -> Int? {
        var match: Int?
        for loopIndex in section.loops.indices {
            guard try boundaryContains(
                point,
                spans: section.loops[loopIndex],
                tolerance: tolerance
            ) else {
                continue
            }
            guard match == nil else {
                throw KernelError(
                    phase: .geometry,
                    code: .ambiguousSelection,
                    tolerance: tolerance,
                    message: "A Loft guide endpoint matches more than one profile boundary loop."
                )
            }
            match = loopIndex
        }
        return match
    }

    private func boundaryContains(
        _ point: Point3D,
        spans: [ExactBSplineCurveSpan],
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for span in spans {
            do {
                let projection = try Curve3D.bSpline(span.curve)
                    .parameterProjection(of: point, tolerance: tolerance)
                if projection.residual <= tolerance.distance {
                    return true
                }
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
        }
        return false
    }

    private func plane(
        for sketchPlane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> Plane3D {
        let value: Plane3D = switch sketchPlane {
        case .xy:
            Plane3D(origin: .origin, normal: .unitZ)
        case .yz:
            Plane3D(origin: .origin, normal: .unitX)
        case .zx:
            Plane3D(origin: .origin, normal: .unitY)
        case let .plane(plane):
            plane
        }
        try value.validate(tolerance: tolerance)
        return Plane3D(
            origin: value.origin,
            normal: try value.normal.normalized(tolerance: tolerance.distance)
        )
    }
}
