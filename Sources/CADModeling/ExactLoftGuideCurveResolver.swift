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
        guard profiles.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph(
                "Exact Loft guides require at least two profile sections."
            )
        }
        guard let boundaryLoopCount = profiles.first?.boundaryLoops.count,
              boundaryLoopCount > 0,
              profiles.allSatisfy({
                  $0.boundaryLoops.count == boundaryLoopCount
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
                firstProfile: profiles[0],
                lastProfile: profiles[profiles.index(before: profiles.endIndex)],
                tolerance: context.tolerance
            )
            let contacts = try sectionContacts(
                curve: oriented.curve,
                boundaryLoopIndex: oriented.boundaryLoopIndex,
                guideFeatureID: guide.featureID,
                profiles: profiles,
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
        firstProfile: Profile,
        lastProfile: Profile,
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
        let forwardStartLoop = try profileBoundaryLoopIndex(
            containing: start,
            profile: firstProfile,
            tolerance: tolerance
        )
        let forwardEndLoop = try profileBoundaryLoopIndex(
            containing: end,
            profile: lastProfile,
            tolerance: tolerance
        )
        if let forwardStartLoop,
           forwardStartLoop == forwardEndLoop {
            return (curve, forwardStartLoop)
        }
        let reverseStartLoop = try profileBoundaryLoopIndex(
            containing: end,
            profile: firstProfile,
            tolerance: tolerance
        )
        let reverseEndLoop = try profileBoundaryLoopIndex(
            containing: start,
            profile: lastProfile,
            tolerance: tolerance
        )
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
        profiles: [Profile],
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
        contacts.reserveCapacity(profiles.count)
        contacts.append((
            try curve.point(at: lower, tolerance: tolerance),
            lower
        ))
        for profile in profiles.dropFirst().dropLast() {
            let intersections = try DefaultCurveSurfaceIntersector().intersections(
                curve: .bSpline(curve),
                surface: .plane(try plane(for: profile.plane, tolerance: tolerance)),
                options: CurveSurfaceIntersectionOptions(
                    curveRange: try ScalarInterval(lower: lower, upper: upper)
                ),
                tolerance: tolerance
            )
            var candidates: [(point: Point3D, parameter: Double)] = []
            for intersection in intersections {
                guard try profileBoundaryContains(
                    intersection.point,
                    loop: profile.boundaryLoops[boundaryLoopIndex],
                    tolerance: tolerance
                ) else {
                    continue
                }
                if candidates.contains(where: { candidate in
                    candidate.point.isApproximatelyEqual(
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
        let resolution = max(
            tolerance.relative * max(abs(lower), abs(upper), 1.0),
            Double.ulpOfOne * max(abs(lower), abs(upper), 1.0) * 512.0
        )
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

    private func profileBoundaryLoopIndex(
        containing point: Point3D,
        profile: Profile,
        tolerance: ModelingTolerance
    ) throws -> Int? {
        var match: Int?
        for loopIndex in profile.boundaryLoops.indices {
            guard try profileBoundaryContains(
                point,
                loop: profile.boundaryLoops[loopIndex],
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

    private func profileBoundaryContains(
        _ point: Point3D,
        loop: ProfileLoop,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let spans = try ExactBSplineCurveSpanBuilder(
            tolerance: tolerance
        ).profileSpans(from: loop)
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
