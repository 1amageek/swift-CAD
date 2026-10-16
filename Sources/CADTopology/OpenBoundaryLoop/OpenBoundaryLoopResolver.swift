import CADCore
import CADGeometry
import HashTreeCollections

public struct OpenBoundaryLoopResolver: Sendable {
  public init() {}

  public func loops(in body: Body, model: BRepModel) throws -> [OpenBoundaryEdgeLoop] {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try loops(in: body, model: model, using: &execution)
  }

  public func loops(in body: Body, model: BRepModel, using execution: inout OriginalQueryExecution)
    throws -> [OpenBoundaryEdgeLoop]
  {
    try execution.consumeWork(1)
    let boundaryIDs = try boundaryEdgeIDs(in: body, model: model, using: &execution)
    let adjacency = try adjacency(for: boundaryIDs, model: model, using: &execution)
    var remaining = boundaryIDs
    var result: [OpenBoundaryEdgeLoop] = []

    while let seed = try remaining.min(by: { first, second in
      try execution.consumeWork(1)
      return first < second
    }) {
      try execution.consumeWork(1)

      let component = try component(
        startingAt: seed, adjacency: adjacency, model: model, using: &execution)
      for edgeID in component {
        try execution.consumeWork(1)
        remaining.remove(edgeID)
      }
      guard
        try isClosedNonBranchingCycle(
          component,
          adjacency: adjacency,
          model: model, using: &execution),
        let ordered = try orderedLoop(
          startingAt: seed,
          component: component,
          adjacency: adjacency,
          model: model, using: &execution)
      else {
        continue
      }
      try execution.retainStorage(count: 1, stride: MemoryLayout<OpenBoundaryEdgeLoop>.stride)
      result.append(OpenBoundaryEdgeLoop(traversals: ordered))
    }
    return result
  }

