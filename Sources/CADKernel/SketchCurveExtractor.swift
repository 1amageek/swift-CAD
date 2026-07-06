import Foundation
import CADCore
import CADIR

public struct SketchCurveExtractor: SketchCurveExtracting {
    private let resolver: ParameterResolving
    private let tolerance: ModelingTolerance
    private let circularSamplingPolicy = CircularCurveSamplingPolicy.standard
    private let splineTessellator: CubicBezierSplineTessellator

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        tolerance: ModelingTolerance = .standard
    ) {
        self.resolver = resolver
        self.tolerance = tolerance
        self.splineTessellator = CubicBezierSplineTessellator(tolerance: tolerance)
    }

    public func extractCurves(
        from sketch: Sketch,
        sourceFeatureID: FeatureID,
        parameters: ResolvedParameterTable
    ) throws -> [EvaluatedCurve] {
        try tolerance.validate()
        let curves = try sketch.entities
            .sorted(by: { $0.key.description < $1.key.description })
            .compactMap { entityID, entity -> EvaluatedCurve? in
                switch entity {
                case .point:
                    return nil
                case let .line(line):
                    let start = try resolve(line.start, parameters: parameters)
                    let end = try resolve(line.end, parameters: parameters)
                    let start3D = try mapTo3D(start, on: sketch.plane)
                    let end3D = try mapTo3D(end, on: sketch.plane)
                    let segment = end3D - start3D
                    let length = segment.length
                    let direction = try segment.normalized(tolerance: tolerance.distance)
                    let curve = EvaluatedCurve(
                        sourceFeatureID: sourceFeatureID,
                        source: .sketchEntity(entityID),
                        kind: .line,
                        points: [start3D, end3D],
                        plane: sketch.plane,
                        exactCurve: .line(Line3D(origin: start3D, direction: direction)),
                        exactParameterDomain: .closed(0.0, length)
                    )
                    try curve.validate(tolerance: tolerance)
                    return curve
                case let .circle(circle):
                    let center = try resolve(circle.center, parameters: parameters)
                    let radius = try resolveLength(
                        circle.radius,
                        operation: "sketch.circle.radius",
                        parameters: parameters
                    )
                    let points = try polygonizedCircle(center: center, radius: radius)
                        .map { try mapTo3D($0, on: sketch.plane) }
                    let center3D = try mapTo3D(center, on: sketch.plane)
                    let normal = try planeNormal(for: sketch.plane)
                    let curve = EvaluatedCurve(
                        sourceFeatureID: sourceFeatureID,
                        source: .sketchEntity(entityID),
                        kind: .circle,
                        points: points,
                        isClosed: true,
                        plane: sketch.plane,
                        exactCurve: .circle(Circle3D(center: center3D, normal: normal, radius: radius))
                    )
                    try curve.validate(tolerance: tolerance)
                    return curve
                case let .arc(arc):
                    let center = try resolve(arc.center, parameters: parameters)
                    let radius = try resolveLength(
                        arc.radius,
                        operation: "sketch.arc.radius",
                        parameters: parameters
                    )
                    let startAngle = try resolveAngle(
                        arc.startAngle,
                        operation: "sketch.arc.startAngle",
                        parameters: parameters
                    )
                    let endAngle = try resolveAngle(
                        arc.endAngle,
                        operation: "sketch.arc.endAngle",
                        parameters: parameters
                    )
                    let angleSpan = try normalizedAngleSpan(startAngle: startAngle, endAngle: endAngle)
                    let points = try polygonizedArc(
                        center: center,
                        radius: radius,
                        startAngle: startAngle,
                        angleSpan: angleSpan
                    ).map { try mapTo3D($0, on: sketch.plane) }
                    let center3D = try mapTo3D(center, on: sketch.plane)
                    let normal = try planeNormal(for: sketch.plane)
                    let circle = Circle3D(center: center3D, normal: normal, radius: radius)
                    let startParameter = try circleParameter(for: try requireFirst(points), on: circle)
                    let curve = EvaluatedCurve(
                        sourceFeatureID: sourceFeatureID,
                        source: .sketchEntity(entityID),
                        kind: .arc,
                        points: points,
                        plane: sketch.plane,
                        exactCurve: .circle(circle),
                        exactParameterDomain: .closed(startParameter, startParameter + angleSpan)
                    )
                    try curve.validate(tolerance: tolerance)
                    return curve
                case let .spline(spline):
                    let controlPoints = try spline.controlPoints.map { point in
                        try resolve(point, parameters: parameters)
                    }
                    let controlPoints3D = try controlPoints.map { try mapTo3D($0, on: sketch.plane) }
                    var points = try splineTessellator.points(for: controlPoints)
                    if spline.isClosed,
                       let first = points.first,
                       let last = points.last,
                       isClose(first, last) == false {
                        points.append(first)
                    }
                    let exactCurve = try cubicBezierSplineCurve(controlPoints: controlPoints3D)
                    let curve = EvaluatedCurve(
                        sourceFeatureID: sourceFeatureID,
                        source: .sketchEntity(entityID),
                        kind: .spline,
                        points: try points.map { try mapTo3D($0, on: sketch.plane) },
                        isClosed: spline.isClosed,
                        plane: sketch.plane,
                        exactCurve: .bSpline(exactCurve)
                    )
                    try curve.validate(tolerance: tolerance)
                    return curve
                }
            }
        guard curves.isEmpty == false else {
            throw SketchError.unsupportedEntity("Sketch contains no curve entities.")
        }
        return curves
    }

    private func cubicBezierSplineCurve(controlPoints: [Point3D]) throws -> BSplineCurve3D {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw SketchError.unsupportedEntity("Cubic sketch spline control point count must be 3n + 1 and at least 4.")
        }
        let spanCount = (controlPoints.count - 1) / 3
        let curve = BSplineCurve3D(
            degree: 3,
            knots: cubicBezierSplineKnots(spanCount: spanCount),
            controlPoints: controlPoints
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func cubicBezierSplineKnots(spanCount: Int) -> [Double] {
        var knots = Array(repeating: 0.0, count: 4)
        if spanCount > 1 {
            for spanIndex in 1..<spanCount {
                knots.append(contentsOf: Array(repeating: Double(spanIndex), count: 3))
            }
        }
        knots.append(contentsOf: Array(repeating: Double(spanCount), count: 4))
        return knots
    }

    private func resolve(_ point: SketchPoint, parameters: ResolvedParameterTable) throws -> Point2D {
        let x = try resolver.evaluate(point.x, parameters: parameters, variables: [:])
        let y = try resolver.evaluate(point.y, parameters: parameters, variables: [:])
        guard x.kind == .length else {
            throw UnitError.expectedQuantity(operation: "sketch.x", expected: .length, actual: x.kind)
        }
        guard y.kind == .length else {
            throw UnitError.expectedQuantity(operation: "sketch.y", expected: .length, actual: y.kind)
        }
        return Point2D(x: x.value, y: y.value)
    }

    private func resolveLength(
        _ expression: CADExpression,
        operation: String,
        parameters: ResolvedParameterTable
    ) throws -> Double {
        let value = try resolver.evaluate(expression, parameters: parameters, variables: [:])
        guard value.kind == .length else {
            throw UnitError.expectedQuantity(operation: operation, expected: .length, actual: value.kind)
        }
        guard value.value.isFinite, value.value > tolerance.distance else {
            throw GeometryError.invalidRadius(value.value)
        }
        return value.value
    }

    private func resolveAngle(
        _ expression: CADExpression,
        operation: String,
        parameters: ResolvedParameterTable
    ) throws -> Double {
        let value = try resolver.evaluate(expression, parameters: parameters, variables: [:])
        guard value.kind == .angle else {
            throw UnitError.expectedQuantity(operation: operation, expected: .angle, actual: value.kind)
        }
        guard value.value.isFinite else {
            throw GeometryError.invalidCoordinate(value.value)
        }
        return value.value
    }

    private func polygonizedCircle(center: Point2D, radius: Double) throws -> [Point2D] {
        let segmentCount = try circleSegmentCount(radius: radius)
        var points = (0..<segmentCount).map { index in
            let angle = Double(index) / Double(segmentCount) * Double.pi * 2.0
            return Point2D(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
        if let first = points.first {
            points.append(first)
        }
        return points
    }

    private func polygonizedArc(
        center: Point2D,
        radius: Double,
        startAngle: Double,
        angleSpan: Double
    ) throws -> [Point2D] {
        let segmentCount = try arcSegmentCount(radius: radius, angleSpan: angleSpan)
        return (0...segmentCount).map { index in
            let ratio = Double(index) / Double(segmentCount)
            let angle = startAngle + angleSpan * ratio
            return Point2D(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }

    private func circleSegmentCount(radius: Double) throws -> Int {
        try circularSamplingPolicy.fullCircleSegmentCount(
            radius: radius,
            tolerance: tolerance
        )
    }

    private func arcSegmentCount(radius: Double, angleSpan: Double) throws -> Int {
        try circularSamplingPolicy.arcSegmentCount(
            radius: radius,
            angleSpan: angleSpan,
            tolerance: tolerance
        )
    }

    private func normalizedAngleSpan(startAngle: Double, endAngle: Double) throws -> Double {
        guard startAngle.isFinite, endAngle.isFinite else {
            throw GeometryError.invalidCoordinate(endAngle)
        }
        let fullCircle = Double.pi * 2.0
        let delta = endAngle - startAngle
        // A near-zero sweep is a degenerate arc, not an implicit full circle:
        // silently promoting it to 2*pi turned editing mistakes into extra
        // profile loops and shifted existing profile indices.
        guard abs(delta) > tolerance.angle else {
            throw SketchError.degenerateProfile
        }
        // Remainder-based normalization stays O(1) for arbitrarily large
        // angle expressions; the previous +/- 2*pi loops hung on huge values.
        var span = delta.truncatingRemainder(dividingBy: fullCircle)
        if span <= tolerance.angle {
            span += fullCircle
        }
        guard span > tolerance.angle else {
            throw SketchError.degenerateProfile
        }
        return min(span, fullCircle)
    }

    private func mapTo3D(_ point: Point2D, on plane: SketchPlane) throws -> Point3D {
        switch plane {
        case .xy:
            return Point3D(x: point.x, y: point.y, z: 0.0)
        case .yz:
            return Point3D(x: 0.0, y: point.x, z: point.y)
        case .zx:
            return Point3D(x: point.y, y: 0.0, z: point.x)
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            let v = normal.cross(u)
            return plane.origin + (u * point.x) + (v * point.y)
        }
    }

    private func planeNormal(for plane: SketchPlane) throws -> Vector3D {
        switch plane {
        case .xy:
            return .unitZ
        case .yz:
            return .unitX
        case .zx:
            return .unitY
        case let .plane(plane):
            return try plane.normal.normalized(tolerance: tolerance.distance)
        }
    }

    private func circleParameter(for point: Point3D, on circle: Circle3D) throws -> Double {
        let (u, v) = try circleBasis(for: circle)
        let offset = point - circle.center
        return atan2(offset.dot(v), offset.dot(u))
    }

    private func circleBasis(for circle: Circle3D) throws -> (Vector3D, Vector3D) {
        let normal = try circle.normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        return (u, v)
    }

    private func isClose(_ lhs: Point2D, _ rhs: Point2D) -> Bool {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot() <= tolerance.distance
    }
}

private func requireFirst<Element>(_ values: [Element]) throws -> Element {
    guard let first = values.first else {
        throw FeatureEvaluationError.emptyResult("Expected at least one curve sample.")
    }
    return first
}
