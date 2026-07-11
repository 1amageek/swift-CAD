import Foundation
import CADCore
import CADIR

public struct SnapQueryEvaluator: Sendable {
    private let tolerance: ModelingTolerance
    private let edgeQueryEvaluator: EdgeQueryEvaluator
    private let curveQueryEvaluator: CurveQueryEvaluator
    private let surfaceQueryEvaluator: SurfaceQueryEvaluator

    public init(tolerance: ModelingTolerance = .standard) {
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
        for entry in sortedGeneratedNames(document.generatedNames) {
            switch entry.reference {
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
                        selection: .topology(entry.name),
                        persistentName: entry.name,
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
                let edgeReference = EdgeReference(edgeName: entry.name)
                let projection = try edgeQueryEvaluator.closestPoint(to: point, on: edgeReference, in: document)
                try appendCandidate(
                    SnapQueryCandidate(
                        kind: .edge,
                        selection: .edge(.parameter(projection.parameterReference)),
                        persistentName: entry.name,
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
                let surfaceReference = SurfaceReference(faceName: entry.name)
                let projection = try surfaceQueryEvaluator.closestPoint(to: point, on: surfaceReference, in: document)
                try appendCandidate(
                    SnapQueryCandidate(
                        kind: .face,
                        selection: .surface(.parameter(projection.parameterReference)),
                        persistentName: entry.name,
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
                        persistentName: persistentName(for: reference),
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
            return persistentNameKey(lhs.persistentName) < persistentNameKey(rhs.persistentName)
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
                persistentName: persistentName(for: queryPoint.reference.curve, role: role),
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

    private func sortedGeneratedNames(
        _ generatedNames: PersistentMap<PersistentName, TopologyReference>
    ) -> [(name: PersistentName, reference: TopologyReference)] {
        generatedNames
            .map { (name: $0.key, reference: $0.value) }
            .sorted { lhs, rhs in
                persistentNameKey(lhs.name) < persistentNameKey(rhs.name)
            }
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

    private func persistentName(for reference: CurveOutputReference) -> PersistentName {
        PersistentName(components: [
            .feature(reference.featureID),
            .generated("curve"),
            .index(reference.curveIndex),
        ])
    }

    private func persistentName(for reference: CurveOutputReference, role: SnapCandidateRole) -> PersistentName {
        PersistentName(components: [
            .feature(reference.featureID),
            .generated("curvePoint"),
            .index(reference.curveIndex),
            .subshape(role.rawValue),
        ])
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

    private func persistentNameKey(_ name: PersistentName) -> String {
        name.components.map(componentKey).joined(separator: "/")
    }

    private func componentKey(_ component: NameComponent) -> String {
        switch component {
        case let .feature(featureID):
            return "feature:\(featureID.rawValue.uuidString)"
        case let .generated(value):
            return "generated:\(value)"
        case let .subshape(value):
            return "subshape:\(value)"
        case let .index(index):
            return "index:\(index)"
        }
    }
}

private enum SnapTopologyKey: Hashable {
    case vertex(VertexID)
    case edge(EdgeID)
    case face(FaceID)
}
