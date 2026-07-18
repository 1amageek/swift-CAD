import CADCore
import CADIR
import CADTopology

package struct SubshapeGeometrySignatureBuilder {
    package let model: BRepModel
    package let tolerance: ModelingTolerance

    package init(model: BRepModel, tolerance: ModelingTolerance) {
        self.model = model
        self.tolerance = tolerance
    }

    package func signature(
        for reference: TopologyReference
    ) throws -> SubshapeGeometrySignature {
        switch reference {
        case let .body(bodyID):
            guard let body = model.bodies[bodyID] else { throw missingTopology("body") }
            var points: [Point3D] = []
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else { throw missingTopology("shell") }
                for faceID in shell.faceIDs {
                    points.append(contentsOf: try boundaryPoints(for: faceID))
                }
            }
            return .body(boundaryPoints: canonicalPoints(points))
        case let .vertex(vertexID):
            guard let vertex = model.vertices[vertexID] else { throw missingTopology("vertex") }
            return .vertex(point: vertex.point)
        case let .edge(edgeID):
            guard let edge = model.edges[edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point else {
                throw missingTopology("edge")
            }
            let midpoint: Point3D
            if let trim = edge.trim {
                midpoint = try curve.point(
                    at: trim.startParameter + (trim.endParameter - trim.startParameter) * 0.5,
                    tolerance: tolerance
                )
            } else {
                midpoint = Point3D(
                    x: (start.x + end.x) * 0.5,
                    y: (start.y + end.y) * 0.5,
                    z: (start.z + end.z) * 0.5
                )
            }
            return .edge(
                kind: curveKind(curve),
                start: start,
                midpoint: midpoint,
                end: end
            )
        case let .face(faceID):
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw missingTopology("face")
            }
            var points = try boundaryPoints(for: faceID)
            if points.isEmpty {
                points = [try surface.point(
                    u: signatureParameter(in: surface.uDomain),
                    v: signatureParameter(in: surface.vDomain),
                    tolerance: tolerance
                )]
            }
            return .face(
                kind: surfaceKind(surface),
                boundaryPoints: canonicalPoints(points)
            )
        }
    }

    package func matches(
        _ lhs: SubshapeGeometrySignature,
        _ rhs: SubshapeGeometrySignature
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.body(first), .body(second)):
            return pointsMatch(first, second)
        case let (.face(firstKind, first), .face(secondKind, second)):
            return firstKind == secondKind && pointsMatch(first, second)
        case let (.vertex(first), .vertex(second)):
            return first.isApproximatelyEqual(to: second, tolerance: tolerance.distance)
        case let (.edge(firstKind, firstStart, firstMidpoint, firstEnd),
                  .edge(secondKind, secondStart, secondMidpoint, secondEnd)):
            guard firstKind == secondKind,
                  firstMidpoint.isApproximatelyEqual(to: secondMidpoint, tolerance: tolerance.distance) else {
                return false
            }
            let forward = firstStart.isApproximatelyEqual(to: secondStart, tolerance: tolerance.distance)
                && firstEnd.isApproximatelyEqual(to: secondEnd, tolerance: tolerance.distance)
            let reversed = firstStart.isApproximatelyEqual(to: secondEnd, tolerance: tolerance.distance)
                && firstEnd.isApproximatelyEqual(to: secondStart, tolerance: tolerance.distance)
            return forward || reversed
        default:
            return false
        }
    }

    private func pointsMatch(_ lhs: [Point3D], _ rhs: [Point3D]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.isApproximatelyEqual(to: $1, tolerance: tolerance.distance)
        }
    }

    private func boundaryPoints(for faceID: FaceID) throws -> [Point3D] {
        guard let face = model.faces[faceID] else { throw missingTopology("face") }
        return try face.loops.flatMap { try model.orderedPoints(for: $0) }
    }

    private func canonicalPoints(_ points: [Point3D]) -> [Point3D] {
        Array(Set(points)).sorted(by: Self.pointOrder(_:_:))
    }

    private func curveKind(_ curve: Curve3D) -> SubshapeGeometrySignature.CurveKind {
        switch curve {
        case .line, .analytic(.line): return .line
        case .circle, .analytic(.circle): return .circle
        case .analytic(.arc): return .arc
        case .analytic(.ellipse): return .ellipse
        case .bSpline: return .bSpline
        }
    }

    private func surfaceKind(_ surface: Surface3D) -> SubshapeGeometrySignature.SurfaceKind {
        switch surface {
        case .plane, .analytic(.plane): return .plane
        case .cylinder, .analytic(.cylinder): return .cylinder
        case .analytic(.cone): return .cone
        case .analytic(.sphere): return .sphere
        case .analytic(.torus): return .torus
        case .bSpline: return .bSpline
        }
    }

    private func signatureParameter(in domain: ParameterDomain) -> Double {
        switch domain {
        case .unbounded, .periodic: return 0.0
        case let .closed(lower, upper): return lower + (upper - lower) * 0.5
        }
    }

    private func missingTopology(_ kind: String) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: .missingReference,
            tolerance: tolerance,
            message: "Stable selection geometry signature references a missing \(kind)."
        )
    }

    private static func pointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }
}
