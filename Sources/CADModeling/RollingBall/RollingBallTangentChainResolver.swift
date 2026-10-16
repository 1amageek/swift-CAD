import CADCore
import CADGeometry
import CADTopology

#if !hasFeature(Embedded)
  import Foundation
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#else
  #error("Rolling-ball tangent certification requires the target C math module.")
#endif

// FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary KernelRollingBallFilletEvaluator
// and its request builder consume this selection step for the admitted original
// cap-chain domain. Mandatory general partner/network selection, terminal closure,
// volumetric admission and lineage behavior remain required for full support.
package struct RollingBallTangentChainResolver {
  package init() {}

  package func resolve(
    selectedEdge: EdgeID, partner: FaceID, shell: Shell,
    model: BRepModel, tolerance: ModelingTolerance
  ) throws -> [EdgeID] {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try resolve(
      selectedEdge: selectedEdge, partner: partner, shell: shell, model: model,
      tolerance: tolerance, using: &execution)
  }

  package func resolve(
    selectedEdge: EdgeID, partner: FaceID, shell: Shell,
    model: BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [EdgeID] {
    try execution.consumeWork(1)
    try tolerance.validate()
    func failure(_ message: String) -> KernelError {
      KernelError(
        phase: .evaluation, code: .unsupportedCapability,
        tolerance: tolerance, message: message)
    }
    var uses: [EdgeID: [(FaceID, Coedge)]] = [:]
    var faceEdges: [FaceID: [Coedge]] = [:]
    for faceID in shell.faceIDs {
      try execution.consumeWork(1)

      guard let face = model.faces[faceID] else { throw failure("Missing chain face.") }
      for loopID in face.loops {
        try execution.consumeWork(1)

        guard let loop = model.loops[loopID] else { throw failure("Missing chain loop.") }
        for coedge in loop.edges {
          try execution.consumeWork(1)

          try execution.retainStorage(
            count: 1,
            stride: MemoryLayout<(FaceID, Coedge)>.stride
              + MemoryLayout<(EdgeID, [(FaceID, Coedge)])>.stride)
          uses[coedge.edgeID, default: []].append((faceID, coedge))
          try execution.retainStorage(
            count: 1, stride: MemoryLayout<Coedge>.stride + MemoryLayout<(FaceID, [Coedge])>.stride)
          faceEdges[faceID, default: []].append(coedge)
        }
      }
    }
    guard let partnerEdges = faceEdges[partner],
      try partnerEdges.contains(where: {
        try execution.consumeWork(1)
        return $0.edgeID == selectedEdge
      })
    else {
      throw failure("The selected edge does not belong to the fixed partner face.")
    }
    var vertexEdges: [VertexID: [EdgeID]] = [:]
    for coedge in partnerEdges {
      try execution.consumeWork(1)

      guard let edge = model.edges[coedge.edgeID] else { throw failure("Missing chain edge.") }
      try execution.retainStorage(
        count: 2, stride: MemoryLayout<EdgeID>.stride + MemoryLayout<(VertexID, [EdgeID])>.stride)
      vertexEdges[edge.startVertexID, default: []].append(edge.id)
      vertexEdges[edge.endVertexID, default: []].append(edge.id)
    }
    func otherFace(_ edge: EdgeID) throws -> FaceID {
      guard let pair = uses[edge], pair.count == 2,
        pair.filter({ $0.0 == partner }).count == 1,
        let other = pair.first(where: { $0.0 != partner })
      else {
        throw failure("A treatment edge requires two distinct incident faces.")
      }
      return other.0
    }
    try execution.retainStorage(count: 1, stride: MemoryLayout<EdgeID>.stride * 2)
    var result = [selectedEdge]
    var visited: Set<EdgeID> = [selectedEdge]
    var cursor = 0
    while cursor < result.count {
      try execution.consumeWork(1)

      let current = result[cursor]
      cursor += 1
      guard let edge = model.edges[current] else { throw failure("Missing selected chain edge.") }
      let firstID = try otherFace(current)
      if edge.startVertexID == edge.endVertexID,
        let incidences = vertexEdges[edge.startVertexID],
        incidences.count == 2, incidences.allSatisfy({ $0 == current })
      {
        guard
          try BRepEdgeGeometryClassifier().kind(
            of: edge, in: model,
            tolerance: tolerance, using: &execution) == .closed
        else {
          throw failure("A single-edge partner loop requires an original closed-curve certificate.")
        }
        continue
      }
      for vertex in [edge.startVertexID, edge.endVertexID] {
        try execution.consumeWork(1)

        guard let candidates = vertexEdges[vertex], candidates.count == 2,
          let next = candidates.first(where: { $0 != current })
        else {
          throw failure("The fixed partner boundary is not a simple chain.")
        }
        if visited.contains(next) { continue }
        let secondID = try otherFace(next)
        guard let firstFace = model.faces[firstID], let secondFace = model.faces[secondID],
          let firstSurface = model.geometry.surfaces[firstFace.surfaceID],
          let secondSurface = model.geometry.surfaces[secondFace.surfaceID],
          case .bSpline(let firstSpline) = firstSurface,
          case .bSpline(let secondSpline) = secondSurface
        else {
          throw failure("Tangent-chain certification requires supported B-spline charts.")
        }
        guard let firstEdges = faceEdges[firstID], let secondEdges = faceEdges[secondID] else {
          throw failure("Missing incident source-face boundaries.")
        }
        try execution.retainStorage(count: firstEdges.count, stride: MemoryLayout<Coedge>.stride)
        let seams = try firstEdges.filter { coedge in
          try execution.consumeWork(1)
          guard let boundary = model.edges[coedge.edgeID],
            boundary.startVertexID == vertex || boundary.endVertexID == vertex
          else { return false }
          return try secondEdges.contains {
            try execution.consumeWork(1)
            return $0.edgeID == coedge.edgeID
          }
        }
        guard seams.count == 1, let a = seams.first,
          let b = try secondEdges.first(where: {
            try execution.consumeWork(1)
            return $0.edgeID == a.edgeID
          }),
          let aUV = a.surfaceParameterCurve, let bUV = b.surfaceParameterCurve
        else {
          throw failure("A continuation requires one shared source-surface seam.")
        }
        let aBoundary = try boundary(aUV, on: firstSurface, tolerance: tolerance, using: &execution)
        let bBoundary = try boundary(
          bUV, on: secondSurface, tolerance: tolerance, using: &execution)
        guard
          let bounds = try RationalBezierSurfaceDifferentialBounds.boundaryNormalSineBounds(
            first: firstSpline, firstBoundary: aBoundary.side,
            second: secondSpline, secondBoundary: bBoundary.side,
            reverseSecond: (aBoundary.increasing == bBoundary.increasing)
              != (a.orientation == b.orientation), tolerance: tolerance, using: &execution)
        else {
          throw failure(
            "The source seam tangent certificate is inconclusive after \(result.count) edges: \(firstSpline.uDegree)x\(firstSpline.vDegree) and \(secondSpline.uDegree)x\(secondSpline.vDegree), controls \(firstSpline.uControlPointCount)x\(firstSpline.vControlPointCount) and \(secondSpline.uControlPointCount)x\(secondSpline.vControlPointCount)."
          )
        }
        if bounds.lower > sin(tolerance.angle) { continue }
        guard bounds.upper <= sin(tolerance.angle) else {
          throw failure("The source seam cannot yet be classified as smooth or creased.")
        }
        try execution.retainStorage(count: 1, stride: MemoryLayout<EdgeID>.stride * 2)
        visited.insert(next)
        result.append(next)
      }
    }
    return result
  }

  private func boundary(
    _ curve: SurfaceParameterCurve, on surface: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws
    -> (side: SurfaceParameterBoundary, increasing: Bool)
  {
    try execution.consumeWork(1)
    switch curve {
    case .constantU(let u, let start, let end):
      if case .closed(let lower, let upper) = surface.uDomain, u == lower || u == upper,
        case .closed(let v0, let v1) = surface.vDomain,
        min(start, end) == v0, max(start, end) == v1
      {
        return (u == lower ? .uLower : .uUpper, end > start)
      }
    case .constantV(let v, let start, let end):
      if case .closed(let lower, let upper) = surface.vDomain, v == lower || v == upper,
        case .closed(let u0, let u1) = surface.uDomain,
        min(start, end) == u0, max(start, end) == u1
      {
        return (v == lower ? .vLower : .vUpper, end > start)
      }
    default: break
    }
    throw KernelError(
      phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
      message: "Tangent continuation requires a complete isoparametric seam.")
  }
}
