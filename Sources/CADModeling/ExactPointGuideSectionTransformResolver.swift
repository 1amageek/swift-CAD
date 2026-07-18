import CADCore
import CADGeometry
import CADIR
import Foundation

package struct ExactPointGuideSectionTransformResolver: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func resolve(
        profile: Profile,
        pathStart: Point3D,
        pathEnd: Point3D,
        guide: EvaluatedCurve,
        distanceFraction: Double,
        featureID: FeatureID?
    ) throws -> ExactSectionTransform2D {
        let spanBuilder = ExactBSplineCurveSpanBuilder(
            tolerance: tolerance
        )
        return try resolve(
            sectionSpans: spanBuilder.profileSpans(from: profile),
            sectionPlane: profile.plane,
            pathStart: pathStart,
            pathEnd: pathEnd,
            guide: guide,
            distanceFraction: distanceFraction,
            featureID: featureID,
            spanBuilder: spanBuilder
        )
    }

    package func resolve(
        section: EvaluatedCurve,
        pathStart: Point3D,
        pathEnd: Point3D,
        guide: EvaluatedCurve,
        distanceFraction: Double,
        featureID: FeatureID?
    ) throws -> ExactSectionTransform2D {
        guard let plane = section.plane else {
            throw KernelError(
                phase: .geometry,
                code: .sweepGuideContactUnavailable,
                featureID: featureID,
                tolerance: tolerance,
                message: "Exact point-guide Sweep requires section-plane metadata."
            )
        }
        let spanBuilder = ExactBSplineCurveSpanBuilder(
            tolerance: tolerance
        )
        return try resolve(
            sectionSpans: spanBuilder.sectionSpans(from: section),
            sectionPlane: plane,
            pathStart: pathStart,
            pathEnd: pathEnd,
            guide: guide,
            distanceFraction: distanceFraction,
            featureID: featureID,
            spanBuilder: spanBuilder
        )
    }

    private func resolve(
        sectionSpans: [ExactBSplineCurveSpan],
        sectionPlane: SketchPlane,
        pathStart: Point3D,
        pathEnd: Point3D,
        guide: EvaluatedCurve,
        distanceFraction: Double,
        featureID: FeatureID?,
        spanBuilder: ExactBSplineCurveSpanBuilder
    ) throws -> ExactSectionTransform2D {
        try tolerance.validate()
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
        try validateInSectionPlane(
            sourceOffset,
            plane: plane,
            featureID: featureID,
            role: "start"
        )
        try validateInSectionPlane(
            targetOffset,
            plane: plane,
            featureID: featureID,
            role: "end"
        )
        let pathAnchor = plane.orthogonalProjection(pathStart)
        let contact = pathAnchor + sourceOffset
        try validateContact(
            contact,
            on: sectionSpans,
            featureID: featureID
        )
        let source = plane.localOffset(
            from: pathAnchor,
            to: contact
        )
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
        let transform = try ExactSectionTransform2D.similarity(
            mapping: source,
            to: target,
            tolerance: tolerance
        )
        let mapped = transform.applied(to: source)
        let residual = hypot(mapped.x - target.x, mapped.y - target.y)
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .sweepGuideContactUnavailable,
                featureID: featureID,
                residual: residual,
                tolerance: tolerance,
                message: "Exact point-guide Sweep failed its terminal guide-contact residual check."
            )
        }
        return transform
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
