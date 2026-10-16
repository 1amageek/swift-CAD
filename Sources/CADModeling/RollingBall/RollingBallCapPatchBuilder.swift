import CADCore
import CADGeometry

// FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary KernelRollingBallFilletEvaluator
// consumes this cap builder through RollingBallFilletRequestBuilder in its
// admitted original cap-chain domain. General cap/rim interactions, whole-solid
// validity and lineage behavior must pass before complete fillet support.
package struct RollingBallCapPatchBuilder {
  package init() {}

  package func build(
    source: BRepSewingFacePatch,
    replacing replacements: [String: BRepSewingEdge],
    tolerance: ModelingTolerance
  ) throws -> BRepSewingFacePatch {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try build(
      source: source, replacing: replacements, tolerance: tolerance, using: &execution)
  }

  package func build(
    source: BRepSewingFacePatch,
    replacing replacements: [String: BRepSewingEdge],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> BRepSewingFacePatch {
    try execution.consumeWork(1)
    try source.validate(tolerance: tolerance, using: &execution)
    guard !replacements.isEmpty else {
      throw invalid(tolerance, "A cap treatment requires replacement rails.")
    }
    try execution.retainStorage(count: source.loops.count, stride: MemoryLayout<Int>.stride)
    let affected = try source.loops.indices.filter { index in
      try execution.consumeWork(1)
      return try source.loops[index].edges.contains {
        try execution.consumeWork(1)
        return replacements[$0.stableID] != nil
      }
    }
    guard affected.count == 1, let loopIndex = affected.first else {
      throw invalid(tolerance, "A cap treatment must identify exactly one source loop.")
    }
    let loop = source.loops[loopIndex]
    try execution.retainStorage(count: loop.edges.count, stride: MemoryLayout<Bool>.stride)
    let mask = try loop.edges.map {
      try execution.consumeWork(1)
      return replacements[$0.stableID] != nil
    }
    guard
      try mask.reduce(
        0,
        { count, replaced in
          try execution.consumeWork(1)
          return count + (replaced ? 1 : 0)
        }) == replacements.count
    else {
      throw invalid(tolerance, "A cap replacement references an unknown or repeated source edge.")
    }
    try execution.retainStorage(
      count: loop.edges.count, stride: MemoryLayout<BRepSewingEdge>.stride)
    var edges = try loop.edges.map { original in
      guard let edge = replacements[original.stableID] else { return original }
      guard case .surfaceLift(let lift) = edge.curve, lift.surface == source.surface else {
        throw invalid(tolerance, "A cap rail must retain its exact source support.")
      }
      let span = try lift.parameterCurve.subcurve(
        fromNormalizedFraction: min(edge.startParameter, edge.endParameter),
        toNormalizedFraction: max(edge.startParameter, edge.endParameter), tolerance: tolerance,
        using: &execution)
      let parameters =
        try edge.startParameter < edge.endParameter
        ? span : span.reversed(tolerance: tolerance, using: &execution)
      return try BRepSewingEdge(
        stableID: original.stableID, curve: edge.curve,
        startParameter: edge.startParameter, endParameter: edge.endParameter,
        startPoint: edge.startPoint, endPoint: edge.endPoint,
        surfaceParameterCurve: parameters,
        parentSubshapeIDs: original.parentSubshapeIDs + edge.parentSubshapeIDs,
        startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
        endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs, using: &execution)
    }
    if replacements.count != edges.count {
      try execution.retainStorage(count: edges.count, stride: MemoryLayout<Int>.stride)
      let starts = try edges.indices.filter {
        try execution.consumeWork(1)
        return mask[$0] && !mask[($0 + edges.count - 1) % edges.count]
      }
      guard starts.count == 1, let start = starts.first else {
        throw invalid(tolerance, "Cap replacement rails must form one contiguous cyclic chain.")
      }
      var end = start
      while mask[(end + 1) % edges.count] {
        try execution.consumeWork(1)
        end = (end + 1) % edges.count
      }
      let before = (start + edges.count - 1) % edges.count
      let after = (end + 1) % edges.count
      for index in Set([before, after]) {
        try execution.consumeWork(1)

        let original = loop.edges[index]
        let first = index == after ? edges[end].endPoint : original.startPoint
        let last = index == before ? edges[start].startPoint : original.endPoint
        let pieces = try BRepSewingEdgeSubdivider().subdivide(
          original,
          at: [first, last], tolerance: tolerance, using: &execution)
        try execution.retainStorage(
          count: pieces.count, stride: MemoryLayout<BRepSewingEdge>.stride)
        let retained = try pieces.filter {
          try execution.consumeWork(1)
          return ($0.startPoint - first).length <= tolerance.distance
            && ($0.endPoint - last).length <= tolerance.distance
        }
        guard retained.count == 1, let piece = retained.first else {
          throw invalid(
            tolerance, "Cap contacts do not identify one retained neighboring edge segment.")
        }
        edges[index] = try BRepSewingEdge(
          stableID: piece.stableID, curve: piece.curve,
          startParameter: piece.startParameter, endParameter: piece.endParameter,
          startPoint: first, endPoint: last, surfaceParameterCurve: piece.surfaceParameterCurve,
          parentSubshapeIDs: piece.parentSubshapeIDs,
          startVertexParentSubshapeIDs: piece.startVertexParentSubshapeIDs,
          endVertexParentSubshapeIDs: piece.endVertexParentSubshapeIDs, using: &execution)
      }
    }
    try execution.retainStorage(
      count: source.loops.count, stride: MemoryLayout<BRepSewingLoop>.stride)
    var loops = source.loops
    loops[loopIndex] = BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: edges)
    let result = try BRepSewingFacePatch(
      stableID: source.stableID, surface: source.surface,
      orientation: source.orientation, loops: loops, parentSubshapeIDs: source.parentSubshapeIDs,
      using: &execution)
    try result.validate(tolerance: tolerance, using: &execution)
    return result
  }

  private func invalid(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
    KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance, message: message)
  }
}
