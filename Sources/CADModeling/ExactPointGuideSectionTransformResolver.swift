import CADCore
import CADGeometry
import CADIR
import Foundation

package struct ExactPointGuideSectionTransformResolver: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The section's end transform for straight guides along a straight path: one guide turns and
    /// scales it (a similarity taking the guide's contact to its end), two deform it by the linear
    /// map taking both contacts to their guides' ends. Swept as the linear interpolation from the
    /// identity, each contact runs along its guide exactly.
    package func resolve(
        section: ResolvedModelingSection,
        pathStart: Point3D,
        pathEnd: Point3D,
        guides: [EvaluatedCurve],
        distanceFraction: Double,
        featureID: FeatureID?
    ) throws -> ExactSectionTransform2D {
        try tolerance.validate()
        let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: tolerance)
        let sectionSpans: [ExactBSplineCurveSpan]
        let sectionPlane: SketchPlane
        switch section {
        case .profile(let profile, _):
            sectionSpans = try spanBuilder.profileLoopSpans(from: profile).flatMap { $0 }
            sectionPlane = profile.plane
        case .curve(let curve):
            guard let plane = curve.plane else {
                throw KernelError(phase: .geometry, code: .sweepGuideContactUnavailable, featureID: featureID, tolerance: tolerance,
                                  message: "Exact point-guide Sweep requires section-plane metadata.")
            }
            sectionSpans = try spanBuilder.sectionSpans(from: curve)
            sectionPlane = plane
        }
        guard (1...2).contains(guides.count) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): a linear map of the section's plane is fixed by
            // two contacts, so a third Point guide is refused. Production path:
            // ExactPointGuideSectionTransformResolver for every Point-guided straight sweep.
            // Complete only when further guides bend the section (a non-linear deformation within
            // an allowance), verified by a sweep with three guides' sections.
            throw KernelError(phase: .geometry, code: .sweepGuideConstraintUnavailable, featureID: featureID, tolerance: tolerance,
                              message: "A Point-guided sweep takes one or two guides.")
        }
        let pairs = try guides.map { guide in
            try contact(sectionSpans: sectionSpans, sectionPlane: sectionPlane, pathStart: pathStart, pathEnd: pathEnd,
                        guide: guide, distanceFraction: distanceFraction, featureID: featureID, spanBuilder: spanBuilder)
        }
        let transform: ExactSectionTransform2D
        if pairs.count == 1 {
            transform = try .similarity(mapping: pairs[0].source, to: pairs[0].target, tolerance: tolerance)
        } else {
            transform = try .linear(mapping: (pairs[0].source, pairs[1].source), to: (pairs[0].target, pairs[1].target),
                                    tolerance: tolerance)
            // The section must not fold on its way: det(I + t(M − I)) stays positive on [0, 1].
            let a = ExactSectionTransform2D(m11: transform.m11 - 1, m12: transform.m12, m21: transform.m21, m22: transform.m22 - 1)
            let (b, c) = (a.m11 + a.m22, a.determinant)
            var candidates = [0.0, 1.0]
            if c != 0 { candidates.append(min(1, max(0, -b / (2 * c)))) }
            guard candidates.allSatisfy({ 1 + b * $0 + c * $0 * $0 > tolerance.relative }) else {
                throw KernelError(phase: .geometry, code: .sweepGuideTransformCollapse, featureID: featureID, tolerance: tolerance,
                                  message: "Two Point guides fold the section on its way along the path.")
            }
        }
        for pair in pairs {
            let mapped = transform.applied(to: pair.source)
            let residual = hypot(mapped.x - pair.target.x, mapped.y - pair.target.y)
            guard residual <= tolerance.distance else {
                throw KernelError(phase: .geometry, code: .sweepGuideContactUnavailable, featureID: featureID, residual: residual,
                                  tolerance: tolerance, message: "Exact point-guide Sweep failed its terminal guide-contact residual check.")
            }
        }
        return transform
    }

    /// A guide's contact with the section (its start, on the section's boundary) and where it ends,
    /// both as offsets in the section's plane from the path.
    private func contact(
        sectionSpans: [ExactBSplineCurveSpan],
        sectionPlane: SketchPlane,
        pathStart: Point3D,
        pathEnd: Point3D,
        guide: EvaluatedCurve,
        distanceFraction: Double,
        featureID: FeatureID?,
        spanBuilder: ExactBSplineCurveSpanBuilder
    ) throws -> (source: Point2D, target: Point2D) {
        guard distanceFraction.isFinite,
              distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw FeatureEvaluationError.invalidDistance(distanceFraction)
        }
        let guideSpans = try spanBuilder.sectionSpans(from: guide)
        let guideEndpoints = try certifiedStraightGuideEndpoints(
            guideSpans,
            featureID: featureID
        )
        let guideEnd = guideEndpoints.start
            + (guideEndpoints.end - guideEndpoints.start) * distanceFraction
        let plane = try ExactSweepSectionPlane(
            sectionPlane,
            tolerance: tolerance
        )
        let sourceOffset = guideEndpoints.start - pathStart
        let targetOffset = guideEnd - pathEnd
        try validateInSectionPlane(sourceOffset, plane: plane, featureID: featureID, role: "start")
        try validateInSectionPlane(targetOffset, plane: plane, featureID: featureID, role: "end")
        let pathAnchor = plane.orthogonalProjection(pathStart)
        let contact = pathAnchor + sourceOffset
        try validateContact(contact, on: sectionSpans, featureID: featureID)
        let source = plane.localOffset(from: pathAnchor, to: contact)
        let target = plane.localOffset(targetOffset)
        let targetLengthSquared = target.x * target.x + target.y * target.y
        guard targetLengthSquared > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .sweepGuideTransformCollapse,
                featureID: featureID,
                residual: targetLengthSquared,
                tolerance: tolerance,
                message: "Exact point-guide Sweep collapses the guide contact onto the path axis."
            )
        }
        return (source, target)
    }

    private func certifiedStraightGuideEndpoints(
        _ spans: [ExactBSplineCurveSpan],
        featureID: FeatureID?
    ) throws -> (start: Point3D, end: Point3D) {
        guard let first = spans.first,
              let last = spans.last else {
            throw KernelError(
                phase: .geometry,
                code: .sweepGuideConstraintUnavailable,
                featureID: featureID,
                tolerance: tolerance,
                message: "Exact point-guide Sweep requires a bounded guide curve."
            )
        }
        let chord = last.endPoint - first.startPoint
        let length = chord.length
        guard length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .sweepGuideConstraintUnavailable,
                featureID: featureID,
                residual: length,
                tolerance: tolerance,
                message: "Exact point-guide Sweep requires a nondegenerate straight guide."
            )
        }
        let direction = try chord.normalized(
            tolerance: tolerance.distance
        )
        var previousAdvance = -Double.infinity
        for span in spans {
            for point in span.curve.controlPoints {
                let offset = point - first.startPoint
                let advance = offset.dot(direction)
                let perpendicular = offset - direction * advance
                guard perpendicular.length <= tolerance.distance,
                      advance >= previousAdvance - tolerance.distance,
                      advance >= -tolerance.distance,
                      advance <= length + tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .sweepGuideConstraintUnavailable,
                        featureID: featureID,
                        residual: max(
                            perpendicular.length,
                            max(previousAdvance - advance, 0.0)
                        ),
                        tolerance: tolerance,
                        message: "Exact point-guide Sweep requires a monotone straight rational guide."
                    )
                }
                previousAdvance = advance
            }
        }
        return (first.startPoint, last.endPoint)
    }

    private func validateInSectionPlane(
        _ offset: Vector3D,
        plane: ExactSweepSectionPlane,
        featureID: FeatureID?,
        role: String
    ) throws {
        let residual = abs(offset.dot(plane.plane.normal))
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .sweepGuideContactUnavailable,
                featureID: featureID,
                residual: residual,
                tolerance: tolerance,
                message: "Exact point-guide Sweep \(role) offset must lie in the section plane."
            )
        }
    }

    private func validateContact(
        _ contact: Point3D,
        on spans: [ExactBSplineCurveSpan],
        featureID: FeatureID?
    ) throws {
        for span in spans {
            let curve = Curve3D.bSpline(span.curve)
            do {
                let projection = try curve.parameterProjection(
                    of: contact,
                    tolerance: tolerance
                )
                let projected = try curve.point(
                    at: projection.parameter,
                    tolerance: tolerance
                )
                if (projected - contact).length <= tolerance.distance {
                    return
                }
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            } catch {
                throw error
            }
        }
        throw KernelError(
            phase: .geometry,
            code: .sweepGuideContactUnavailable,
            featureID: featureID,
            tolerance: tolerance,
            message: "Exact point-guide Sweep must begin at a point on the section boundary."
        )
    }
}
