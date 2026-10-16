import CADCore

public extension BSplineCurve2D {
    func rationalBezierPatches(tolerance: ModelingTolerance) throws -> [RationalBezierCurvePatch2D] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try rationalBezierPatches(tolerance: tolerance, using: &execution)
    }

    func rationalBezierPatches<A: ExactScalarAdmission & ~Copyable>(
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> [RationalBezierCurvePatch2D] {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlPoints.count, of: Point3D.self))
        var embedded: [Point3D] = []
        embedded.reserveCapacity(controlPoints.count)
        for point in controlPoints {
            try execution.consumeWork(1)
            embedded.append(Point3D(x: point.x, y: point.y, z: 0))
        }
        let lifted = BSplineCurve3D(degree: degree, knots: knots,
            controlPoints: embedded, weights: weights)
        let patches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: lifted, tolerance: tolerance, using: &execution)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: patches.count, of: RationalBezierCurvePatch2D.self))
        var result: [RationalBezierCurvePatch2D] = []
        result.reserveCapacity(patches.count)
        for patch in patches {
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: patch.controlPoints.count, of: Point2D.self))
            var planar: [Point2D] = []
            planar.reserveCapacity(patch.controlPoints.count)
            for point in patch.controlPoints {
                try execution.consumeWork(1)
                planar.append(Point2D(x: point.x, y: point.y))
            }
            result.append(RationalBezierCurvePatch2D(controlPoints: planar,
                weights: patch.weights, lower: patch.lower, upper: patch.upper))
        }
        return result
    }
}
