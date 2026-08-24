import CADCore
import CADGeometry
import CADIR

package struct EvaluatedCurveChainBuilder: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func openChain(
        from curves: [EvaluatedCurve],
        operationName: String
    ) throws -> EvaluatedCurve {
        let segments = try openSegments(from: curves, operationName: operationName)
        var chainPoints: [Point3D] = []
        for segment in segments {
            let points = orientedPoints(
                for: segment.curve,
                isReversed: segment.isReversed
            )
            if chainPoints.isEmpty {
                chainPoints = points
            } else {
                chainPoints.append(contentsOf: points.dropFirst())
            }
        }

        let chain = EvaluatedCurve(
            sourceFeatureID: segments[0].curve.sourceFeatureID,
            source: .generatedFeature,
            kind: .spline,
            points: chainPoints,
            isClosed: false
        )
        try chain.validate(tolerance: tolerance)
        return chain
    }

    package func openSegments(
        from curves: [EvaluatedCurve],
        operationName: String,
        preferredStartPlane: Plane3D? = nil
    ) throws -> [EvaluatedCurvePathSegment] {
        let chain = try connectedSegments(
            from: curves,
            operationName: operationName,
            preferredStartPlane: preferredStartPlane
        )
        guard chain.isClosed == false else {
            throw SketchError.unsupportedEntity(
                "\(operationName) requires an open curve chain."
            )
        }
        return chain.segments
    }

    package func connectedSegments(
        from curves: [EvaluatedCurve],
        operationName: String,
        preferredStartPlane: Plane3D? = nil
    ) throws -> (segments: [EvaluatedCurvePathSegment], isClosed: Bool) {
        try tolerance.validate()
        guard curves.isEmpty == false else {
            throw SketchError.unsupportedEntity("\(operationName) contains no curve entities.")
        }
        if curves.count == 1 {
            let curve = curves[0]
            try curve.validate(tolerance: tolerance)
            guard let first = curve.points.first,
                  let last = curve.points.last else {
                throw SketchError.unsupportedEntity("\(operationName) contains no curve points.")
            }
            return (
                [EvaluatedCurvePathSegment(curve: curve)],
                curve.isClosed
                    || first.isApproximatelyEqual(to: last, tolerance: tolerance.distance)
            )
        }

        try validateOpenSegments(curves, operationName: operationName)
        let endpoints = endpoints(for: curves)
        try validateEndpointDegrees(endpoints, operationName: operationName)
        let unmatchedEndpoints = endpoints.filter { matchingEndpointCount(for: $0, in: endpoints) == 0 }
        let isClosed = unmatchedEndpoints.isEmpty
        guard isClosed || unmatchedEndpoints.count == 2 else {
            throw SketchError.disconnectedCurveChain(operation: operationName)
        }

        let startEndpoint = selectedStartEndpoint(
            from: isClosed ? endpoints : unmatchedEndpoints,
            preferredStartPlane: preferredStartPlane
        )
        var usedCurveIndexes: Set<Int> = [startEndpoint.curveIndex]
        var segments = [
            EvaluatedCurvePathSegment(
                curve: curves[startEndpoint.curveIndex],
                isReversed: startEndpoint.end == .end
            )
        ]

        while usedCurveIndexes.count < curves.count {
            guard let currentEnd = endPoint(for: segments[segments.index(before: segments.endIndex)]) else {
                throw SketchError.unsupportedEntity("\(operationName) requires connected open curve segments.")
            }
            let candidates = connectionCandidates(
                from: curves,
                currentEnd: currentEnd,
                usedCurveIndexes: usedCurveIndexes
            )
            guard candidates.count <= 1 else {
                throw SketchError.unsupportedEntity("\(operationName) contains a branched curve junction.")
            }
            guard let candidate = candidates.first else {
                throw SketchError.disconnectedCurveChain(operation: operationName)
            }
            usedCurveIndexes.insert(candidate.curveIndex)
            segments.append(candidate.segment)
        }

        guard let finalPoint = endPoint(for: segments[segments.index(before: segments.endIndex)]) else {
            throw SketchError.unsupportedEntity(
                "\(operationName) requires one connected, non-branching curve chain."
            )
        }
        if isClosed {
            guard startEndpoint.point.isApproximatelyEqual(
                to: finalPoint,
                tolerance: tolerance.distance
            ) else {
                throw SketchError.unsupportedEntity(
                    "\(operationName) closed curve chain does not close at its selected start."
                )
            }
        } else {
            guard unmatchedEndpoints.contains(where: { endpoint in
                endpoint.curveIndex != startEndpoint.curveIndex
                    && endpoint.point.isApproximatelyEqual(
                        to: finalPoint,
                        tolerance: tolerance.distance
                    )
            }) else {
                throw SketchError.disconnectedCurveChain(operation: operationName)
            }
        }

        for segment in segments {
            try segment.validate(tolerance: tolerance)
        }
        return (segments, isClosed)
    }

    private func selectedStartEndpoint(
        from endpoints: [Endpoint],
        preferredStartPlane: Plane3D?
    ) -> Endpoint {
        endpoints.min { first, second in
            if let preferredStartPlane {
                let firstDistance = abs(
                    (first.point - preferredStartPlane.origin).dot(preferredStartPlane.normal)
                )
                let secondDistance = abs(
                    (second.point - preferredStartPlane.origin).dot(preferredStartPlane.normal)
                )
                if abs(firstDistance - secondDistance) > tolerance.distance {
                    return firstDistance < secondDistance
                }
            }
            if first.point.x != second.point.x {
                return first.point.x < second.point.x
            }
            if first.point.y != second.point.y {
                return first.point.y < second.point.y
            }
            if first.point.z != second.point.z {
                return first.point.z < second.point.z
            }
            if first.curveIndex != second.curveIndex {
                return first.curveIndex < second.curveIndex
            }
            return first.end.sortOrder < second.end.sortOrder
        } ?? endpoints[0]
    }

    private func validateOpenSegments(
        _ curves: [EvaluatedCurve],
        operationName: String
    ) throws {
        for curve in curves {
            try curve.validate(tolerance: tolerance)
            guard curve.isClosed == false else {
                throw SketchError.unsupportedEntity("\(operationName) requires open curve segments.")
            }
            guard let first = curve.points.first,
                  let last = curve.points.last,
                  first.isApproximatelyEqual(to: last, tolerance: tolerance.distance) == false else {
                throw SketchError.unsupportedEntity(
                    "\(operationName) closed curve chains require closed sweep topology support."
                )
            }
        }
    }

    private func endpoints(for curves: [EvaluatedCurve]) -> [Endpoint] {
        curves.enumerated().flatMap { curveIndex, curve in
            [
                Endpoint(curveIndex: curveIndex, end: .start, point: curve.points[0]),
                Endpoint(
                    curveIndex: curveIndex,
                    end: .end,
                    point: curve.points[curve.points.index(before: curve.points.endIndex)]
                ),
            ]
        }
    }

    private func validateEndpointDegrees(
        _ endpoints: [Endpoint],
        operationName: String
    ) throws {
        for endpoint in endpoints {
            guard matchingEndpointCount(for: endpoint, in: endpoints) <= 1 else {
                throw SketchError.unsupportedEntity("\(operationName) contains a branched curve junction.")
            }
        }
    }

    private func matchingEndpointCount(
        for endpoint: Endpoint,
        in endpoints: [Endpoint]
    ) -> Int {
        endpoints.filter { candidate in
            candidate.curveIndex != endpoint.curveIndex
                && candidate.point.isApproximatelyEqual(to: endpoint.point, tolerance: tolerance.distance)
        }.count
    }

    private func connectionCandidates(
        from curves: [EvaluatedCurve],
        currentEnd: Point3D,
        usedCurveIndexes: Set<Int>
    ) -> [ConnectionCandidate] {
        curves.enumerated().flatMap { curveIndex, curve -> [ConnectionCandidate] in
            guard usedCurveIndexes.contains(curveIndex) == false,
                  let first = curve.points.first,
                  let last = curve.points.last else {
                return []
            }
            if first.isApproximatelyEqual(to: currentEnd, tolerance: tolerance.distance) {
                return [
                    ConnectionCandidate(
                        curveIndex: curveIndex,
                        segment: EvaluatedCurvePathSegment(curve: curve)
                    )
                ]
            }
            if last.isApproximatelyEqual(to: currentEnd, tolerance: tolerance.distance) {
                return [
                    ConnectionCandidate(
                        curveIndex: curveIndex,
                        segment: EvaluatedCurvePathSegment(curve: curve, isReversed: true)
                    )
                ]
            }
            return []
        }
    }

    private func orientedPoints(
        for curve: EvaluatedCurve,
        isReversed: Bool
    ) -> [Point3D] {
        if isReversed {
            return Array(curve.points.reversed())
        }
        return curve.points
    }

    private func endPoint(for segment: EvaluatedCurvePathSegment) -> Point3D? {
        if segment.isReversed {
            return segment.curve.points.first
        }
        return segment.curve.points.last
    }
}

private struct Endpoint: Sendable, Hashable {
    var curveIndex: Int
    var end: EndpointEnd
    var point: Point3D
}

private enum EndpointEnd: Sendable, Hashable {
    case start
    case end

    var sortOrder: Int {
        switch self {
        case .start:
            return 0
        case .end:
            return 1
        }
    }
}

private struct ConnectionCandidate: Sendable {
    var curveIndex: Int
    var segment: EvaluatedCurvePathSegment
}
