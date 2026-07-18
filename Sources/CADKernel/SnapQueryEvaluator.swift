import Foundation
import CADCore
import CADIR
import CADModeling

public struct SnapQueryEvaluator: Sendable {
    private let tolerance: ModelingTolerance
    private let edgeQueryEvaluator: EdgeQueryEvaluator
    private let curveQueryEvaluator: CurveQueryEvaluator
    private let surfaceQueryEvaluator: SurfaceQueryEvaluator

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
        self.edgeQueryEvaluator = EdgeQueryEvaluator(tolerance: tolerance)
        self.curveQueryEvaluator = CurveQueryEvaluator(tolerance: tolerance)
        self.surfaceQueryEvaluator = SurfaceQueryEvaluator(tolerance: tolerance)
    }

    public func candidates(
        near point: Point3D,
        in document: EvaluatedDocument,
        options: SnapQueryOptions = SnapQueryOptions()
    ) throws -> SnapQueryResult {
        try point.validate()
        try options.validate(tolerance: tolerance)

        var candidates: [SnapQueryCandidate] = []
        var recordedTopology = Set<SnapTopologyKey>()
        for entry in document.subshapes.entries.sorted(by: { $0.key < $1.key }) {
            switch entry.value {
            case let .vertex(vertexID):
                guard options.accepts(.vertex),
                      recordedTopology.insert(.vertex(vertexID)).inserted,
                      let vertex = document.brep.vertices[vertexID] else {
                    continue
                }
                let distance = (point - vertex.point).length
                try appendCandidate(
                    SnapQueryCandidate(
                        kind: .vertex,
                        selection: .subshape(try document.stableSubshapeReference(for: entry.key)),
                        subshapeID: entry.key,
                        role: .topologyVertex,
                        point: vertex.point,
                        distance: distance
                    ),
                    to: &candidates,
                    options: options
                )
            case let .edge(edgeID):
                guard options.accepts(.edge),
                      recordedTopology.insert(.edge(edgeID)).inserted else {
                    continue
                }
                let edgeReference = EdgeReference(
                    subshape: try document.stableSubshapeReference(for: entry.key)
                )
                let projection = try edgeQueryEvaluator.closestPoint(to: point, on: edgeReference, in: document)
                try appendCandidate(
                    SnapQueryCandidate(
                        kind: .edge,
                        selection: .edge(.parameter(projection.parameterReference)),
                        subshapeID: entry.key,
                        role: .edgeProjection,
                        point: projection.projectedPoint,
                        distance: projection.distance,
                        tangent: projection.frame.tangent,
                        curvature: projection.frame.curvature
                    ),
                    to: &candidates,
                    options: options
                )
            case let .face(faceID):
                guard options.accepts(.face),
                      recordedTopology.insert(.face(faceID)).inserted else {
                    continue
                }
                let surfaceReference = SurfaceReference(
                    subshape: try document.stableSubshapeReference(for: entry.key)
                )
                let projection = try surfaceQueryEvaluator.closestPoint(to: point, on: surfaceReference, in: document)
                try appendCandidate(
                    SnapQueryCandidate(
                        kind: .face,
                        selection: .surface(.parameter(projection.parameterReference)),
                        subshapeID: entry.key,
                        role: .faceProjection,
                        point: projection.projectedPoint,
                        distance: projection.distance,
                        normal: projection.frame.normal
                    ),
                    to: &candidates,
                    options: options
                )
            case .body:
                continue
            }
        }
        if options.accepts(.curvePoint) {
            for reference in sortedCurveReferences(document.curves) {
                try appendCurvePointCandidates(
                    near: point,
                    on: reference,
                    in: document,
                    to: &candidates,
                    options: options
                )
            }
        }
        if options.accepts(.curve) {
            for reference in sortedCurveReferences(document.curves) {
                let projection = try curveQueryEvaluator.closestPoint(to: point, on: reference, in: document)
                try appendCandidate(
                    SnapQueryCandidate(
                        kind: .curve,
                        selection: .curve(.parameter(projection.parameterReference)),
                        role: .curveProjection,
                        point: projection.projectedPoint,
                        distance: projection.distance,
                        tangent: projection.queryPoint.tangent,
                        curvature: projection.queryPoint.curvature
                    ),
                    to: &candidates,
                    options: options
                )
            }
        }

        candidates.sort { lhs, rhs in
            if abs(lhs.distance - rhs.distance) > tolerance.distance {
                return lhs.distance < rhs.distance
            }
            if lhs.kind != rhs.kind {
                return snapPriority(for: lhs.kind, options: options) < snapPriority(for: rhs.kind, options: options)
            }
            return candidateKey(lhs) < candidateKey(rhs)
        }

        if candidates.count > options.maximumCandidateCount {
            candidates = Array(candidates.prefix(options.maximumCandidateCount))
        }
        return SnapQueryResult(sourcePoint: point, candidates: candidates)
    }

    private func appendCurvePointCandidates(
        near point: Point3D,
        on reference: CurveOutputReference,
        in document: EvaluatedDocument,
        to candidates: inout [SnapQueryCandidate],
        options: SnapQueryOptions
    ) throws {
        let curve = try curveQueryEvaluator.resolve(reference, in: document)
        guard curve.isClosed == false else {
            return
        }
        let parameters = try curveEndpointParameters(for: curve)
        let start = try curveQueryEvaluator.point(
            at: CurveParameterReference(curve: reference, parameter: parameters.start),
            in: document
        )
        let midpoint = try curveQueryEvaluator.midpoint(of: reference, in: document)
        let end = try curveQueryEvaluator.point(
            at: CurveParameterReference(curve: reference, parameter: parameters.end),
            in: document
        )
        try appendCurvePointCandidate(start, role: .curveStart, near: point, to: &candidates, options: options)
        if midpoint.point.isApproximatelyEqual(to: start.point, tolerance: tolerance.distance) == false &&
            midpoint.point.isApproximatelyEqual(to: end.point, tolerance: tolerance.distance) == false {
            try appendCurvePointCandidate(midpoint, role: .curveMidpoint, near: point, to: &candidates, options: options)
        }
        if end.point.isApproximatelyEqual(to: start.point, tolerance: tolerance.distance) == false {
            try appendCurvePointCandidate(end, role: .curveEnd, near: point, to: &candidates, options: options)
        }
    }

    private func appendCurvePointCandidate(
        _ queryPoint: CurveQueryPoint,
        role: SnapCandidateRole,
        near point: Point3D,
        to candidates: inout [SnapQueryCandidate],
        options: SnapQueryOptions
    ) throws {
        try appendCandidate(
            SnapQueryCandidate(
                kind: .curvePoint,
                selection: .curve(.parameter(queryPoint.reference)),
                role: role,
                point: queryPoint.point,
                distance: (point - queryPoint.point).length,
                tangent: queryPoint.tangent,
                curvature: queryPoint.curvature
            ),
            to: &candidates,
            options: options
        )
    }

    private func appendCandidate(
        _ candidate: SnapQueryCandidate,
        to candidates: inout [SnapQueryCandidate],
        options: SnapQueryOptions
    ) throws {
        guard candidate.distance.isFinite else {
            throw GeometryError.invalidDistance(candidate.distance)
        }
        guard options.accepts(candidate.kind) else {
            return
        }
        if let maximumDistance = options.maximumDistance,
           candidate.distance > maximumDistance + tolerance.distance {
            return
        }
        candidates.append(candidate)
    }

    private func sortedCurveReferences(
        _ curvesByFeature: [FeatureID: [EvaluatedCurve]]
    ) -> [CurveOutputReference] {
        curvesByFeature
            .flatMap { featureID, curves in
                curves.indices.map { CurveOutputReference(featureID: featureID, curveIndex: $0) }
            }
            .sorted { lhs, rhs in
                let leftFeatureID = lhs.featureID.rawValue.uuidString
                let rightFeatureID = rhs.featureID.rawValue.uuidString
                if leftFeatureID != rightFeatureID {
                    return leftFeatureID < rightFeatureID
                }
                return lhs.curveIndex < rhs.curveIndex
            }
    }

    private func curveEndpointParameters(for curve: EvaluatedCurve) throws -> (start: Double, end: Double) {
        switch curve.parameterDomain {
        case let .closed(lower, upper):
            return (lower, upper)
        case let .periodic(period):
            return (0.0, period)
        case .unbounded:
            guard let first = curve.points.first,
                  let last = curve.points.last else {
                throw FeatureEvaluationError.emptyResult("Curve output contains no evaluated endpoints.")
            }
            guard case let .line(line) = curve.exactCurve else {
                return (0.0, 1.0)
            }
            return (
                (first - line.origin).dot(line.direction),
                (last - line.origin).dot(line.direction)
            )
        }
    }

    private func snapPriority(for kind: SnapCandidateKind, options: SnapQueryOptions) -> Int {
        options.priority(for: kind) ?? Int.max
    }

    private func candidateKey(_ candidate: SnapQueryCandidate) -> String {
        if let subshapeID = candidate.subshapeID {
            return "subshape:\(subshapeID.featureID):\(subshapeID.role):\(subshapeID.ordinal)"
        }
        return [
            "derived",
            candidate.kind.rawValue,
            candidate.role?.rawValue ?? "",
            String(candidate.point.x),
            String(candidate.point.y),
            String(candidate.point.z),
        ].joined(separator: ":")
    }
}

private enum SnapTopologyKey: Hashable {
    case vertex(VertexID)
    case edge(EdgeID)
    case face(FaceID)
}
