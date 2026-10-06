import CADCore

/// Encloses signed distance on the complete source chart interval.
struct OverlapPlanarMembershipCertifier {
    func deviation(of curve: Curve3D, over range: ScalarInterval,
                   on plane: CanonicalAnalyticSurface.Plane, tolerance: ModelingTolerance) throws -> Double {
        try CurrentTaskCancellationChecker().checkCancellation()
        // The interval-specific encloser covers translated periodic spans as well.
        // A fundamental-domain-only prepared decomposition cannot authorize this range.
        let position = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
            of: curve, over: range, tolerance: tolerance)
        let normal = IntervalVector3DBounds(x: .exact(plane.normal.x),
            y: .exact(plane.normal.y), z: .exact(plane.normal.z))
        let length = OutwardScalarInterval(lower: normal.lengthLowerBound, upper: normal.lengthUpperBound)
        let signedNumerator = (position.x.value - .exact(plane.origin.x)) * normal.x
            + (position.y.value - .exact(plane.origin.y)) * normal.y
            + (position.z.value - .exact(plane.origin.z)) * normal.z
        guard length.isFinite, length.lower > 0,
              let signedDistance = signedNumerator.divided(by: length), signedDistance.isFinite else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                message: "The complete source interval has no finite normalized plane-distance enclosure.")
        }
        let bound = signedDistance.absoluteUpperBound
        guard bound <= tolerance.distance else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, residual: bound, tolerance: tolerance,
                message: "A hosting-surface coincidence candidate exceeds its whole-span plane-distance certificate.")
        }
        return bound
    }
}
