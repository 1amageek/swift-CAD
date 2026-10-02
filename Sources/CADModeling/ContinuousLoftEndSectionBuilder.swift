import Foundation
import CADCore
import CADGeometry

/// Continuous lofting's far section: a Loft from one open section along two guides, each leaving
/// one of its ends (Plasticity's Loft from a single edge, its two neighbouring edges the guides),
/// ends on the section carried by the similarity — the least rotation, a uniform scale and a move
/// — that takes its ends to the guides' far ends. The map is affine, so the B-spline spans carry
/// over exactly by their control points.
package struct ContinuousLoftEndSectionBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func endSection(of section: [ExactBSplineCurveSpan], guides: [[ExactBSplineCurveSpan]], featureID: FeatureID) throws -> [ExactBSplineCurveSpan] {
        guard let first = section.first, let last = section.last, guides.count == 2 else {
            throw failure(featureID, "A Loft from one section runs along two guides.")
        }
        let (start, end) = (first.startPoint, last.endPoint)
        guard start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) == false else {
            throw failure(featureID, "A Loft from one section needs an open section.")
        }
        // Each guide's end away from the section, found by which section end it leaves.
        var far: [Bool: Point3D] = [:]
        for guide in guides {
            guard let a = guide.first?.startPoint, let b = guide.last?.endPoint else {
                throw failure(featureID, "A Loft guide is empty.")
            }
            for (near, away) in [(a, b), (b, a)] {
                if near.isApproximatelyEqual(to: start, tolerance: tolerance.distance) { far[true] = away }
                if near.isApproximatelyEqual(to: end, tolerance: tolerance.distance) { far[false] = away }
            }
        }
        guard let farStart = far[true], let farEnd = far[false] else {
            throw failure(featureID, "A Loft from one section needs a guide leaving each of its ends.")
        }
        let across = end - start
        let target = farEnd - farStart
        guard target.length > tolerance.distance else {
            throw failure(featureID, "A Loft from one section needs its guides to end apart.")
        }
        let scale = target.length / across.length
        let from = try across.normalized(tolerance: tolerance.distance)
        let to = try target.normalized(tolerance: tolerance.distance)
        let seed: Vector3D = abs(from.x) < 0.9 ? .unitX : .unitY
        let flipAxis = try from.cross(seed).normalized(tolerance: tolerance.distance)
        func rotated(_ v: Vector3D) -> Vector3D {
            // Rodrigues about from × to; opposite directions turn half a turn about an axis square
            // to them.
            let axis = from.cross(to)
            let cosine = from.dot(to)
            if axis.length <= tolerance.angle {
                guard cosine < 0 else { return v }
                return flipAxis * (2 * flipAxis.dot(v)) - v
            }
            let k = axis * (1 / axis.length)
            let sine = axis.length
            return v * cosine + k.cross(v) * sine + k * (k.dot(v) * (1 - cosine))
        }
        func mapped(_ p: Point3D) -> Point3D { farStart + rotated(p - start) * scale }
        return try section.map { span in
            let curve = BSplineCurve3D(degree: span.curve.degree, knots: span.curve.knots,
                                       controlPoints: span.curve.controlPoints.map(mapped), weights: span.curve.weights)
            return try ExactBSplineCurveSpan(curve: curve, tolerance: tolerance)
        }
    }

    private func failure(_ featureID: FeatureID, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance, message: message)
    }
}
