import Foundation
import CADCore
import CADIR

public struct SketchCurveExtractor: SketchCurveExtracting {
    private let resolver: ParameterResolving
    private let tolerance: ModelingTolerance
    private let minimumCircleSegmentCount = 32
    private let maximumCircleSegmentCount = 8_192
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
                    let curve = EvaluatedCurve(
                        sourceFeatureID: sourceFeatureID,
                        source: .sketchEntity(entityID),
                        kind: .line,
                        points: [
                            try mapTo3D(start, on: sketch.plane),
                            try mapTo3D(end, on: sketch.plane),
                        ]
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
                    let curve = EvaluatedCurve(
                        sourceFeatureID: sourceFeatureID,
                        source: .sketchEntity(entityID),
                        kind: .circle,
                        points: points,
                        isClosed: true
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
                    let points = try polygonizedArc(
                        center: center,
                        radius: radius,
                        startAngle: startAngle,
                        endAngle: endAngle
                    ).map { try mapTo3D($0, on: sketch.plane) }
                    let curve = EvaluatedCurve(
                        sourceFeatureID: sourceFeatureID,
                        source: .sketchEntity(entityID),
                        kind: .arc,
                        points: points
                    )
                    try curve.validate(tolerance: tolerance)
                    return curve
                case let .spline(spline):
                    let controlPoints = try spline.controlPoints.map { point in
                        try resolve(point, parameters: parameters)
                    }
                    var points = try splineTessellator.points(for: controlPoints)
                    if spline.isClosed,
                       let first = points.first,
                       let last = points.last,
                       isClose(first, last) == false {
                        points.append(first)
                    }
                    let curve = EvaluatedCurve(
                        sourceFeatureID: sourceFeatureID,
                        source: .sketchEntity(entityID),
                        kind: .spline,
                        points: try points.map { try mapTo3D($0, on: sketch.plane) },
                        isClosed: spline.isClosed
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
        endAngle: Double
    ) throws -> [Point2D] {
        let span = try normalizedAngleSpan(startAngle: startAngle, endAngle: endAngle)
        let segmentCount = try arcSegmentCount(radius: radius, angleSpan: span)
        return (0...segmentCount).map { index in
            let ratio = Double(index) / Double(segmentCount)
            let angle = startAngle + span * ratio
            return Point2D(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }

    private func circleSegmentCount(radius: Double) throws -> Int {
        let ratio = min(max(tolerance.distance / radius, 1.0e-9), 0.5)
        let angle = 2.0 * acos(1.0 - ratio)
        let requiredSegmentCount = Int(ceil((Double.pi * 2.0) / angle))
        guard requiredSegmentCount <= maximumCircleSegmentCount else {
            throw SketchError.unsupportedEntity(
                "Circle curve requires more than \(maximumCircleSegmentCount) segments at the current modeling tolerance."
            )
        }
        let segmentCount = max(requiredSegmentCount, minimumCircleSegmentCount)
        let edgeLength = 2.0 * radius * sin(Double.pi / Double(segmentCount))
        guard edgeLength > tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        return segmentCount
    }

    private func arcSegmentCount(radius: Double, angleSpan: Double) throws -> Int {
        let fullCircleSegmentCount = try circleSegmentCount(radius: radius)
        let proportionalCount = Int(ceil(Double(fullCircleSegmentCount) * angleSpan / (Double.pi * 2.0)))
        return max(proportionalCount, 2)
    }

    private func normalizedAngleSpan(startAngle: Double, endAngle: Double) throws -> Double {
        guard startAngle.isFinite, endAngle.isFinite else {
            throw GeometryError.invalidCoordinate(endAngle)
        }
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= tolerance.angle {
            span += fullCircle
        }
        while span > fullCircle + tolerance.angle {
            span -= fullCircle
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

    private func isClose(_ lhs: Point2D, _ rhs: Point2D) -> Bool {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot() <= tolerance.distance
    }
}
