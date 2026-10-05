import CADCore
import CADGeometry

/// A candidate pose admitted against the complete original start-position jet.
package struct OriginalPipeStartPose: Sendable {
    package let origin: Point3D
    package let tangent: Vector3D

    package init(span: ExactBSplineCurveSpan, featureID: FeatureID,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws {
        let source = try OriginalCurveConstructionSource(chart: span.originalChart,
            domain: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, admission: admission)
        let jet = try source.enclosure(over: ScalarInterval(lower: 0, upper: 0),
            tolerance: tolerance, admission: admission)
        func bound(_ p: CoordinateEnclosure3D) -> IntervalVector3DBounds {
            .init(x: .init(lower: p.x.lower, upper: p.x.upper),
                y: .init(lower: p.y.lower, upper: p.y.upper),
                z: .init(lower: p.z.lower, upper: p.z.upper))
        }
        let position = bound(jet.position), direction = bound(jet.firstDerivative)
        let origin = Point3D(x: position.x.midpoint, y: position.y.midpoint, z: position.z.midpoint)
        let displacement = IntervalVector3DBounds(x: position.x - .exact(origin.x),
            y: position.y - .exact(origin.y), z: position.z - .exact(origin.z))
        let candidate = Vector3D(x: direction.x.midpoint, y: direction.y.midpoint, z: direction.z.midpoint)
        let tangent = try candidate.normalized(tolerance: tolerance.distance)
        let dot = direction.x * .exact(tangent.x) + direction.y * .exact(tangent.y) + direction.z * .exact(tangent.z)
        let cross = IntervalVector3DBounds(
            x: direction.y * .exact(tangent.z) - direction.z * .exact(tangent.y),
            y: direction.z * .exact(tangent.x) - direction.x * .exact(tangent.z),
            z: direction.x * .exact(tangent.y) - direction.y * .exact(tangent.x))
        let sine = try CertifiedRotationTrigonometry.evaluate(.exact(min(tolerance.angle, Double.pi * 0.5)),
            tolerance: tolerance, consumeWork: { try admission.chargeWork() }).sine
        let tangentLength = IntervalVector3DBounds(x: .exact(tangent.x),
            y: .exact(tangent.y), z: .exact(tangent.z)).lengthLowerBound
        guard displacement.lengthUpperBound <= tolerance.distance * 0.125,
              direction.lengthLowerBound > 0, dot.lower > 0,
              cross.lengthUpperBound <= (OutwardScalarInterval.exact(direction.lengthLowerBound) * .exact(tangentLength) * .exact(max(0, sine.lower))).lower else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, featureID: featureID,
                tolerance: tolerance, message: "Original Pipe start pose cannot meet its position and tangent allowances.")
        }
        self.origin = origin; self.tangent = tangent
    }
}