  public func loop(
    startingAt edgeID: EdgeID,
    in body: Body,
    model: BRepModel
  ) throws -> OpenBoundaryEdgeLoop? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try loop(startingAt: edgeID, in: body, model: model, using: &execution)
  }

  public func loop(
    startingAt edgeID: EdgeID,
    in body: Body,
    model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> OpenBoundaryEdgeLoop? {
    try execution.consumeWork(1)
    let boundaryIDs = try boundaryEdgeIDs(in: body, model: model, using: &execution)
    guard boundaryIDs.contains(edgeID) else { return nil }
    let adjacency = try adjacency(for: boundaryIDs, model: model, using: &execution)
    let component = try component(
      startingAt: edgeID, adjacency: adjacency, model: model, using: &execution)
    guard
      try isClosedNonBranchingCycle(
        component,
        adjacency: adjacency,
        model: model, using: &execution),
      let ordered = try orderedLoop(
        startingAt: edgeID,
        component: component,
        adjacency: adjacency,
        model: model, using: &execution)
    else {
      return nil
    }
    return OpenBoundaryEdgeLoop(traversals: ordered)
  }

  public func isFillableSurfaceBoundary(
    _ boundary: OpenBoundaryEdgeLoop,
    in body: Body,
    model: BRepModel
  ) throws -> Bool {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try isFillableSurfaceBoundary(boundary, in: body, model: model, using: &execution)
  }

  public func isFillableSurfaceBoundary(
    _ boundary: OpenBoundaryEdgeLoop,
    in body: Body,
    model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    var faceIDs: Set<FaceID> = []
    for shellID in try body.originalShellIDs(using: &execution) {
      try execution.consumeWork(1)
      guard let shell = model.shells[shellID] else { continue }
      for faceID in shell.faceIDs {
        try execution.consumeWork(1)
        if !faceIDs.contains(faceID) {
          try execution.retainStorage(count: 1, stride: MemoryLayout<FaceID>.stride)
          faceIDs.insert(faceID)
        }
      }
    }
    guard !faceIDs.isEmpty else { return false }
    guard faceIDs.count == 1, let faceID = faceIDs.first,
      let face = model.faces[faceID]
    else { return true }
    var boundaryEdgeIDs: Set<EdgeID> = []
    for traversal in boundary.traversals {
      try execution.consumeWork(1)
      guard !boundaryEdgeIDs.contains(traversal.edgeID) else { return false }
      try execution.retainStorage(count: 1, stride: MemoryLayout<EdgeID>.stride)
      boundaryEdgeIDs.insert(traversal.edgeID)
    }
    for loopID in face.loops {
      try execution.consumeWork(1)
      guard let loop = model.loops[loopID], loop.role == .inner,
        loop.coedges.count == boundary.traversals.count
      else { continue }
      var loopEdgeIDs: Set<EdgeID> = []
      for coedge in loop.coedges {
        try execution.consumeWork(1)
        if !loopEdgeIDs.contains(coedge.edgeID) {
          try execution.retainStorage(count: 1, stride: MemoryLayout<EdgeID>.stride)
          loopEdgeIDs.insert(coedge.edgeID)
        }
      }
      if loopEdgeIDs.count == boundaryEdgeIDs.count {
        var equal = true
        for edgeID in loopEdgeIDs {
          try execution.consumeWork(1)
          if !boundaryEdgeIDs.contains(edgeID) {
            equal = false
            break
          }
        }
        if equal { return true }
      }
    }
    return false
  }

  /// The body's open edges: each used by exactly one face, whether or not it closes a loop.
  public func boundaryEdgeIDs(in body: Body, model: BRepModel) throws -> Set<EdgeID> {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try boundaryEdgeIDs(in: body, model: model, using: &execution)
  }

  public func boundaryEdgeIDs(
    in body: Body, model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> Set<EdgeID> {
    try execution.consumeWork(1)
    var uses: [EdgeID: Int] = [:]
    for shellID in try body.originalShellIDs(using: &execution) {
      try execution.consumeWork(1)

      guard let shell = model.shells[shellID] else { continue }
      for faceID in shell.faceIDs {
        try execution.consumeWork(1)

        guard let face = model.faces[faceID] else { continue }
        for loopID in face.loops {
          try execution.consumeWork(1)

          guard let loop = model.loops[loopID] else { continue }
          for coedge in loop.coedges where model.edges[coedge.edgeID] != nil {
            try execution.consumeWork(1)

            if uses[coedge.edgeID] == nil {
              try execution.retainStorage(count: 1, stride: MemoryLayout<(EdgeID, Int)>.stride)
            }
            let count = (uses[coedge.edgeID] ?? 0).addingReportingOverflow(1)
            guard !count.overflow else { throw ExactScalarFailure.countOverflow }
            uses[coedge.edgeID] = count.partialValue
          }
        }
      }
    }
    var result: Set<EdgeID> = []
    for (edgeID, count) in uses {
      try execution.consumeWork(1)
      if count == 1 {
        try execution.retainStorage(count: 1, stride: MemoryLayout<EdgeID>.stride)
        result.insert(edgeID)
      }
    }
    return result
  }

  private func adjacency(
    for edgeIDs: Set<EdgeID>,
    model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> [VertexID: [EdgeID]] {
    try execution.consumeWork(1)
    var result: [VertexID: [EdgeID]] = [:]
    for edgeID in edgeIDs {
      try execution.consumeWork(1)

      guard let edge = model.edges[edgeID] else { continue }
      try execution.retainStorage(
        count: 2, stride: MemoryLayout<(VertexID, [EdgeID])>.stride + MemoryLayout<EdgeID>.stride)
      result[edge.startVertexID, default: []].append(edgeID)
      result[edge.endVertexID, default: []].append(edgeID)
    }
    return result
  }

  private func component(
    startingAt edgeID: EdgeID,
    adjacency: [VertexID: [EdgeID]],
    model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> Set<EdgeID> {
    try execution.consumeWork(1)
    var result: Set<EdgeID> = []
    guard let seed = model.edges[edgeID] else {
      return result
    }
    try execution.retainStorage(count: 2, stride: MemoryLayout<VertexID>.stride)
    var pending = [seed.startVertexID, seed.endVertexID]
    var visitedVertices: Set<VertexID> = []
    while let vertexID = pending.popLast() {
      try execution.consumeWork(1)

      guard !visitedVertices.contains(vertexID) else { continue }
      try execution.retainStorage(count: 1, stride: MemoryLayout<VertexID>.stride)
      visitedVertices.insert(vertexID)
      for connectedEdgeID in adjacency[vertexID, default: []] {
        try execution.consumeWork(1)

        if !result.contains(connectedEdgeID) {
          try execution.retainStorage(count: 1, stride: MemoryLayout<EdgeID>.stride)
          result.insert(connectedEdgeID)
          guard let edge = model.edges[connectedEdgeID] else { continue }
          try execution.retainStorage(count: 2, stride: MemoryLayout<VertexID>.stride)
          pending.append(edge.startVertexID)
          pending.append(edge.endVertexID)
        }
      }
    }
    return result
  }

  private func isClosedNonBranchingCycle(
    _ component: Set<EdgeID>,
    adjacency: [VertexID: [EdgeID]],
    model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    guard !component.isEmpty else { return false }
    return try component.allSatisfy { edgeID in
      try execution.consumeWork(1)

      guard let edge = model.edges[edgeID] else { return false }
      return adjacency[edge.startVertexID]?.count == 2
        && adjacency[edge.endVertexID]?.count == 2
    }
  }

  private func orderedLoop(
    startingAt seedID: EdgeID,
    component: Set<EdgeID>,
    adjacency: [VertexID: [EdgeID]],
    model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> [OpenBoundaryEdgeLoop.Traversal]? {
    try execution.consumeWork(1)
    guard let seed = model.edges[seedID] else {
      return nil
    }
    let startVertexID = seed.startVertexID
    var currentVertexID = seed.endVertexID
    try execution.retainStorage(count: component.count, stride: MemoryLayout<EdgeID>.stride)
    try execution.retainStorage(
      count: component.count, stride: MemoryLayout<OpenBoundaryEdgeLoop.Traversal>.stride)
    var used: Set<EdgeID> = [seedID]
    var result = [
      OpenBoundaryEdgeLoop.Traversal(
        edgeID: seedID,
        followsStoredDirection: true
      )
    ]

    while currentVertexID != startVertexID {
      try execution.consumeWork(1)

      var candidates: [EdgeID] = []
      for candidate in adjacency[currentVertexID, default: []] {
        try execution.consumeWork(1)
        if component.contains(candidate) && !used.contains(candidate) {
          try execution.retainStorage(count: 1, stride: MemoryLayout<EdgeID>.stride)
          candidates.append(candidate)
        }
      }
      guard candidates.count == 1,
        let next = model.edges[candidates[0]]
      else {
        return nil
      }
      let followsStoredDirection = next.startVertexID == currentVertexID
      guard followsStoredDirection || next.endVertexID == currentVertexID else {
        return nil
      }
      currentVertexID = followsStoredDirection ? next.endVertexID : next.startVertexID
      used.insert(next.id)
      try execution.retainStorage(
        count: 1, stride: MemoryLayout<OpenBoundaryEdgeLoop.Traversal>.stride)
      result.append(
        OpenBoundaryEdgeLoop.Traversal(
          edgeID: next.id,
          followsStoredDirection: followsStoredDirection
        ))
      guard result.count <= component.count else { return nil }
    }
    guard used.count == component.count else { return nil }
    for edgeID in used {
      try execution.consumeWork(1)
      guard component.contains(edgeID) else { return nil }
    }
    return result
  }
}
