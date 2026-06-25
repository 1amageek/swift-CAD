import CADCore
import CADIR

struct EvaluatedCurveChainBuilder: Sendable {
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    func openChain(
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

    func openSegments(
        from curves: [EvaluatedCurve],
        operationName: String
    ) throws -> [EvaluatedCurvePathSegment] {
        try tolerance.validate()
        guard curves.isEmpty == false else {
            throw SketchError.unsupportedEntity("\(operationName) contains no curve entities.")
        }
        if curves.count == 1 {
            let curve = try validateSingleOpenCurve(curves[0], operationName: operationName)
            return [EvaluatedCurvePathSegment(curve: curve)]
        }

        try validateOpenSegments(curves, operationName: operationName)
        let endpoints = endpoints(for: curves)
        try validateEndpointDegrees(endpoints, operationName: operationName)
        let unmatchedEndpoints = endpoints.filter { matchingEndpointCount(for: $0, in: endpoints) == 0 }
        guard unmatchedEndpoints.count != 0 else {
            throw SketchError.unsupportedEntity(
                "\(operationName) closed curve chains require closed sweep topology support."
            )
        }
        guard unmatchedEndpoints.count == 2 else {
            throw SketchError.unsupportedEntity("\(operationName) requires connected open curve segments.")
        }

        let startEndpoint = unmatchedEndpoints[0]
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
                throw SketchError.unsupportedEntity("\(operationName) requires connected open curve segments.")
            }
            usedCurveIndexes.insert(candidate.curveIndex)
            segments.append(candidate.segment)
        }

        guard let finalPoint = endPoint(for: segments[segments.index(before: segments.endIndex)]),
              unmatchedEndpoints.contains(where: { endpoint in
                  endpoint.curveIndex != startEndpoint.curveIndex
                      && endpoint.point.isApproximatelyEqual(to: finalPoint, tolerance: tolerance.distance)
              }) else {
            throw SketchError.unsupportedEntity("\(operationName) requires connected open curve segments.")
        }

        for segment in segments {
            try segment.validate(tolerance: tolerance)
        }
        return segments
    }

    private func validateSingleOpenCurve(
        _ curve: EvaluatedCurve,
        operationName: String
    ) throws -> EvaluatedCurve {
        try curve.validate(tolerance: tolerance)
        guard curve.isClosed == false else {
            throw SketchError.unsupportedEntity("\(operationName) requires an open curve chain.")
        }
        guard let first = curve.points.first,
              let last = curve.points.last,
              first.isApproximatelyEqual(to: last, tolerance: tolerance.distance) == false else {
            throw SketchError.unsupportedEntity(
                "\(operationName) closed curve chains require closed sweep topology support."
            )
        }
        return curve
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
}

private struct ConnectionCandidate: Sendable {
    var curveIndex: Int
    var segment: EvaluatedCurvePathSegment
}
