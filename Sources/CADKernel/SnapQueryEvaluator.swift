import Foundation
import CADCore
import CADIR

public struct SnapQueryEvaluator: Sendable {
    private let tolerance: ModelingTolerance
    private let edgeQueryEvaluator: EdgeQueryEvaluator
    private let surfaceQueryEvaluator: SurfaceQueryEvaluator

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
        self.edgeQueryEvaluator = EdgeQueryEvaluator(tolerance: tolerance)
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
                guard options.includesVertices,
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
                        point: vertex.point,
                        distance: distance
                    ),
                    to: &candidates,
                    options: options
                )
            case let .edge(edgeID):
                guard options.includesEdges,
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
                        point: projection.projectedPoint,
                        distance: projection.distance,
                        tangent: projection.frame.tangent,
                        curvature: projection.frame.curvature
                    ),
                    to: &candidates,
                    options: options
                )
            case let .face(faceID):
                guard options.includesFaces,
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

        candidates.sort { lhs, rhs in
            if abs(lhs.distance - rhs.distance) > tolerance.distance {
                return lhs.distance < rhs.distance
            }
            if lhs.kind != rhs.kind {
                return priority(for: lhs.kind) < priority(for: rhs.kind)
            }
            return persistentNameKey(lhs.persistentName) < persistentNameKey(rhs.persistentName)
        }

        if candidates.count > options.maximumCandidateCount {
            candidates = Array(candidates.prefix(options.maximumCandidateCount))
        }
        return SnapQueryResult(sourcePoint: point, candidates: candidates)
    }

    private func appendCandidate(
        _ candidate: SnapQueryCandidate,
        to candidates: inout [SnapQueryCandidate],
        options: SnapQueryOptions
    ) throws {
        guard candidate.distance.isFinite else {
            throw GeometryError.invalidDistance(candidate.distance)
        }
        if let maximumDistance = options.maximumDistance,
           candidate.distance > maximumDistance + tolerance.distance {
            return
        }
        candidates.append(candidate)
    }

    private func sortedGeneratedNames(
        _ generatedNames: [PersistentName: TopologyReference]
    ) -> [(name: PersistentName, reference: TopologyReference)] {
        generatedNames
            .map { (name: $0.key, reference: $0.value) }
            .sorted { lhs, rhs in
                persistentNameKey(lhs.name) < persistentNameKey(rhs.name)
            }
    }

    private func priority(for kind: SnapCandidateKind) -> Int {
        switch kind {
        case .vertex:
            return 0
        case .edge:
            return 1
        case .face:
            return 2
        }
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
