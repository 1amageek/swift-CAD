import CADCore

extension Curve3D {
    /// Classifies representations whose full parameterization is exactly a
    /// straight line, independent of modeling tolerance.
    package var hasExactLinearParameterization: Bool {
        exactLinearLocus != nil
    }

    /// Returns an exact line containing the complete curve locus.
    package var exactLinearLocus: Line3D? {
        let candidate: Line3D?
        switch self {
        case let .line(line):
            candidate = line
        case let .analytic(.line(origin, direction)):
            candidate = Line3D(origin: origin, direction: direction)
        case let .bSpline(curve):
            guard curve.degree == 1, curve.controlPoints.count == 2 else {
                return nil
            }
            candidate = Line3D(
                origin: curve.controlPoints[0],
                direction: curve.controlPoints[1] - curve.controlPoints[0]
            )
        case let .rigidImage(image):
            guard let source = image.source.exactLinearLocus else {
                return nil
            }
            candidate = Line3D(
                origin: image.transform.applying(to: source.origin),
                direction: image.transform.applying(to: source.direction)
            )
        case let .affineImage(image):
            guard let source = image.source.exactLinearLocus else {
                return nil
            }
            candidate = Line3D(
                origin: image.transform.applying(to: source.origin),
                direction: image.transform.applying(to: source.direction)
            )
        case .circle, .analytic, .implicit, .surfaceLift,
             .certifiedIntersection:
            return nil
        }
        guard let candidate, candidate.direction.length > 0.0 else {
            return nil
        }
        return candidate
    }
}
