import CADCore

package struct DefaultCurvePositionEncloser: CurvePositionEnclosing, Sendable {
    package init() {}

    package func enclosure(
        of curve: Curve3D,
        over parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CoordinateEnclosure3D {
        if case let .surfaceLift(lift) = curve {
            let box = try lift.boundingBox(
                over: parameters,
                tolerance: tolerance
            )
            return CoordinateEnclosure3D(
                x: try ScalarInterval(
                    lower: box.minimum.x,
                    upper: box.maximum.x
                ),
                y: try ScalarInterval(
                    lower: box.minimum.y,
                    upper: box.maximum.y
                ),
                z: try ScalarInterval(
                    lower: box.minimum.z,
                    upper: box.maximum.z
                )
            )
        }
        return try DefaultCurveDifferentialEncloser().enclosure(
            of: curve,
            over: parameters,
            tolerance: tolerance
        ).position
    }
}
