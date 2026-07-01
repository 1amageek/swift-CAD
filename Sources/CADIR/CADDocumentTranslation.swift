import CADCore

public extension CADDocument {
    func translatingSources(
        by vector: Vector3D,
        tolerance: ModelingTolerance = .standard
    ) throws -> CADDocument {
        try vector.validate()
        try tolerance.validate()
        guard vector.length > tolerance.distance else {
            return self
        }

        var document = self
        for featureID in document.designGraph.order {
            guard var node = document.designGraph.nodes[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Document translation found a missing ordered feature.")
            }
            node.operation = try node.operation.translatingSources(
                by: vector,
                tolerance: tolerance
            )
            document.designGraph.nodes[featureID] = node
        }
        try document.validate(tolerance: tolerance)
        return document
    }
}

private extension FeatureOperation {
    func translatingSources(
        by vector: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> FeatureOperation {
        switch self {
        case .sketch(let sketch):
            return .sketch(try sketch.translatingSources(by: vector, tolerance: tolerance))
        case .extrude,
             .sweep,
             .loft,
             .boolean,
             .faceLoopOffset,
             .edgeOffset,
             .faceDelete,
             .faceDraft,
             .curveOffset,
             .curveTrim:
            return self
        case .revolve(var revolve):
            revolve.axis.origin = revolve.axis.origin + vector
            return .revolve(revolve)
        case .polySpline(var polySpline):
            polySpline.sourceMesh.positions = polySpline.sourceMesh.positions.map { $0 + vector }
            polySpline.controlPointOverrides = polySpline.controlPointOverrides.map { override in
                var translated = override
                translated.point = translated.point + vector
                return translated
            }
            return .polySpline(polySpline)
        case .bSplineSurface(var surfaceFeature):
            surfaceFeature.surface.controlPoints = surfaceFeature.surface.controlPoints.map { row in
                row.map { $0 + vector }
            }
            return .bSplineSurface(surfaceFeature)
        case .faceKnife(var faceKnife):
            faceKnife.loop = faceKnife.loop.map { $0 + vector }
            return .faceKnife(faceKnife)
        case .bridgeCurve(var bridgeCurve):
            bridgeCurve.start.curve = bridgeCurve.start.curve.translatingSources(by: vector)
            bridgeCurve.end.curve = bridgeCurve.end.curve.translatingSources(by: vector)
            return .bridgeCurve(bridgeCurve)
        case .curveEdit(var curveEdit):
            curveEdit.edits = curveEdit.edits.map { $0.translatingSources(by: vector) }
            return .curveEdit(curveEdit)
        }
    }
}

private extension Sketch {
    func translatingSources(
        by vector: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Sketch {
        var sketch = self
        switch sketch.plane {
        case .xy:
            try requireInPlaneTranslation(
                normalDistance: vector.z,
                planeName: "xy",
                tolerance: tolerance
            )
            sketch.entities = sketch.entities.mapValues {
                $0.translatingLocalCoordinates(deltaX: vector.x, deltaY: vector.y, tolerance: tolerance)
            }
        case .yz:
            try requireInPlaneTranslation(
                normalDistance: vector.x,
                planeName: "yz",
                tolerance: tolerance
            )
            sketch.entities = sketch.entities.mapValues {
                $0.translatingLocalCoordinates(deltaX: vector.y, deltaY: vector.z, tolerance: tolerance)
            }
        case .zx:
            try requireInPlaneTranslation(
                normalDistance: vector.y,
                planeName: "zx",
                tolerance: tolerance
            )
            sketch.entities = sketch.entities.mapValues {
                $0.translatingLocalCoordinates(deltaX: vector.z, deltaY: vector.x, tolerance: tolerance)
            }
        case .plane(var plane):
            plane.origin = plane.origin + vector
            sketch.plane = .plane(plane)
        }
        return sketch
    }

    private func requireInPlaneTranslation(
        normalDistance: Double,
        planeName: String,
        tolerance: ModelingTolerance
    ) throws {
        guard abs(normalDistance) <= tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Document source translation cannot move a \(planeName) sketch along its normal without changing the sketch plane representation."
            )
        }
    }
}

private extension SketchEntity {
    func translatingLocalCoordinates(
        deltaX: Double,
        deltaY: Double,
        tolerance: ModelingTolerance
    ) -> SketchEntity {
        switch self {
        case .point(let point):
            return .point(point.translatingLocalCoordinates(
                deltaX: deltaX,
                deltaY: deltaY,
                tolerance: tolerance
            ))
        case .line(var line):
            line.start = line.start.translatingLocalCoordinates(
                deltaX: deltaX,
                deltaY: deltaY,
                tolerance: tolerance
            )
            line.end = line.end.translatingLocalCoordinates(
                deltaX: deltaX,
                deltaY: deltaY,
                tolerance: tolerance
            )
            return .line(line)
        case .circle(var circle):
            circle.center = circle.center.translatingLocalCoordinates(
                deltaX: deltaX,
                deltaY: deltaY,
                tolerance: tolerance
            )
            return .circle(circle)
        case .arc(var arc):
            arc.center = arc.center.translatingLocalCoordinates(
                deltaX: deltaX,
                deltaY: deltaY,
                tolerance: tolerance
            )
            return .arc(arc)
        case .spline(var spline):
            spline.controlPoints = spline.controlPoints.map {
                $0.translatingLocalCoordinates(
                    deltaX: deltaX,
                    deltaY: deltaY,
                    tolerance: tolerance
                )
            }
            return .spline(spline)
        }
    }
}

private extension SketchPoint {
    func translatingLocalCoordinates(
        deltaX: Double,
        deltaY: Double,
        tolerance: ModelingTolerance
    ) -> SketchPoint {
        SketchPoint(
            x: x.translatingLength(by: deltaX, tolerance: tolerance),
            y: y.translatingLength(by: deltaY, tolerance: tolerance)
        )
    }
}

private extension CADExpression {
    func translatingLength(
        by delta: Double,
        tolerance: ModelingTolerance
    ) -> CADExpression {
        guard abs(delta) > tolerance.distance else {
            return self
        }
        let deltaExpression = CADExpression.constant(.length(delta, unit: .meter))
        switch self {
        case .constant(let quantity) where quantity.kind == .length:
            return .constant(.length(quantity.value + delta, unit: .meter))
        default:
            return .add(self, deltaExpression)
        }
    }
}

private extension Curve3D {
    func translatingSources(by vector: Vector3D) -> Curve3D {
        switch self {
        case .line(var line):
            line.origin = line.origin + vector
            return .line(line)
        case .circle(var circle):
            circle.center = circle.center + vector
            return .circle(circle)
        case .bSpline(var curve):
            curve.controlPoints = curve.controlPoints.map { $0 + vector }
            return .bSpline(curve)
        }
    }
}

private extension CurveEdit {
    func translatingSources(by vector: Vector3D) -> CurveEdit {
        switch self {
        case .setControlPoint(var edit):
            edit.point = edit.point + vector
            return .setControlPoint(edit)
        case .setKnot,
             .setWeight:
            return self
        }
    }
}
