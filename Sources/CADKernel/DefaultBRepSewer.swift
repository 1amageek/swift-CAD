import HashTreeCollections
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif

public struct DefaultBRepSewer: BRepSewing {
  public init() {}

  public func sew(
    _ request: BRepSewingRequest,
    tolerance: ModelingTolerance
  ) throws -> BRepSewingResult {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32)
    )
    return try sew(request, tolerance: tolerance, using: &execution)
  }

  public func sew(
    _ request: BRepSewingRequest,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> BRepSewingResult {
    try execution.consumeWork(1)
    try request.validate(tolerance: tolerance, using: &execution)
    let draft = try assemble(request, tolerance: tolerance, using: &execution)
    let limits = execution.effectiveLimits
    let validatedBRep = try ValidatedBRepModel(
      draft.brep,
      tolerance: tolerance,
      validationLevel: .exact,
      maximumSubdivisionDepth: min(32, limits.maximumSubdivisionDepth),
      remainingSourceDepth: min(16, limits.remainingSourceDepth),
      maximumAlgebraicDepth: min(32, limits.maximumValueDepth, limits.maximumCoefficientDepth),
      using: &execution
    )
    return BRepSewingResult(
      validatedBRep: validatedBRep,
      bodyID: draft.bodyID,
      subshapes: draft.subshapes,
      lineage: draft.lineage,
      stableReferences: draft.stableReferences
    )
  }

  private func assemble(
    _ request: BRepSewingRequest,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> BRepSewingDraft {
    try execution.consumeWork(1)
    var topologyIDs = FeatureTopologyIDAllocator(
      featureID: request.featureID,
      topologyNamespace: request.topologyNamespace
    )
    var model = BRepModel()
    var allVertices: [VertexRecord] = []
    var allEdges: [EdgeRecord] = []
    var allFaces: [FaceRecord] = []
    var generatedShells: [(shell: BRepSewingShell, id: ShellID)] = []
    var stableReferences: [BRepSewingStableKey: TopologyReference] = [:]

    for shell in request.shells.sorted(by: { $0.stableID < $1.stableID }) {
      try execution.consumeWork(1)
      var vertices: [VertexRecord] = []
      var edges: [EdgeRecord] = []
      var faceRecords: [FaceRecord] = []
      let connectivity = try makeConnectivity(
        for: shell,
        records: &vertices,
        model: &model,
        topologyIDs: &topologyIDs,
        tolerance: tolerance,
        using: &execution
      )
      for patch in shell.patches.sorted(by: { $0.stableID < $1.stableID }) {
        try execution.consumeWork(1)
        let surfaceID = topologyIDs.nextSurfaceID()
        let faceID = topologyIDs.nextFaceID()
        model.geometry.surfaces[surfaceID] = patch.surface
        stableReferences[.face(patch.stableID)] = .face(faceID)
        var loopIDs: [LoopID] = []
        let orderedLoops = patch.loops.sorted {
          if $0.role != $1.role { return $0.role == .outer }
          return $0.stableID < $1.stableID
        }
        for loop in orderedLoops {
          try execution.consumeWork(1)
          let loopID = topologyIDs.nextLoopID()
          var coedges: [Coedge] = []
          for sewingEdge in loop.edges {
            try execution.consumeWork(1)
            guard
              let endpointIDs = connectivity.endpointIDs[
                sewingEdge.stableID
              ]
            else {
              throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message:
                  "Sewing connectivity has no endpoint identity for edge \(sewingEdge.stableID)."
              )
            }
            let startVertexID = endpointIDs.start
            let endVertexID = endpointIDs.end
            let geometryKind = try BRepEdgeGeometryClassifier().kind(
              curve: sewingEdge.curve, from: sewingEdge.startParameter,
              to: sewingEdge.endParameter, tolerance: tolerance, using: &execution)
            guard startVertexID != endVertexID || geometryKind != .open else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Sewing collapsed an edge to one canonical vertex."
              )
            }
            let use = try canonicalEdge(
              sewingEdge,
              patchStableID: patch.stableID,
              faceSurface: patch.surface,
              startVertexID: startVertexID,
              endVertexID: endVertexID,
              records: &edges,
              model: &model,
              topologyIDs: &topologyIDs,
              tolerance: tolerance,
              using: &execution
            )
            stableReferences[.edge(sewingEdge.stableID)] = .edge(use.edgeID)
            stableReferences[.startVertex(edge: sewingEdge.stableID)] = .vertex(startVertexID)
            stableReferences[.endVertex(edge: sewingEdge.stableID)] = .vertex(endVertexID)
            coedges.append(
              Coedge(
                edgeID: use.edgeID,
                orientation: use.orientation,
                surfaceParameterCurve: use.surfaceParameterCurve
              ))
          }
          model.loops[loopID] = Loop(id: loopID, role: loop.role, coedges: coedges)
          loopIDs.append(loopID)
        }
        model.faces[faceID] = Face(
          id: faceID,
          surfaceID: surfaceID,
          loops: loopIDs,
          orientation: patch.orientation
        )
        faceRecords.append(
          FaceRecord(
            id: faceID,
            parents: patch.parentSubshapeIDs
          ))
      }
      try validateEdgeUses(
        edges,
        bodyKind: request.bodyKind,
        model: model,
        tolerance: tolerance,
        using: &execution
      )
      let shellID = topologyIDs.nextShellID()
      model.shells[shellID] = Shell(
        id: shellID,
        faceIDs: faceRecords.map { $0.id },
        orientation: shell.orientation
      )
      generatedShells.append((shell, shellID))
      allVertices.append(contentsOf: vertices)
      allEdges.append(contentsOf: edges)
      allFaces.append(contentsOf: faceRecords)
    }

    let bodyID = topologyIDs.nextBodyID()
    model.bodies[bodyID] = Body(
      id: bodyID,
      topology: try bodyTopology(
        requestTopology: request.bodyTopology,
        generatedShells: generatedShells,
        tolerance: tolerance
      )
    )
    stableReferences[.body] = .body(bodyID)
    let identity = topologyIdentity(
      featureID: request.featureID,
      bodyID: bodyID,
      bodyParents: request.bodyParentSubshapeIDs,
      faces: allFaces,
      edges: allEdges,
      vertices: allVertices
    )
    return BRepSewingDraft(
      brep: model,
      bodyID: bodyID,
      subshapes: identity.subshapes,
      lineage: identity.lineage,
      stableReferences: stableReferences
    )
  }

  private func bodyTopology(
    requestTopology: BRepSewingBodyTopology,
    generatedShells: [(shell: BRepSewingShell, id: ShellID)],
    tolerance: ModelingTolerance
  ) throws -> BodyTopology {
    let shellIDsByStableID = Dictionary(
      uniqueKeysWithValues: generatedShells.map {
        ($0.shell.stableID, $0.id)
      })
    func shellID(for stableID: String) throws -> ShellID {
      guard let shellID = shellIDsByStableID[stableID] else {
        throw KernelError(
          phase: .topology,
          code: .missingReference,
          tolerance: tolerance,
          message: "Sewing topology references an unavailable stable shell identity."
        )
      }
      return shellID
    }
    switch requestTopology {
    case .sheet(let shellStableIDs):
      return .sheet(
        shellIDs: try shellStableIDs.map {
          try shellID(for: $0)
        })
    case .solid(let components):
      return .solid(
        components: try components.map { component in
          SolidShellComponent(
            outerShellID: try shellID(for: component.outerShellStableID),
            voidShellIDs: try component.voidShellStableIDs.map {
              try shellID(for: $0)
            }
          )
        })
    }
  }

  private func makeConnectivity(
    for shell: BRepSewingShell,
    records: inout [VertexRecord],
    model: inout BRepModel,
    topologyIDs: inout FeatureTopologyIDAllocator,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SewingConnectivity {
    try execution.consumeWork(1)
    var slots: [EndpointSlot] = []
    var uses: [InputEdgeUse] = []
    var endpointSlots: [String: EndpointSlotPair] = [:]
    var disjointSet = try DisjointSet(count: 0, using: &execution)

    let orderedPatches = shell.patches.sorted { $0.stableID < $1.stableID }
    for patch in orderedPatches {
      try execution.consumeWork(1)
      let orderedLoops = patch.loops.sorted {
        if $0.role != $1.role { return $0.role == .outer }
        return $0.stableID < $1.stableID
      }
      for loop in orderedLoops {
        try execution.consumeWork(1)
        var loopPairs: [EndpointSlotPair] = []
        for edge in loop.edges {
          try execution.consumeWork(1)
          let start = slots.count
          slots.append(
            EndpointSlot(
              point: edge.startPoint,
              parents: edge.startVertexParentSubshapeIDs,
              stableKey: "\(edge.stableID):start"
            ))
          let end = slots.count
          slots.append(
            EndpointSlot(
              point: edge.endPoint,
              parents: edge.endVertexParentSubshapeIDs,
              stableKey: "\(edge.stableID):end"
            ))
          try disjointSet.appendPair(using: &execution)
          let geometryKind = try BRepEdgeGeometryClassifier().kind(
            curve: edge.curve, from: edge.startParameter, to: edge.endParameter, tolerance: tolerance, using: &execution)
          if geometryKind != .open {
            try disjointSet.union(start, end, using: &execution)
          }
          let pair = EndpointSlotPair(start: start, end: end)
          endpointSlots[edge.stableID] = pair
          loopPairs.append(pair)
          uses.append(InputEdgeUse(edge: edge, slots: pair))
        }
        for index in loopPairs.indices {
          try execution.consumeWork(1)
          try disjointSet.union(
            loopPairs[index].end,
            loopPairs[(index + 1) % loopPairs.count].start,
            using: &execution
          )
        }
      }
    }

    // ponytail: O(n²) endpoint scan; use a conservative spatial index if
    // endpoint comparisons dominate after eliminating full edge-value copies.
    let pairs = uses.map { $0.slots }
    for firstIndex in pairs.indices {
      try execution.checkpoint()
      let first = pairs[firstIndex]
      // Singular parameter boundaries have no physical span to share. Preserve each
      // face's own original UV law, even when two boundaries map to the same point.
      if try BRepEdgeGeometryClassifier().kind(curve: uses[firstIndex].edge.curve,
        from: uses[firstIndex].edge.startParameter, to: uses[firstIndex].edge.endParameter,
        tolerance: tolerance, using: &execution) == .singular { continue }
      for secondIndex in (firstIndex + 1)..<pairs.count {
        try execution.consumeWork(1)
        let second = pairs[secondIndex]
        if try BRepEdgeGeometryClassifier().kind(curve: uses[secondIndex].edge.curve,
          from: uses[secondIndex].edge.startParameter, to: uses[secondIndex].edge.endParameter,
          tolerance: tolerance, using: &execution) == .singular { continue }
        let forwardEndpointsAgree = endpointsAgree(
          first,
          second,
          slots: slots,
          orientation: .forward,
          tolerance: tolerance
        )
        if forwardEndpointsAgree,
          try isProvablySameCurveSpan(
            CurveSpanDefinition(uses[secondIndex].edge),
            record: CurveSpanDefinition(uses[firstIndex].edge),
            orientation: .forward,
            tolerance: tolerance,
            using: &execution
          )
        {
          try disjointSet.union(first.start, second.start, using: &execution)
          try disjointSet.union(first.end, second.end, using: &execution)
          continue
        }
        let reversedEndpointsAgree = endpointsAgree(
          first,
          second,
          slots: slots,
          orientation: .reversed,
          tolerance: tolerance
        )
        if reversedEndpointsAgree,
          try isProvablySameCurveSpan(
            CurveSpanDefinition(uses[secondIndex].edge),
            record: CurveSpanDefinition(uses[firstIndex].edge),
            orientation: .reversed,
            tolerance: tolerance,
            using: &execution
          )
        {
          try disjointSet.union(first.start, second.end, using: &execution)
          try disjointSet.union(first.end, second.start, using: &execution)
        }
      }
    }

    var groupedSlots: [Int: [Int]] = [:]
    for slot in slots.indices {
      try execution.consumeWork(1)
      groupedSlots[try disjointSet.find(slot, using: &execution), default: []].append(slot)
    }
    var vertexIDByRoot: [Int: VertexID] = [:]
    for root in groupedSlots.keys.sorted() {
      try execution.consumeWork(1)
      guard let members = groupedSlots[root],
        let canonicalIndex = members.min(by: {
          slots[$0].stableKey < slots[$1].stableKey
        })
      else {
        continue
      }
      let canonicalPoint = slots[canonicalIndex].point
      var parents: Set<SubshapeID> = []
      for member in members {
        try execution.consumeWork(1)
        let gap = (slots[member].point - canonicalPoint).length
        guard gap <= tolerance.distance else {
          throw KernelError(
            phase: .topology,
            code: .topologyFailure,
            residual: gap,
            tolerance: tolerance,
            message:
              "Topologically identical sewing endpoints disagree geometrically. \(slots[canonicalIndex].stableKey) and \(slots[member].stableKey) exceed the distance contract."
          )
        }
        parents.formUnion(slots[member].parents)
      }
      let vertexID = topologyIDs.nextVertexID()
      model.vertices[vertexID] = Vertex(id: vertexID, point: canonicalPoint)
      records.append(
        VertexRecord(
          id: vertexID,
          point: canonicalPoint,
          parents: parents
        ))
      vertexIDByRoot[root] = vertexID
    }

    var endpointIDs: [String: EndpointVertexPair] = [:]
    for (stableID, pair) in endpointSlots {
      try execution.consumeWork(1)
      guard let start = vertexIDByRoot[try disjointSet.find(pair.start, using: &execution)],
        let end = vertexIDByRoot[try disjointSet.find(pair.end, using: &execution)]
      else {
        throw KernelError(
          phase: .topology,
          code: .missingReference,
          tolerance: tolerance,
          message: "Sewing endpoint union did not materialize a vertex identity."
        )
      }
      endpointIDs[stableID] = EndpointVertexPair(start: start, end: end)
    }
    return SewingConnectivity(endpointIDs: endpointIDs)
  }

  private func endpointsAgree(
    _ first: EndpointSlotPair,
    _ second: EndpointSlotPair,
    slots: [EndpointSlot],
    orientation: Orientation,
    tolerance: ModelingTolerance
  ) -> Bool {
    switch orientation {
    case .forward:
      return slots[first.start].point.isApproximatelyEqual(
        to: slots[second.start].point,
        tolerance: tolerance.distance
      )
        && slots[first.end].point.isApproximatelyEqual(
          to: slots[second.end].point,
          tolerance: tolerance.distance
        )
    case .reversed:
      return slots[first.start].point.isApproximatelyEqual(
        to: slots[second.end].point,
        tolerance: tolerance.distance
      )
        && slots[first.end].point.isApproximatelyEqual(
          to: slots[second.start].point,
          tolerance: tolerance.distance
        )
    }
  }

  private func canonicalEdge(
    _ sewingEdge: BRepSewingEdge,
    patchStableID: String,
    faceSurface: Surface3D,
    startVertexID: VertexID,
    endVertexID: VertexID,
    records: inout [EdgeRecord],
    model: inout BRepModel,
    topologyIDs: inout FeatureTopologyIDAllocator,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> EdgeUse {
    try execution.consumeWork(1)
    let kind = try BRepEdgeGeometryClassifier().kind(curve: sewingEdge.curve,
      from: sewingEdge.startParameter, to: sewingEdge.endParameter, tolerance: tolerance, using: &execution)
    for index in records.indices {
      try execution.consumeWork(1)
      if kind == .singular { continue }
      var matchedOrientation: Orientation?
      for orientation in [Orientation.forward, .reversed] {
        try execution.consumeWork(1)
        let endpointsMatch = orientation == .forward
          ? records[index].startVertexID == startVertexID && records[index].endVertexID == endVertexID
          : records[index].startVertexID == endVertexID && records[index].endVertexID == startVertexID
        if endpointsMatch, try isProvablySameCurveSpan(CurveSpanDefinition(sewingEdge),
          record: records[index].span, orientation: orientation, tolerance: tolerance, using: &execution) {
          matchedOrientation = orientation
          break
        }
      }
      guard let orientation = matchedOrientation else { continue }
      records[index].orientations.append(orientation)
      records[index].parents.formUnion(sewingEdge.parentSubshapeIDs)
      records[index].stableIDs.insert(sewingEdge.stableID)
      records[index].patchStableIDs.insert(patchStableID)
      return EdgeUse(
        edgeID: records[index].id,
        orientation: orientation,
        surfaceParameterCurve: try canonicalSurfaceParameterCurve(
          sewingEdge.surfaceParameterCurve,
          candidateCurve: sewingEdge.curve,
          canonicalSpan: records[index].span,
          faceSurface: faceSurface,
          orientation: orientation,
          tolerance: tolerance,
          using: &execution
        )
      )
    }

    let curveID = topologyIDs.nextCurveID()
    let edgeID = topologyIDs.nextEdgeID()
    model.geometry.curves[curveID] = sewingEdge.curve
    model.edges[edgeID] = Edge(
      id: edgeID,
      curveID: curveID,
      startVertexID: startVertexID,
      endVertexID: endVertexID,
      trim: CurveTrim(
        startParameter: sewingEdge.startParameter,
        endParameter: sewingEdge.endParameter
      )
    )
    records.append(
      EdgeRecord(
        id: edgeID,
        startVertexID: startVertexID,
        endVertexID: endVertexID,
        span: CurveSpanDefinition(sewingEdge),
        orientations: [.forward],
        parents: Set(sewingEdge.parentSubshapeIDs),
        stableIDs: [sewingEdge.stableID],
        patchStableIDs: [patchStableID]
      ))
    return EdgeUse(
      edgeID: edgeID,
      orientation: .forward,
      surfaceParameterCurve: sewingEdge.surfaceParameterCurve
    )
  }

  private func canonicalSurfaceParameterCurve(
    _ parameterCurve: SurfaceParameterCurve,
    candidateCurve: Curve3D,
    canonicalSpan: CurveSpanDefinition,
    faceSurface: Surface3D,
    orientation: Orientation,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterCurve {
    try execution.consumeWork(1)
    guard case .certifiedImplicit(let candidatePcurve) = parameterCurve,
      case .implicit(let candidateIntersection) = candidateCurve,
      case .implicit(let canonicalIntersection) = canonicalSpan.curve
    else {
      return parameterCurve
    }
    guard candidatePcurve.intersection == candidateIntersection,
      try candidateIntersection.certifiesSameComponent(
        as: canonicalIntersection,
        tolerance: tolerance,
        using: &execution
      )
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "A reused implicit sewing edge has no transferable pcurve certificate."
      )
    }
    let role: SurfaceIntersectionSurfaceRole
    if faceSurface == canonicalIntersection.firstSurface {
      role = .first
    } else if faceSurface == canonicalIntersection.secondSurface {
      role = .second
    } else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "A reused implicit sewing edge does not contain the coedge face surface."
      )
    }
    let startFraction: Double
    let endFraction: Double
    switch orientation {
    case .forward:
      startFraction = canonicalSpan.startParameter
      endFraction = canonicalSpan.endParameter
    case .reversed:
      startFraction = canonicalSpan.endParameter
      endFraction = canonicalSpan.startParameter
    }
    return .certifiedImplicit(
      try CertifiedImplicitSurfaceParameterCurve(
        intersection: canonicalIntersection,
        role: role,
        startFraction: startFraction,
        endFraction: endFraction,
        tolerance: tolerance,
        using: &execution
      ))
  }

  private func isProvablySameCurveSpan(
    _ edge: CurveSpanDefinition,
    record: CurveSpanDefinition,
    orientation: Orientation,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    return try CurveSpanCoincidenceMatcher().matches(
      edge,
      record,
      orientation: orientation,
      tolerance: tolerance,
      using: &execution
    )
  }

  private func validateEdgeUses(
    _ edges: [EdgeRecord],
    bodyKind: BodyKind,
    model: BRepModel,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)
    for edge in edges {
      try execution.consumeWork(1)
      if try BRepEdgeGeometryClassifier().kind(curve: edge.span.curve,
        from: edge.span.startParameter, to: edge.span.endParameter, tolerance: tolerance, using: &execution) == .singular {
        guard edge.orientations.count == 1 else {
          throw KernelError(phase: .topology, code: .nonManifoldResult, tolerance: tolerance,
            message: "A singular sewing boundary must retain exactly one face-local parameter use.")
        }
        continue
      }
      let forwardCount = edge.orientations.filter { $0 == .forward }.count
      let reversedCount = edge.orientations.filter { $0 == .reversed }.count
      switch bodyKind {
      case .solid:
        guard edge.orientations.count == 2,
          forwardCount == 1,
          reversedCount == 1
        else {
          let start = model.vertices[edge.startVertexID]?.point
          let end = model.vertices[edge.endVertexID]?.point
          let endpointPeers = edges.filter { candidate in
            candidate.id != edge.id
              && ((candidate.startVertexID == edge.startVertexID
                && candidate.endVertexID == edge.endVertexID)
                || (candidate.startVertexID == edge.endVertexID
                  && candidate.endVertexID == edge.startVertexID))
          }.flatMap { $0.stableIDs }.sorted()
          throw KernelError(
            phase: .topology,
            code: edge.orientations.count > 2 ? .nonManifoldResult : .topologyFailure,
            tolerance: tolerance,
            message:
              "Solid sewing edge \(edge.stableIDs.sorted()) owned by patches \(edge.patchStableIDs.sorted()) from \(pointDescription(start)) to \(pointDescription(end)) has \(edge.orientations.count) uses with \(forwardCount) forward and \(reversedCount) reversed. Distinct curve-span records with the same endpoint pair: \(endpointPeers)."
          )
        }
      case .sheet:
        guard
          edge.orientations.count == 1
            || (edge.orientations.count == 2 && forwardCount == 1 && reversedCount == 1)
        else {
          throw KernelError(
            phase: .topology,
            code: .nonManifoldResult,
            tolerance: tolerance,
            message: "Sheet sewing edge use is non-manifold or inconsistently oriented."
          )
        }
      }
    }
  }

  private func topologyIdentity(
    featureID: FeatureID,
    bodyID: BodyID,
    bodyParents: [SubshapeID],
    faces: [FaceRecord],
    edges: [EdgeRecord],
    vertices: [VertexRecord]
  ) -> IdentityResult {
    var subshapes: [SubshapeID: TopologyReference] = [:]
    var drafts: [LineageDraft] = []
    let bodySubshape = SubshapeID(featureID: featureID, role: "body", ordinal: 0)
    subshapes[bodySubshape] = .body(bodyID)
    drafts.append(LineageDraft(output: bodySubshape, parents: bodyParents))
    for (ordinal, face) in faces.enumerated() {
      let subshape = SubshapeID(featureID: featureID, role: "face", ordinal: ordinal)
      subshapes[subshape] = .face(face.id)
      drafts.append(LineageDraft(output: subshape, parents: face.parents))
    }
    for (ordinal, edge) in edges.enumerated() {
      let subshape = SubshapeID(featureID: featureID, role: "edge", ordinal: ordinal)
      subshapes[subshape] = .edge(edge.id)
      drafts.append(LineageDraft(output: subshape, parents: Array(edge.parents).sorted()))
    }
    for (ordinal, vertex) in vertices.enumerated() {
      let subshape = SubshapeID(featureID: featureID, role: "vertex", ordinal: ordinal)
      subshapes[subshape] = .vertex(vertex.id)
      drafts.append(LineageDraft(output: subshape, parents: Array(vertex.parents).sorted()))
    }
    var parentUseCount: [SubshapeID: Int] = [:]
    for draft in drafts {
      for parent in draft.parents {
        parentUseCount[parent, default: 0] += 1
      }
    }
    let lineage = Dictionary(
      uniqueKeysWithValues: drafts.map { draft in
        let relation: TopologyLineageRelation
        if draft.parents.isEmpty {
          relation = .generated
        } else if draft.parents.count > 1 {
          relation = .merged
        } else if parentUseCount[draft.parents[0], default: 0] > 1 {
          relation = .split
        } else {
          relation = .preserved
        }
        let entry = TopologyLineage(
          output: draft.output,
          parents: draft.parents,
          relation: relation
        )
        return (draft.output, entry)
      })
    return IdentityResult(subshapes: subshapes, lineage: lineage)
  }

  private struct VertexRecord {
    let id: VertexID
    let point: Point3D
    var parents: Set<SubshapeID>
  }

  private struct SewingConnectivity {
    let endpointIDs: [String: EndpointVertexPair]
  }

  private struct EndpointVertexPair {
    let start: VertexID
    let end: VertexID
  }

  private struct EndpointSlotPair {
    let start: Int
    let end: Int
  }

  private struct EndpointSlot {
    let point: Point3D
    let parents: [SubshapeID]
    let stableKey: String
  }

  private struct InputEdgeUse {
    let edge: BRepSewingEdge
    let slots: EndpointSlotPair
  }

  private struct DisjointSet {
    private var parents: [Int]
    private var ranks: [UInt8]

    init(count: Int, using execution: inout OriginalQueryExecution) throws {
      try execution.retainStorage(count: count, stride: MemoryLayout<Int>.stride + MemoryLayout<UInt8>.stride)
      parents = Array(0..<count)
      ranks = Array(repeating: 0, count: count)
    }

    mutating func appendPair(using execution: inout OriginalQueryExecution) throws {
      try execution.consumeWork(1)
      try execution.retainStorage(count: 2, stride: MemoryLayout<Int>.stride + MemoryLayout<UInt8>.stride)
      parents.append(parents.count)
      ranks.append(0)
      parents.append(parents.count)
      ranks.append(0)
    }

    mutating func find(_ element: Int, using execution: inout OriginalQueryExecution) throws -> Int {
      try execution.consumeWork(1)
      if parents[element] != element {
        parents[element] = try find(parents[element], using: &execution)
      }
      return parents[element]
    }

    mutating func union(_ first: Int, _ second: Int, using execution: inout OriginalQueryExecution) throws {
      try execution.consumeWork(1)
      let firstRoot = try find(first, using: &execution)
      let secondRoot = try find(second, using: &execution)
      guard firstRoot != secondRoot else { return }
      if ranks[firstRoot] < ranks[secondRoot] {
        parents[firstRoot] = secondRoot
      } else if ranks[firstRoot] > ranks[secondRoot] {
        parents[secondRoot] = firstRoot
      } else {
        parents[secondRoot] = firstRoot
        ranks[firstRoot] += 1
      }
    }
  }

  private struct EdgeRecord {
    let id: EdgeID
    let startVertexID: VertexID
    let endVertexID: VertexID
    let span: CurveSpanDefinition
    var orientations: [Orientation]
    var parents: Set<SubshapeID>
    var stableIDs: Set<String>
    var patchStableIDs: Set<String>
  }

  private struct FaceRecord {
    let id: FaceID
    let parents: [SubshapeID]
  }

  private struct EdgeUse {
    let edgeID: EdgeID
    let orientation: Orientation
    let surfaceParameterCurve: SurfaceParameterCurve
  }

  private struct LineageDraft {
    let output: SubshapeID
    let parents: [SubshapeID]
  }

  private struct IdentityResult {
    let subshapes: [SubshapeID: TopologyReference]
    let lineage: [SubshapeID: TopologyLineage]
  }
  private func pointDescription(_ point: Point3D?) -> String {
#if hasFeature(Embedded)
    guard let point else { return "nil" }
    return "(\(point.x), \(point.y), \(point.z))"
#else
    return String(describing: point)
#endif
  }

}
