import CADCore
import CADGeometry
import CADTopology
import Foundation

// FIXME(INCOMPLETE_IMPLEMENTATION): Native machining integration tests consume
// this selection step; feature publication still requires complete cap trimming,
// terminal closure, volumetric admission and stable topology lineage.
package struct RollingBallTangentChainResolver {
    package init() {}

    package func resolve(selectedEdge: EdgeID, partner: FaceID, shell: Shell,
                         model: BRepModel, tolerance: ModelingTolerance) throws -> [EdgeID] {
        try tolerance.validate()
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability,
                        tolerance: tolerance, message: message)
        }
        var uses: [EdgeID: [(FaceID, Coedge)]] = [:]
        var faceEdges: [FaceID: [Coedge]] = [:]
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else { throw failure("Missing chain face.") }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw failure("Missing chain loop.") }
                for coedge in loop.edges {
                    uses[coedge.edgeID, default: []].append((faceID, coedge))
                    faceEdges[faceID, default: []].append(coedge)
                }
            }
        }
        guard let partnerEdges = faceEdges[partner],
              partnerEdges.contains(where: { $0.edgeID == selectedEdge }) else {
            throw failure("The selected edge does not belong to the fixed partner face.")
        }
        var vertexEdges: [VertexID: [EdgeID]] = [:]
        for coedge in partnerEdges {
            guard let edge = model.edges[coedge.edgeID] else { throw failure("Missing chain edge.") }
            vertexEdges[edge.startVertexID, default: []].append(edge.id)
            vertexEdges[edge.endVertexID, default: []].append(edge.id)
        }
        func otherFace(_ edge: EdgeID) throws -> FaceID {
            guard let pair = uses[edge], pair.count == 2,
                  pair.filter({ $0.0 == partner }).count == 1,
                  let other = pair.first(where: { $0.0 != partner }) else {
                throw failure("A treatment edge requires two distinct incident faces.")
            }
            return other.0
        }
        var result = [selectedEdge]
        var visited: Set<EdgeID> = [selectedEdge]
        var cursor = 0
        while cursor < result.count {
            let current = result[cursor]
            cursor += 1
            guard let edge = model.edges[current] else { throw failure("Missing selected chain edge.") }
            let firstID = try otherFace(current)
            for vertex in [edge.startVertexID, edge.endVertexID] {
                guard let candidates = vertexEdges[vertex], candidates.count == 2,
                      let next = candidates.first(where: { $0 != current }) else {
                    throw failure("The fixed partner boundary is not a simple chain.")
                }
                if visited.contains(next) { continue }
                let secondID = try otherFace(next)
                guard let firstFace = model.faces[firstID], let secondFace = model.faces[secondID],
                      let firstSurface = model.geometry.surfaces[firstFace.surfaceID],
                      let secondSurface = model.geometry.surfaces[secondFace.surfaceID],
                      case let .bSpline(firstSpline) = firstSurface,
                      case let .bSpline(secondSpline) = secondSurface else {
                    throw failure("Tangent-chain certification requires supported B-spline charts.")
                }
                guard let firstEdges = faceEdges[firstID], let secondEdges = faceEdges[secondID] else {
                    throw failure("Missing incident source-face boundaries.")
                }
                let seams = firstEdges.filter { coedge in
                    guard let boundary = model.edges[coedge.edgeID],
                          boundary.startVertexID == vertex || boundary.endVertexID == vertex else { return false }
                    return secondEdges.contains { $0.edgeID == coedge.edgeID }
                }
                guard seams.count == 1, let a = seams.first,
                      let b = secondEdges.first(where: { $0.edgeID == a.edgeID }),
                      let aUV = a.surfaceParameterCurve, let bUV = b.surfaceParameterCurve else {
                    throw failure("A continuation requires one shared source-surface seam.")
                }
                let aBoundary = try boundary(aUV, on: firstSurface, tolerance: tolerance)
                let bBoundary = try boundary(bUV, on: secondSurface, tolerance: tolerance)
                guard let bounds = try RationalBezierSurfaceDifferentialBounds.boundaryNormalSineBounds(
                    first: firstSpline, firstBoundary: aBoundary.side,
                    second: secondSpline, secondBoundary: bBoundary.side,
                    reverseSecond: (aBoundary.increasing == bBoundary.increasing)
                        != (a.orientation == b.orientation), tolerance: tolerance) else {
                    throw failure("The source seam tangent certificate is inconclusive after \(result.count) edges: \(firstSpline.uDegree)x\(firstSpline.vDegree) and \(secondSpline.uDegree)x\(secondSpline.vDegree), controls \(firstSpline.uControlPointCount)x\(firstSpline.vControlPointCount) and \(secondSpline.uControlPointCount)x\(secondSpline.vControlPointCount).")
                }
                if bounds.lower > sin(tolerance.angle) { continue }
                guard bounds.upper <= sin(tolerance.angle) else {
                    throw failure("The source seam cannot yet be classified as smooth or creased.")
                }
                visited.insert(next)
                result.append(next)
            }
        }
        return result
    }

    private func boundary(_ curve: SurfaceParameterCurve, on surface: Surface3D,
                          tolerance: ModelingTolerance) throws
        -> (side: SurfaceParameterBoundary, increasing: Bool) {
        switch curve {
        case let .constantU(u, start, end):
            if case let .closed(lower, upper) = surface.uDomain, u == lower || u == upper,
               case let .closed(v0, v1) = surface.vDomain,
               min(start, end) == v0, max(start, end) == v1 {
                return (u == lower ? .uLower : .uUpper, end > start)
            }
        case let .constantV(v, start, end):
            if case let .closed(lower, upper) = surface.vDomain, v == lower || v == upper,
               case let .closed(u0, u1) = surface.uDomain,
               min(start, end) == u0, max(start, end) == u1 {
                return (v == lower ? .vLower : .vUpper, end > start)
            }
        default: break
        }
        throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                          message: "Tangent continuation requires a complete isoparametric seam.")
    }
}
