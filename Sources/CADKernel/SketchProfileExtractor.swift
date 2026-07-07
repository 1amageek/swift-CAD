import Foundation
import CADCore
import CADIR

public struct SketchProfileExtractor: SketchProfileExtracting {
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

    public func extractProfiles(
        from sketch: Sketch,
        sourceFeatureID: FeatureID,
        parameters: ResolvedParameterTable
    ) throws -> [Profile] {
        try tolerance.validate()
        var lines: [ResolvedSketchLine] = []
        var arcs: [ResolvedSketchArc] = []
        var splines: [ResolvedSketchSpline] = []
        var circles: [ResolvedSketchCircle] = []
        for (entityID, entity) in sketch.entities.sorted(by: { $0.key.description < $1.key.description }) {
            switch entity {
            case let .line(line):
                lines.append(ResolvedSketchLine(
                    id: entityID,
                    start: try resolve(line.start, parameters: parameters),
                    end: try resolve(line.end, parameters: parameters)
                ))
            case .point:
                throw SketchError.unsupportedProfile("Point entities are not supported in profile extraction.")
            case let .spline(spline):
                splines.append(ResolvedSketchSpline(
                    id: entityID,
                    controlPoints: try spline.controlPoints.map { point in
                        try resolve(point, parameters: parameters)
                    },
                    isClosed: spline.isClosed
                ))
            case let .arc(arc):
                arcs.append(ResolvedSketchArc(
                    id: entityID,
                    center: try resolve(arc.center, parameters: parameters),
                    radius: try resolveLength(
                        arc.radius,
                        operation: "sketch.arc.radius",
                        parameters: parameters
                    ),
                    startAngle: try resolveAngle(
                        arc.startAngle,
                        operation: "sketch.arc.startAngle",
                        parameters: parameters
                    ),
                    endAngle: try resolveAngle(
                        arc.endAngle,
                        operation: "sketch.arc.endAngle",
                        parameters: parameters
                    )
                ))
            case let .circle(circle):
                circles.append(ResolvedSketchCircle(
                    id: entityID,
                    center: try resolve(circle.center, parameters: parameters),
                    radius: try resolveLength(
                        circle.radius,
                        operation: "sketch.circle.radius",
                        parameters: parameters
                    )
                ))
            }
        }

        if (!lines.isEmpty || !arcs.isEmpty || !splines.isEmpty), !circles.isEmpty {
            throw SketchError.unsupportedProfile("Mixed curve and circle profiles are not supported.")
        }

        if circles.count > 1 {
            throw SketchError.unsupportedProfile("Multiple circle profiles are not supported.")
        }

        if let circle = circles.first {
            let orderedPoints = try normalizedCircleSampleLoop(from: try polygonizedCircle(circle))
            let vertices = try orderedPoints.map { point in
                try mapTo3D(point, on: sketch.plane)
            }
            return [Profile(
                sourceFeatureID: sourceFeatureID,
                plane: sketch.plane,
                vertices: vertices,
                boundarySegments: [
                    try circularArcBoundarySegment(
                        center: circle.center,
                        radius: circle.radius,
                        start: Point2D(x: circle.center.x + circle.radius, y: circle.center.y),
                        end: Point2D(x: circle.center.x + circle.radius, y: circle.center.y),
                        sweepAngle: Double.pi * 2.0,
                        on: sketch.plane
                    )
                ]
            )]
        }

        guard !lines.isEmpty || !arcs.isEmpty || !splines.isEmpty else {
            throw SketchError.emptyProfile
        }

        let segments = try resolvedProfileSegments(lines: lines, arcs: arcs, splines: splines)
        let orderedLoops = try orderClosedLoops(segments).map { segments in
            try normalizedSupportedSegments(from: segments)
        }.sorted(by: areLoopsInCanonicalOrder)
        let orderedLoopPoints = try orderedLoops.map { try loopPoints(from: $0) }
        try validateIndependentLoops(orderedLoopPoints)
        return try orderedLoops.map { orderedSegments in
            let orderedPoints = try loopPoints(from: orderedSegments)
            let vertices = try orderedPoints.map { point in
                try mapTo3D(point, on: sketch.plane)
            }
            let profileBoundarySegments = try orderedSegments.flatMap { segment in
                try boundarySegments(from: segment, on: sketch.plane)
            }
            return Profile(
                sourceFeatureID: sourceFeatureID,
                plane: sketch.plane,
                vertices: vertices,
                boundarySegments: profileBoundarySegments
            )
        }
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

    private func polygonizedCircle(_ circle: ResolvedSketchCircle) throws -> [Point2D] {
        let segmentCount = try circleSegmentCount(radius: circle.radius)
        return (0..<segmentCount).map { index in
            let angle = Double(index) / Double(segmentCount) * Double.pi * 2.0
            return Point2D(
                x: circle.center.x + circle.radius * cos(angle),
                y: circle.center.y + circle.radius * sin(angle)
            )
        }
    }

    private func circleSegmentCount(radius: Double) throws -> Int {
        try circularSamplingPolicy.boundedFullCircleSegmentCount(
            radius: radius,
            tolerance: tolerance
        )
    }

    private func resolvedProfileSegments(
        lines: [ResolvedSketchLine],
        arcs: [ResolvedSketchArc],
        splines: [ResolvedSketchSpline]
    ) throws -> [ResolvedProfileSegment] {
        var segments = lines.map { line in
            ResolvedProfileSegment(
                id: line.id,
                kind: .line,
                points: [line.start, line.end]
            )
        }
        for arc in arcs {
            segments.append(try polygonizedArcSegment(arc))
        }
        for spline in splines {
            segments.append(try polygonizedSplineSegment(spline))
        }
        return segments
    }

    private func polygonizedSplineSegment(_ spline: ResolvedSketchSpline) throws -> ResolvedProfileSegment {
        let points = try splineTessellator.points(for: spline.controlPoints)
        if spline.isClosed {
            guard let first = points.first,
                  let last = points.last,
                  isClose(first, last) else {
                throw SketchError.openProfile
            }
        }
        guard points.count >= 2 else {
            throw SketchError.degenerateProfile
        }
        return ResolvedProfileSegment(
            id: spline.id,
            kind: .spline,
            points: points
        )
    }

    private func polygonizedArcSegment(_ arc: ResolvedSketchArc) throws -> ResolvedProfileSegment {
        let span = try normalizedAngleSpan(startAngle: arc.startAngle, endAngle: arc.endAngle)
        let segmentCount = try arcSegmentCount(radius: arc.radius, angleSpan: span)
        let points = (0 ... segmentCount).map { index in
            let ratio = Double(index) / Double(segmentCount)
            let angle = arc.startAngle + span * ratio
            return Point2D(
                x: arc.center.x + arc.radius * cos(angle),
                y: arc.center.y + arc.radius * sin(angle)
            )
        }
        return ResolvedProfileSegment(
            id: arc.id,
            kind: .arc(center: arc.center, radius: arc.radius, sweepAngle: span),
            points: points
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

    private func arcSegmentCount(radius: Double, angleSpan: Double) throws -> Int {
        try circularSamplingPolicy.boundedArcSegmentCount(
            radius: radius,
            angleSpan: angleSpan,
            tolerance: tolerance
        )
    }

    private func orderClosedLoops(_ segments: [ResolvedProfileSegment]) throws -> [[ResolvedProfileSegment]] {
        var unused = segments
        var loops: [[ResolvedProfileSegment]] = []
        while !unused.isEmpty {
            let first = unused.removeFirst()
            var ordered = [first]
            var current = first.end

            while !isClose(first.start, current) {
                guard let matchIndex = unused.firstIndex(where: {
                    isClose($0.start, current) || isClose($0.end, current)
                }) else {
                    throw SketchError.openProfile
                }

                let match = unused.remove(at: matchIndex)
                let segment = isClose(match.start, current)
                    ? match
                    : match.reversed()
                current = segment.end
                ordered.append(segment)
            }

            let points = try loopPoints(from: ordered)
            guard points.count >= 3 else {
                throw SketchError.openProfile
            }
            loops.append(ordered)
        }
        guard loops.isEmpty == false else {
            throw SketchError.emptyProfile
        }
        return loops
    }

    private func loopPoints(from segments: [ResolvedProfileSegment]) throws -> [Point2D] {
        guard let first = segments.first else {
            throw SketchError.emptyProfile
        }
        var points = first.points
        for segment in segments.dropFirst() {
            points.append(contentsOf: segment.points.dropFirst())
        }
        if let start = points.first, let end = points.last, isClose(start, end) {
            points.removeLast()
        }
        return points
    }

    private func normalizedSupportedLoop(from points: [Point2D]) throws -> [Point2D] {
        let area = signedArea(of: points)
        let areaTolerance = tolerance.distance * tolerance.distance
        guard abs(area) > areaTolerance else {
            throw SketchError.degenerateProfile
        }

        let normalized = area > 0.0 ? points : Array(points.reversed())
        try validateSimpleLoop(normalized)
        return normalized
    }

    private func normalizedCircleSampleLoop(from points: [Point2D]) throws -> [Point2D] {
        guard points.count >= 3 else {
            throw SketchError.degenerateProfile
        }
        let area = signedArea(of: points)
        let areaTolerance = tolerance.distance * tolerance.distance
        guard abs(area) > areaTolerance else {
            throw SketchError.degenerateProfile
        }
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            guard isClose(points[index], next) == false else {
                throw SketchError.degenerateProfile
            }
        }
        return area > 0.0 ? points : Array(points.reversed())
    }

    private func normalizedSupportedSegments(
        from segments: [ResolvedProfileSegment]
    ) throws -> [ResolvedProfileSegment] {
        let points = try loopPoints(from: segments)
        let area = signedArea(of: points)
        let areaTolerance = tolerance.distance * tolerance.distance
        guard abs(area) > areaTolerance else {
            throw SketchError.degenerateProfile
        }

        let normalized = area > 0.0
            ? segments
            : segments.reversed().map { $0.reversed() }
        try validateSimpleLoop(try loopPoints(from: normalized))
        return canonicalizedSegments(normalized)
    }

    private func canonicalizedSegments(_ segments: [ResolvedProfileSegment]) -> [ResolvedProfileSegment] {
        guard let startIndex = segments.indices.min(by: {
            isPointInCanonicalOrder(segments[$0].start, before: segments[$1].start)
        }) else {
            return segments
        }
        return Array(segments[startIndex...]) + Array(segments[..<startIndex])
    }

    private func areLoopsInCanonicalOrder(
        _ lhs: [ResolvedProfileSegment],
        before rhs: [ResolvedProfileSegment]
    ) -> Bool {
        guard let lhsStart = lhs.first?.start else {
            return false
        }
        guard let rhsStart = rhs.first?.start else {
            return true
        }
        return isPointInCanonicalOrder(lhsStart, before: rhsStart)
    }

    private func isPointInCanonicalOrder(_ lhs: Point2D, before rhs: Point2D) -> Bool {
        if abs(lhs.x - rhs.x) > tolerance.distance {
            return lhs.x < rhs.x
        }
        if abs(lhs.y - rhs.y) > tolerance.distance {
            return lhs.y < rhs.y
        }
        return false
    }

    private func validateSimpleLoop(_ points: [Point2D]) throws {
        guard points.count >= 3 else {
            throw SketchError.degenerateProfile
        }
        let areaTolerance = tolerance.distance * tolerance.distance
        let edgeTolerance = tolerance.distance * tolerance.distance
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let second = Point2D(x: next.x - current.x, y: next.y - current.y)
            let edgeLengthSquared = second.x * second.x + second.y * second.y
            if edgeLengthSquared <= edgeTolerance {
                throw SketchError.degenerateProfile
            }
            let previousLengthSquared = (current.x - previous.x) * (current.x - previous.x)
                + (current.y - previous.y) * (current.y - previous.y)
            if previousLengthSquared <= edgeTolerance {
                throw SketchError.degenerateProfile
            }
        }

        for leftIndex in points.indices {
            let leftStart = points[leftIndex]
            let leftEnd = points[(leftIndex + 1) % points.count]
            for rightIndex in points.indices where rightIndex > leftIndex {
                let isAdjacent = rightIndex == leftIndex + 1
                    || (leftIndex == 0 && rightIndex == points.count - 1)
                guard isAdjacent == false else {
                    continue
                }
                let rightStart = points[rightIndex]
                let rightEnd = points[(rightIndex + 1) % points.count]
                if segmentsIntersectOrTouch(leftStart, leftEnd, rightStart, rightEnd) {
                    throw SketchError.unsupportedProfile("Self-intersecting profiles are not supported.")
                }
            }
        }
        guard abs(signedArea(of: points)) > areaTolerance else {
            throw SketchError.degenerateProfile
        }
    }

    private func validateIndependentLoops(_ loops: [[Point2D]]) throws {
        for leftIndex in loops.indices {
            let left = loops[leftIndex]
            for rightIndex in loops.indices where rightIndex > leftIndex {
                let right = loops[rightIndex]
                try validateLoopsDoNotIntersect(left, right)
                if containsPoint(right[0], in: left) || containsPoint(left[0], in: right) {
                    throw SketchError.unsupportedProfile("Nested profile loops require hole-aware profile extraction.")
                }
            }
        }
    }

    private func validateLoopsDoNotIntersect(
        _ left: [Point2D],
        _ right: [Point2D]
    ) throws {
        for leftIndex in left.indices {
            let leftStart = left[leftIndex]
            let leftEnd = left[(leftIndex + 1) % left.count]
            for rightIndex in right.indices {
                let rightStart = right[rightIndex]
                let rightEnd = right[(rightIndex + 1) % right.count]
                if segmentsIntersectOrTouch(leftStart, leftEnd, rightStart, rightEnd) {
                    throw SketchError.unsupportedProfile("Intersecting or touching profile loops require region-union extraction.")
                }
            }
        }
    }

    private func containsPoint(_ point: Point2D, in polygon: [Point2D]) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        var inside = false
        var previousIndex = polygon.count - 1
        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            if abs(orientation(previous, current, point)) <= tolerance.distance * tolerance.distance,
               isPoint(point, onSegmentFrom: previous, to: current) {
                return true
            }
            let crosses = (current.y > point.y) != (previous.y > point.y)
            if crosses {
                let xIntersection = (previous.x - current.x) * (point.y - current.y)
                    / (previous.y - current.y) + current.x
                if point.x < xIntersection {
                    inside.toggle()
                }
            }
            previousIndex = currentIndex
        }
        return inside
    }

    private func segmentsIntersectOrTouch(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D
    ) -> Bool {
        let areaTolerance = tolerance.distance * tolerance.distance
        let firstSecondStart = orientation(firstStart, firstEnd, secondStart)
        let firstSecondEnd = orientation(firstStart, firstEnd, secondEnd)
        let secondFirstStart = orientation(secondStart, secondEnd, firstStart)
        let secondFirstEnd = orientation(secondStart, secondEnd, firstEnd)

        if abs(firstSecondStart) <= areaTolerance,
           isPoint(secondStart, onSegmentFrom: firstStart, to: firstEnd) {
            return true
        }
        if abs(firstSecondEnd) <= areaTolerance,
           isPoint(secondEnd, onSegmentFrom: firstStart, to: firstEnd) {
            return true
        }
        if abs(secondFirstStart) <= areaTolerance,
           isPoint(firstStart, onSegmentFrom: secondStart, to: secondEnd) {
            return true
        }
        if abs(secondFirstEnd) <= areaTolerance,
           isPoint(firstEnd, onSegmentFrom: secondStart, to: secondEnd) {
            return true
        }

        return valuesHaveOppositeSigns(firstSecondStart, firstSecondEnd, tolerance: areaTolerance)
            && valuesHaveOppositeSigns(secondFirstStart, secondFirstEnd, tolerance: areaTolerance)
    }

    private func valuesHaveOppositeSigns(
        _ left: Double,
        _ right: Double,
        tolerance: Double
    ) -> Bool {
        (left > tolerance && right < -tolerance) ||
            (left < -tolerance && right > tolerance)
    }

    private func orientation(
        _ start: Point2D,
        _ end: Point2D,
        _ point: Point2D
    ) -> Double {
        (end.x - start.x) * (point.y - start.y)
            - (end.y - start.y) * (point.x - start.x)
    }

    private func isPoint(
        _ point: Point2D,
        onSegmentFrom start: Point2D,
        to end: Point2D
    ) -> Bool {
        point.x >= min(start.x, end.x) - tolerance.distance
            && point.x <= max(start.x, end.x) + tolerance.distance
            && point.y >= min(start.y, end.y) - tolerance.distance
            && point.y <= max(start.y, end.y) + tolerance.distance
    }

    private func signedArea(of points: [Point2D]) -> Double {
        guard let origin = points.first else {
            return 0.0
        }
        var twiceArea = 0.0
        for index in points.indices {
            let current = Point2D(
                x: points[index].x - origin.x,
                y: points[index].y - origin.y
            )
            let nextPoint = points[(index + 1) % points.count]
            let next = Point2D(
                x: nextPoint.x - origin.x,
                y: nextPoint.y - origin.y
            )
            twiceArea += current.x * next.y - next.x * current.y
        }
        return twiceArea / 2.0
    }

    private func isClose(_ lhs: Point2D, _ rhs: Point2D) -> Bool {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot() <= tolerance.distance
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

    private func normal(for plane: SketchPlane) throws -> Vector3D {
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

    private func boundarySegments(
        from segment: ResolvedProfileSegment,
        on plane: SketchPlane
    ) throws -> [ProfileBoundarySegment] {
        switch segment.kind {
        case .line:
            return [.line(ProfileLineSegment(
                start: try mapTo3D(segment.start, on: plane),
                end: try mapTo3D(segment.end, on: plane)
            ))]
        case let .arc(center, radius, sweepAngle):
            return [try circularArcBoundarySegment(
                center: center,
                radius: radius,
                start: segment.start,
                end: segment.end,
                sweepAngle: sweepAngle,
                on: plane
            )]
        case .spline:
            return try lineBoundarySegments(from: segment.points, on: plane)
        }
    }

    private func lineBoundarySegments(
        from points: [Point2D],
        on plane: SketchPlane
    ) throws -> [ProfileBoundarySegment] {
        guard points.count >= 2 else {
            throw SketchError.degenerateProfile
        }
        return try (0..<(points.count - 1)).map { index in
            .line(ProfileLineSegment(
                start: try mapTo3D(points[index], on: plane),
                end: try mapTo3D(points[index + 1], on: plane)
            ))
        }
    }

    private func circularArcBoundarySegment(
        center: Point2D,
        radius: Double,
        start: Point2D,
        end: Point2D,
        sweepAngle: Double,
        on plane: SketchPlane
    ) throws -> ProfileBoundarySegment {
        .circularArc(ProfileCircularArcSegment(
            center: try mapTo3D(center, on: plane),
            normal: try normal(for: plane),
            radius: radius,
            start: try mapTo3D(start, on: plane),
            end: try mapTo3D(end, on: plane),
            sweepAngle: sweepAngle
        ))
    }
}

private struct ResolvedSketchLine {
    var id: SketchEntityID
    var start: Point2D
    var end: Point2D
}

private struct ResolvedSketchCircle {
    var id: SketchEntityID
    var center: Point2D
    var radius: Double
}

private struct ResolvedSketchArc {
    var id: SketchEntityID
    var center: Point2D
    var radius: Double
    var startAngle: Double
    var endAngle: Double
}

private struct ResolvedSketchSpline {
    var id: SketchEntityID
    var controlPoints: [Point2D]
    var isClosed: Bool
}

private struct ResolvedProfileSegment {
    var id: SketchEntityID
    var kind: ResolvedProfileSegmentKind
    var points: [Point2D]

    var start: Point2D {
        points[0]
    }

    var end: Point2D {
        points[points.count - 1]
    }

    func reversed() -> ResolvedProfileSegment {
        ResolvedProfileSegment(
            id: id,
            kind: kind.reversed(),
            points: Array(points.reversed())
        )
    }
}

private enum ResolvedProfileSegmentKind {
    case line
    case arc(center: Point2D, radius: Double, sweepAngle: Double)
    case spline

    func reversed() -> ResolvedProfileSegmentKind {
        switch self {
        case .line:
            return .line
        case let .arc(center, radius, sweepAngle):
            return .arc(center: center, radius: radius, sweepAngle: -sweepAngle)
        case .spline:
            return .spline
        }
    }
}
