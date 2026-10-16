import CADCore
import CADGeometry
import CADIR
import CADTopology
import Foundation

public struct DefaultBooleanUVFaceSplitter: BooleanUVFaceSplitting {
  private struct RegisteredPairCurve: Hashable {
    let pair: BooleanFacePairCandidate
    let curveID: ExactCurveIdentity
  }

  private struct ContactProjectionCacheKey: Hashable {
    let curveID: ExactCurveIdentity
    let point: Point3D
  }

  private enum ContactProjectionCacheEntry {
    case parameter(Double)
    case noIntersection
  }

  private let facePointContainment: any FacePointContainmentTesting
  private let coincidentFaceOverlapTester: CoincidentFaceOverlapTester

  public init(
    facePointContainment: any FacePointContainmentTesting = DefaultFacePointContainmentTester()
  ) {
    self.facePointContainment = facePointContainment
    self.coincidentFaceOverlapTester = CoincidentFaceOverlapTester(
      facePointContainment: facePointContainment
    )
  }

  public func splitGraph(intersectionGraph: BooleanIntersectionGraph,
    model: BRepModel, tolerance: ModelingTolerance) throws -> BooleanUVSplitGraph {
    var execution = try OriginalQueryExecution.kernelOriginal()
    return try splitGraph(intersectionGraph: intersectionGraph, model: model,
      tolerance: tolerance, using: &execution)
  }

  public func splitGraph(
    intersectionGraph: BooleanIntersectionGraph,
    model: BRepModel,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BooleanUVSplitGraph {
    do {
      execution.context = execution.context.at(stage: .refinement)
      let graph = try resolve(using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return graph
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
    func resolve(using execution: inout OriginalQueryExecution) throws -> BooleanUVSplitGraph {
    try execution.consumeWork(1)
    do {
      try intersectionGraph.validate(in: model, tolerance: tolerance, using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: "input graph validation",
        tolerance: tolerance
      )
    }
    var splits: [BooleanFaceSplit] = []
    var containmentCache: [FacePointContainmentCacheKey: Bool] = [:]
    // Every pair sharing one intersection curve must split it at the
    // union of all pairs' contacts, or per-pair drift breaks junction
    // and sewing-twin identity.
    var curveIdentityRegistry = ExactCurveIdentityRegistry()
    var contactRegistry: [ExactCurveIdentity: [ClipContact]] = [:]
    var registeredPairCurves: Set<RegisteredPairCurve> = []
    var containmentPreparationCache = FacePointContainmentPreparationCache()
    var contactProjectionCache: [ContactProjectionCacheKey: ContactProjectionCacheEntry] = [:]
    // Phase 1: register every curved pair's clip contacts before any
    // pair clips. The registry is order-sensitive otherwise: a pair
    // clipping early would test intervals unbounded by contacts that
    // only later pairs discover, rejecting spans it partially owns.
    for pair in intersectionGraph.facePairs {
      guard let targetFace = model.faces[pair.targetFaceID],
        let toolFace = model.faces[pair.toolFaceID],
        let targetSurface = model.geometry.surfaces[targetFace.surfaceID],
        let toolSurface = model.geometry.surfaces[toolFace.surfaceID],
        try planeGeometry(
          targetSurface,
          tolerance: tolerance
        , using: &execution) == nil
          || planeGeometry(
            toolSurface,
            tolerance: tolerance
          , using: &execution) == nil
      else {
        continue
      }
      let pairContacts = try contacts(for: pair, in: intersectionGraph, using: &execution)
      for intersection in intersectionGraph.faceIntersections
      where intersection.facePair == pair {
        guard case .curve(let curveIntersection) = intersection.geometry else {
          continue
        }
        do {
          _ = try registerClipContacts(
            curveIntersection,
            at: pairContacts,
            pair: pair,
            targetSurface: targetSurface,
            toolSurface: toolSurface,
            model: model,
            containmentCache: &containmentCache,
            containmentPreparationCache: &containmentPreparationCache,
            curveIdentityRegistry: &curveIdentityRegistry,
            contactProjectionCache: &contactProjectionCache,
            contactRegistry: &contactRegistry,
            registeredPairCurves: &registeredPairCurves,
            tolerance: tolerance
          , using: &execution)
        } catch {
          throw contextualized(
            error,
            stage: "curved face-pair contact registration",
            tolerance: tolerance
          )
        }
      }
    }
    // Phase 1.5: unify registry contacts across curves. Distinct curves
    // recover one physical junction independently with micron-level
    // disagreement; clustering assigns each junction one canonical point
    // snapped onto source boundary geometry so segment endpoints, graph
    // nodes, and sewing twins coincide exactly.
    try canonicalizeRegistryContacts(
      intersectionGraph: intersectionGraph,
      model: model,
      contactRegistry: &contactRegistry,
      tolerance: tolerance
    , using: &execution)
    for pair in intersectionGraph.facePairs {
      guard let targetFace = model.faces[pair.targetFaceID],
        let toolFace = model.faces[pair.toolFaceID],
        let targetSurface = model.geometry.surfaces[targetFace.surfaceID],
        let toolSurface = model.geometry.surfaces[toolFace.surfaceID]
      else {
        throw KernelError(
          phase: .topology,
          code: .missingReference,
          tolerance: tolerance,
          message: "Boolean UV splitting references missing face geometry."
        )
      }
      guard
        let targetPlane = try planeGeometry(
          targetSurface,
          tolerance: tolerance
        , using: &execution),
        let toolPlane = try planeGeometry(
          toolSurface,
          tolerance: tolerance
        , using: &execution)
      else {
        do {
          if let curvedSplit = try curvedSplit(
            pair: pair,
            intersectionGraph: intersectionGraph,
            targetSurface: targetSurface,
            toolSurface: toolSurface,
            model: model,
            containmentCache: &containmentCache,
            containmentPreparationCache: &containmentPreparationCache,
            curveIdentityRegistry: &curveIdentityRegistry,
            contactProjectionCache: &contactProjectionCache,
            contactRegistry: &contactRegistry,
            registeredPairCurves: &registeredPairCurves,
            tolerance: tolerance
          , using: &execution) {
            try OriginalParameterQueryStorage.append(curvedSplit, to: &splits, using: &execution)
          }
        } catch {
          throw contextualized(
            error,
            stage: "curved face-pair clipping",
            tolerance: tolerance
          )
        }
        continue
      }
      let lineDirection = targetPlane.normal.cross(toolPlane.normal)
      let contacts = try contacts(for: pair, in: intersectionGraph, using: &execution)
      if lineDirection.length <= tolerance.angle {
        let separation = abs((toolPlane.origin - targetPlane.origin).dot(targetPlane.normal))
        if separation <= tolerance.distance,
          contacts.contains(where: {
            if case .coincident = $0.geometry { return true }
            return false
          }),
          try coincidentFaceOverlapTester.overlapsOrTouches(
            pair.targetFaceID,
            pair.toolFaceID,
            in: model,
            tolerance: tolerance
          , using: &execution)
        {
          try OriginalParameterQueryStorage.append(
            try split(
              facePair: pair,
              geometries: [.coincident],
              tolerance: tolerance
            , using: &execution), to: &splits, using: &execution)
        }
        continue
      }
      let points = try clippedPoints(
        contacts: contacts,
        pair: pair,
        targetSurface: targetSurface,
        toolSurface: toolSurface,
        model: model,
        containmentCache: &containmentCache,
        containmentPreparationCache: &containmentPreparationCache,
        tolerance: tolerance
      , using: &execution)
      guard points.isEmpty == false else { continue }
      let direction = try lineDirection.normalized(tolerance: tolerance.distance)
      let ordered = points.sorted {
        vector($0.point).dot(direction) < vector($1.point).dot(direction)
      }
      var geometries: [BooleanFaceSplitComponentGeometry] = []
      var incident = Array(repeating: false, count: ordered.count)
      for index in ordered.indices.dropLast() {
        let first = ordered[index]
        let last = ordered[index + 1]
        guard (first.point - last.point).length > tolerance.distance else { continue }
        let midpoint = first.point + (last.point - first.point) * 0.5
        // All original boundary events have been isolated. Material membership
        // is constant on each open interval, including intervals across holes.
        if try contains(midpoint, faceID: pair.targetFaceID, surface: targetSurface,
            model: model, cache: &containmentCache, preparationCache: &containmentPreparationCache,
            tolerance: tolerance, using: &execution),
           try contains(midpoint, faceID: pair.toolFaceID, surface: toolSurface,
            model: model, cache: &containmentCache, preparationCache: &containmentPreparationCache,
            tolerance: tolerance, using: &execution) {
          try OriginalParameterQueryStorage.append(.transverseSegment(start: first, end: last), to: &geometries, using: &execution)
          incident[index] = true
          incident[index + 1] = true
        }
      }
      for index in ordered.indices where !incident[index] {
        try OriginalParameterQueryStorage.append(.tangent(ordered[index]), to: &geometries, using: &execution)
      }
      if !geometries.isEmpty {
        try OriginalParameterQueryStorage.append(try split(facePair: pair, geometries: geometries, tolerance: tolerance, using: &execution), to: &splits, using: &execution)
      }
    }
    let graph = BooleanUVSplitGraph(splits: splits)
    try graph.validate(intersectionGraph: intersectionGraph, model: model, tolerance: tolerance, using: &execution)
    return graph
      }
  }

  private func contextualized(
      _ error: any Error,
      stage: String,
      tolerance: ModelingTolerance
  ) -> any Error {
      let wrapped = KernelError.wrapping(error, phase: .topology, tolerance: tolerance)
      let classification = KernelError(
          phase: wrapped.phase,
          code: wrapped.code,
          featureID: wrapped.featureID,
          subshapeID: wrapped.subshapeID,
          residual: wrapped.residual,
          tolerance: wrapped.tolerance ?? tolerance,
          message: "Boolean UV face splitting \(stage) failed: \(wrapped.message)"
      )
      return OriginalQueryFailure.contextualizing(error, classification: classification)
  }

  private func planeGeometry(
    _ surface: Surface3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> (origin: Point3D, normal: Vector3D)? {
    try execution.consumeWork(1)
    guard
      let plane = try DefaultPlanarSurfaceResolver().exactPlane(
        for: surface,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    return (plane.origin, plane.normal)
  }

  private func contacts(
    for pair: BooleanFacePairCandidate,
    in graph: BooleanIntersectionGraph
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [BooleanBoundaryContact] {
    try execution.consumeWork(1)
    try execution.consumeWork(graph.boundaryContacts.count)
    try execution.retainKernelValues(count: graph.boundaryContacts.count,
      stride: MemoryLayout<BooleanBoundaryContact>.stride)
    return graph.boundaryContacts.filter { contact in
      (contact.curveFaceID == pair.targetFaceID && contact.surfaceFaceID == pair.toolFaceID)
        || (contact.curveFaceID == pair.toolFaceID && contact.surfaceFaceID == pair.targetFaceID)
    }
  }

  private func curvedSplit(
    pair: BooleanFacePairCandidate,
    intersectionGraph: BooleanIntersectionGraph,
    targetSurface: Surface3D,
    toolSurface: Surface3D,
    model: BRepModel,
    containmentCache: inout [FacePointContainmentCacheKey: Bool],
    containmentPreparationCache: inout FacePointContainmentPreparationCache,
    curveIdentityRegistry: inout ExactCurveIdentityRegistry,
    contactProjectionCache: inout [ContactProjectionCacheKey: ContactProjectionCacheEntry],
    contactRegistry: inout [ExactCurveIdentity: [ClipContact]],
    registeredPairCurves: inout Set<RegisteredPairCurve>,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BooleanFaceSplit? {
    try execution.consumeWork(1)
    let intersections = intersectionGraph.faceIntersections.filter { $0.facePair == pair }
    guard intersections.isEmpty == false else { return nil }
    if intersections.contains(where: {
      if case .coincident = $0.geometry { return true }
      return false
    }) {
      guard intersections.count == 1 else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "A coincident face pair cannot also contain discrete intersections."
        )
      }
      guard
        try coincidentFaceOverlapTester.overlapsOrTouches(
          pair.targetFaceID,
          pair.toolFaceID,
          in: model,
          tolerance: tolerance
        , using: &execution)
      else {
        return nil
      }
      return try split(
        facePair: pair,
        geometries: [.coincident],
        tolerance: tolerance
      , using: &execution)
    }

    let pairContacts = try contacts(for: pair, in: intersectionGraph, using: &execution)
    var geometries: [BooleanFaceSplitComponentGeometry] = []
    for intersection in intersections {
      switch intersection.geometry {
      // FIXME(INCOMPLETE_IMPLEMENTATION): The finite face splitter still needs
      // exact source-relation/material refinement for symbolic SSI; numeric
      // pcurve clipping must not discard the retained all-UV owner.
      case .originalCoaxial, .originalBoundedSphereCone, .originalFullSphereCone, .originalFullConeCone, .originalApexSphereCone, .originalCommonApexCone, .originalCoincidentCone:
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
          message: "Finite face splitting requires original symbolic material refinement.")
      case .coincident:
        break
      case .point(let point):
        do {
          guard
            try containsSurfaceParameter(
              SurfaceParameter(
                u: point.firstSurfaceParameter.u,
                v: point.firstSurfaceParameter.v
              ),
              fallbackPoint: point.point,
              faceID: pair.targetFaceID,
              surface: targetSurface,
              model: model,
              cache: &containmentCache,
              preparationCache: &containmentPreparationCache,
              tolerance: tolerance
            , using: &execution),
            try containsSurfaceParameter(
              SurfaceParameter(
                u: point.secondSurfaceParameter.u,
                v: point.secondSurfaceParameter.v
              ),
              fallbackPoint: point.point,
              faceID: pair.toolFaceID,
              surface: toolSurface,
              model: model,
              cache: &containmentCache,
              preparationCache: &containmentPreparationCache,
              tolerance: tolerance
            , using: &execution)
          else {
            continue
          }
          try OriginalParameterQueryStorage.append(
            .tangent(
              try booleanUVPoint(
                point,
                targetSurface: targetSurface,
                toolSurface: toolSurface,
                tolerance: tolerance
              , using: &execution)), to: &geometries, using: &execution)
        } catch {
          throw contextualized(
            error,
            stage: "isolated curved face-pair point classification",
            tolerance: tolerance
          )
        }
      case .curve(let curveIntersection):
        let clipped: CurvedClipResult
        do {
          clipped = try clip(
            curveIntersection,
            at: pairContacts,
            pair: pair,
            targetSurface: targetSurface,
            toolSurface: toolSurface,
            model: model,
            containmentCache: &containmentCache,
            containmentPreparationCache: &containmentPreparationCache,
            curveIdentityRegistry: &curveIdentityRegistry,
            contactProjectionCache: &contactProjectionCache,
            contactRegistry: &contactRegistry,
            registeredPairCurves: &registeredPairCurves,
            tolerance: tolerance
          , using: &execution)
        } catch {
          throw contextualized(
            error,
            stage: "curved face-pair intersection-curve clipping",
            tolerance: tolerance
          )
        }
        switch clipped {
        case .empty:
          break
        case .closed(let value):
          try OriginalParameterQueryStorage.append(.closedCurve(value), to: &geometries, using: &execution)
        case .trimmed(let values):
          try OriginalParameterQueryStorage.append(contentsOf: values.map(BooleanFaceSplitComponentGeometry.trimmedCurve), to: &geometries, using: &execution)
        }
      }
    }
    guard geometries.isEmpty == false else { return nil }
    return try split(
      facePair: pair,
      geometries: geometries,
      tolerance: tolerance
    , using: &execution)
  }

  private func split(
    facePair: BooleanFacePairCandidate,
    geometries: [BooleanFaceSplitComponentGeometry],
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BooleanFaceSplit {
    try execution.consumeWork(1)
    guard geometries.isEmpty == false else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Boolean face split requires at least one geometric component."
      )
    }
    let sorted = geometries.map { geometry in
      (geometry: geometry, key: componentSortKey(geometry))
    }.sorted { lhs, rhs in
      lhs.key.lexicographicallyPrecedes(rhs.key)
    }
    for index in 1..<sorted.count where sorted[index - 1].key == sorted[index].key {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Boolean split components have indistinguishable deterministic geometry keys."
      )
    }
    return BooleanFaceSplit(
      facePair: facePair,
      components: sorted.enumerated().map { ordinal, record in
        BooleanFaceSplitComponent(
          id: BooleanFaceSplitComponentID(ordinal: ordinal),
          geometry: record.geometry
        )
      }
    )
  }

  private func componentSortKey(
    _ geometry: BooleanFaceSplitComponentGeometry
  ) -> [Double] {
    switch geometry {
    case .transverseSegment(let start, let end):
      return [0.0] + orderedPointKey(start.point, end.point)
    case .closedCurve(let curve):
      let points = curve.samples.map(\.uvPoint.point)
      let minimum = points.min(by: lexicographicPointOrder) ?? .origin
      let maximum = points.max(by: lexicographicPointOrder) ?? .origin
      let count = Double(max(points.count, 1))
      let centroid = Point3D(
        x: points.reduce(0.0) { $0 + $1.x } / count,
        y: points.reduce(0.0) { $0 + $1.y } / count,
        z: points.reduce(0.0) { $0 + $1.z } / count
      )
      return [1.0, Double(points.count)]
        + pointKey(minimum)
        + pointKey(maximum)
        + pointKey(centroid)
        + points.sorted(by: lexicographicPointOrder).flatMap(pointKey)
    case .trimmedCurve(let chain):
      let midpoint = Point3D(
        x: (chain.start.point.x + chain.end.point.x) * 0.5,
        y: (chain.start.point.y + chain.end.point.y) * 0.5,
        z: (chain.start.point.z + chain.end.point.z) * 0.5
      )
      return [2.0, Double(chain.segments.count)]
        + orderedPointKey(chain.start.point, chain.end.point)
        + pointKey(midpoint)
        + chain.segments.flatMap {
          [$0.startParameter, $0.endParameter]
        }
    case .tangent(let point):
      return [3.0] + pointKey(point.point)
    case .coincident:
      return [4.0]
    }
  }

  private func orderedPointKey(_ first: Point3D, _ second: Point3D) -> [Double] {
    if lexicographicPointOrder(first, second) {
      return pointKey(first) + pointKey(second)
    }
    return pointKey(second) + pointKey(first)
  }

  private func lexicographicPointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
    pointKey(lhs).lexicographicallyPrecedes(pointKey(rhs))
  }

  private func pointKey(_ point: Point3D) -> [Double] {
    [point.x, point.y, point.z]
  }

  private func canonicalizeRegistryContacts(
    intersectionGraph: BooleanIntersectionGraph,
    model: BRepModel,
    contactRegistry: inout [ExactCurveIdentity: [ClipContact]],
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)
    let snapDistance = tolerance.distance * 8.0
    var vertexPoints: [Point3D] = []
    var boundaryEdges: [(curve: Curve3D, lower: Double, upper: Double)] = []
    var seenFaces: Set<FaceID> = []
    for pair in intersectionGraph.facePairs {
      for faceID in [pair.targetFaceID, pair.toolFaceID]
      where seenFaces.contains(faceID) == false {
        seenFaces.insert(faceID)
        guard let face = model.faces[faceID] else { continue }
        for loopID in face.loops {
          guard let loop = model.loops[loopID] else { continue }
          for coedge in loop.coedges {
            guard let edge = model.edges[coedge.edgeID],
              let curve = model.geometry.curves[edge.curveID]
            else {
              continue
            }
            if let start = model.vertices[edge.startVertexID] {
              try OriginalParameterQueryStorage.append(start.point, to: &vertexPoints, using: &execution)
            }
            if let end = model.vertices[edge.endVertexID] {
              try OriginalParameterQueryStorage.append(end.point, to: &vertexPoints, using: &execution)
            }
            guard let trim = edge.trim else { continue }
            try OriginalParameterQueryStorage.append(
              (
                curve: curve,
                lower: min(trim.startParameter, trim.endParameter),
                upper: max(trim.startParameter, trim.endParameter)
              ), to: &boundaryEdges, using: &execution)
          }
        }
      }
    }
    func lexicographicallyPrecedes(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
      [lhs.x, lhs.y, lhs.z].lexicographicallyPrecedes([rhs.x, rhs.y, rhs.z])
    }
    func nearestSourceSnap(
      _ point: Point3D
    ) throws -> (point: Point3D, distance: Double)? {
      var best: (point: Point3D, distance: Double)? = nil
      for vertex in vertexPoints {
        let distance = (vertex - point).length
        guard distance <= snapDistance else { continue }
        if let current = best {
          if distance < current.distance
            || (distance == current.distance
              && lexicographicallyPrecedes(vertex, current.point))
          {
            best = (vertex, distance)
          }
        } else {
          best = (vertex, distance)
        }
      }
      if let best { return best }
      for boundary in boundaryEdges {
        let foot: Point3D
        do {
          let interval = try ScalarInterval(
            lower: boundary.lower,
            upper: boundary.upper
          )
          // Projection acceptance is tied to the tolerance's
          // distance; candidate points sit up to the snap bound
          // off the boundary, so the projection runs widened.
          let projection = try boundary.curve.parameterProjection(
            of: point,
            options: CurveParameterProjectionOptions(parameterRange: interval),
            tolerance: ModelingTolerance(
              distance: snapDistance,
              angle: tolerance.angle,
              relative: tolerance.relative
            )
          , using: &execution)
          foot = try boundary.curve.point(
            at: projection.parameter,
            tolerance: tolerance
          , using: &execution)
        } catch let error as KernelError where error.code == .intersectionFailure {
          continue
        }
        let distance = (foot - point).length
        guard distance <= snapDistance else { continue }
        if let current = best {
          if distance < current.distance
            || (distance == current.distance
              && lexicographicallyPrecedes(foot, current.point))
          {
            best = (foot, distance)
          }
        } else {
          best = (foot, distance)
        }
      }
      return best
    }
    var entries: [(key: ExactCurveIdentity, index: Int, point: Point3D, isRecovered: Bool)] = []
    for (key, contacts) in contactRegistry {
      for (index, contact) in contacts.enumerated() {
        try OriginalParameterQueryStorage.append(
          (
            key: key,
            index: index,
            point: contact.point,
            isRecovered: contact.isRecovered
          ), to: &entries, using: &execution)
      }
    }
    entries.sort { lhs, rhs in
      if lhs.point == rhs.point {
        return (lhs.key, lhs.index) < (rhs.key, rhs.index)
      }
      return lexicographicallyPrecedes(lhs.point, rhs.point)
    }
    // Projection contacts are exact intersections and never move; only
    // containment-recovered contacts carry micron-level error, so only
    // they cluster, anchor onto a nearby projection contact when one
    // exists, and otherwise snap onto source geometry.
    var representatives: [Point3D] = []
    var clusterMembers:
      [Int: [(key: ExactCurveIdentity, index: Int, point: Point3D, isRecovered: Bool)]] = [:]
    for entry in entries {
      var clusterIndex: Int? = nil
      if entry.isRecovered {
        for (index, representative) in representatives.enumerated()
        where (representative - entry.point).length <= snapDistance {
          clusterIndex = index
          break
        }
      }
      let resolvedIndex: Int
      if let clusterIndex {
        resolvedIndex = clusterIndex
      } else {
        try OriginalParameterQueryStorage.append(entry.point, to: &representatives, using: &execution)
        resolvedIndex = representatives.count - 1
      }
      if clusterMembers[resolvedIndex] == nil {
        try OriginalParameterQueryStorage.set([], for: resolvedIndex, in: &clusterMembers, using: &execution)
      }
      try OriginalParameterQueryStorage.append(entry,
        to: &clusterMembers[resolvedIndex, default: []], using: &execution)
    }
    for (clusterIndex, members) in clusterMembers.sorted(by: { $0.key < $1.key }) {
      guard members.contains(where: \.isRecovered) else { continue }
      var canonical: Point3D? = nil
      for member in members where member.isRecovered == false {
        if let current = canonical {
          if lexicographicallyPrecedes(member.point, current) {
            canonical = member.point
          }
        } else {
          canonical = member.point
        }
      }
      if canonical == nil {
        // No projection anchor: nearby projection contacts outside
        // this cluster still anchor recovered points, else source
        // geometry does, else the representative unifies members.
        let representative = representatives[clusterIndex]
        var anchor: Point3D? = nil
        for entry in entries
        where entry.isRecovered == false
          && (entry.point - representative).length <= snapDistance
        {
          if let current = anchor {
            if (entry.point - representative).length
              < (current - representative).length
            {
              anchor = entry.point
            }
          } else {
            anchor = entry.point
          }
        }
        if let anchor {
          canonical = anchor
        } else if let snap = try nearestSourceSnap(representative) {
          canonical = snap.point
        } else if members.count > 1 {
          canonical = representative
        }
      }
      guard let canonical else { continue }
      for member in members {
        guard let existing = contactRegistry[member.key]?[member.index] else {
          continue
        }
        contactRegistry[member.key]?[member.index] = ClipContact(
          parameter: existing.parameter,
          point: canonical,
          isRecovered: existing.isRecovered
        )
      }
    }
  }

  // Contact computation is separated from clipping so splitGraph can
  // register every pair's contacts before any pair clips: the registry
  // must be complete when the first pair consumes it, or clipping order
  // starves earlier pairs of later pairs' crossing boundaries.
  private func registerClipContacts(
    _ intersection: SurfaceSurfaceIntersectionCurve,
    at boundaryContacts: [BooleanBoundaryContact],
    pair: BooleanFacePairCandidate,
    targetSurface: Surface3D,
    toolSurface: Surface3D,
    model: BRepModel,
    containmentCache: inout [FacePointContainmentCacheKey: Bool],
    containmentPreparationCache: inout FacePointContainmentPreparationCache,
    curveIdentityRegistry: inout ExactCurveIdentityRegistry,
    contactProjectionCache: inout [ContactProjectionCacheKey: ContactProjectionCacheEntry],
    contactRegistry: inout [ExactCurveIdentity: [ClipContact]],
    registeredPairCurves: inout Set<RegisteredPairCurve>,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [ClipContact] {
    try execution.consumeWork(1)
    let curve = intersection.curve
    let registryKey = try curveIdentityRegistry.identity(for: curve, using: &execution)
    let pairCurveKey = RegisteredPairCurve(pair: pair, curveID: registryKey)
    if registeredPairCurves.contains(pairCurveKey) {
      return contactRegistry[registryKey] ?? []
    }
    var contacts: [ClipContact] = []
    let contactRefiner = RectangularBooleanClipContactRefiner()
    for boundaryContact in boundaryContacts {
      guard case .points(let points) = boundaryContact.geometry else { continue }
      for pointContact in points {
        let point = pointContact.point
        let key = ContactProjectionCacheKey(
          curveID: registryKey,
          point: point
        )
        let projectedParameter: Double
        if let cached = contactProjectionCache[key] {
          guard case .parameter(let parameter) = cached else { continue }
          projectedParameter = parameter
        } else {
          do {
            let projection = try curve.parameterProjection(
              of: point,
              tolerance: tolerance
            , using: &execution)
            contactProjectionCache[key] = .parameter(projection.parameter)
            projectedParameter = projection.parameter
          } catch let error as KernelError where error.code == .intersectionFailure {
            contactProjectionCache[key] = .noIntersection
            continue
          } catch {
            let wrapped = KernelError.wrapping(
              error,
              phase: .geometry,
              tolerance: tolerance
            )
            let classification = KernelError(
              phase: wrapped.phase,
              code: wrapped.code,
              residual: wrapped.residual,
              tolerance: wrapped.tolerance ?? tolerance,
              message: "Boolean intersection contact projection failed: \(wrapped.message)"
            )
            throw OriginalQueryFailure.contextualizing(error, classification: classification)
          }
        }
        if let refined = try contactRefiner.refine(
          parameter: projectedParameter,
          intersection: intersection,
          boundaryFaceID: boundaryContact.curveFaceID,
          boundaryEdgeID: boundaryContact.edgeID,
          pair: pair,
          model: model,
          tolerance: tolerance
        , using: &execution) {
          try OriginalParameterQueryStorage.append(
            ClipContact(
              parameter: refined.parameter,
              point: refined.point
            ), to: &contacts, using: &execution)
        } else {
          try OriginalParameterQueryStorage.append(
            ClipContact(
              parameter: projectedParameter,
              point: point
            ), to: &contacts, using: &execution)
        }
      }
    }
    contacts = try deduplicatedContacts(
      contacts,
      domain: curve.parameterDomain,
      tolerance: tolerance
    , using: &execution)
    // Boundary contacts are certified curve-surface events produced by
    // BooleanPipeline. A containment-state scan is neither a completeness
    // proof nor a valid source of topology: it can miss a narrow interval
    // and manufactures approximate twin contacts around tangencies.
    // Merge with the cross-pair registry so every pair splits this
    // curve at the identical canonical contact set.
    var merged = contactRegistry[registryKey] ?? []
    try OriginalParameterQueryStorage.append(contentsOf: contacts, to: &merged, using: &execution)
    merged = try deduplicatedContacts(
      merged,
      domain: curve.parameterDomain,
      tolerance: tolerance
    , using: &execution).sorted { $0.parameter < $1.parameter }
    contactRegistry[registryKey] = merged
    registeredPairCurves.insert(pairCurveKey)
    return merged
  }

  private func clip(
    _ intersection: SurfaceSurfaceIntersectionCurve,
    at boundaryContacts: [BooleanBoundaryContact],
    pair: BooleanFacePairCandidate,
    targetSurface: Surface3D,
    toolSurface: Surface3D,
    model: BRepModel,
    containmentCache: inout [FacePointContainmentCacheKey: Bool],
    containmentPreparationCache: inout FacePointContainmentPreparationCache,
    curveIdentityRegistry: inout ExactCurveIdentityRegistry,
    contactProjectionCache: inout [ContactProjectionCacheKey: ContactProjectionCacheEntry],
    contactRegistry: inout [ExactCurveIdentity: [ClipContact]],
    registeredPairCurves: inout Set<RegisteredPairCurve>,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> CurvedClipResult {
    try execution.consumeWork(1)
    let curve = intersection.curve
    let contacts: [ClipContact]
    do {
      contacts = try registerClipContacts(
        intersection,
        at: boundaryContacts,
        pair: pair,
        targetSurface: targetSurface,
        toolSurface: toolSurface,
        model: model,
        containmentCache: &containmentCache,
        containmentPreparationCache: &containmentPreparationCache,
        curveIdentityRegistry: &curveIdentityRegistry,
        contactProjectionCache: &contactProjectionCache,
        contactRegistry: &contactRegistry,
        registeredPairCurves: &registeredPairCurves,
        tolerance: tolerance
      , using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: "intersection-curve contact registration",
        tolerance: tolerance
      )
    }
    if contacts.count < 2 {
      switch curve.parameterDomain {
      case .periodic(let period):
        return try completeClosedClip(
          intersection,
          lowerParameter: 0.0,
          upperParameter: period,
          pair: pair,
          targetSurface: targetSurface,
          toolSurface: toolSurface,
          model: model,
          containmentCache: &containmentCache,
          containmentPreparationCache: &containmentPreparationCache,
          tolerance: tolerance
        , using: &execution)
      case .closed(let lower, let upper):
        if try closesAtBoundedDomainBoundary(
          intersection,
          lower: lower,
          upper: upper,
          tolerance: tolerance
        , using: &execution) {
          return try completeClosedClip(
            intersection,
            lowerParameter: lower,
            upperParameter: upper,
            pair: pair,
            targetSurface: targetSurface,
            toolSurface: toolSurface,
            model: model,
            containmentCache: &containmentCache,
            containmentPreparationCache: &containmentPreparationCache,
            tolerance: tolerance
          , using: &execution)
        }
      case .unbounded:
        break
      }
    }

    var boundaries = contacts.map(\.parameter)
    switch curve.parameterDomain {
    case .closed(let lower, let upper):
      try OriginalParameterQueryStorage.append(contentsOf: [lower, upper], to: &boundaries, using: &execution)
    case .periodic, .unbounded:
      break
    }
    boundaries = try deduplicatedParameters(
      boundaries,
      domain: curve.parameterDomain,
      tolerance: tolerance
    , using: &execution).sorted()
    guard boundaries.count >= 2 else { return .empty }

    var intervals = Array(zip(boundaries, boundaries.dropFirst()))
    if case .periodic(let period) = curve.parameterDomain,
      let first = boundaries.first,
      let last = boundaries.last
    {
      try OriginalParameterQueryStorage.append((last, first + period), to: &intervals, using: &execution)
    }
    var result: [TrimmedIntervalRecord] = []
    for (intervalOrdinal, interval) in intervals.enumerated() {
      let (lower, upper) = interval
      guard upper - lower > tolerance.angle else { continue }
      let midpoint = lower + (upper - lower) * 0.5
      let midpointIsContained: Bool
      do {
        let evaluation =
          try intersection
          .evaluatedCorrespondenceAssumingValidated(
            atCurveParameter: midpoint,
            firstSurface: targetSurface,
            secondSurface: toolSurface,
            tolerance: tolerance
          )
        midpointIsContained = try containsIntersection(
          evaluation,
          pair: pair,
          targetSurface: targetSurface,
          toolSurface: toolSurface,
          model: model,
          cache: &containmentCache,
          preparationCache: &containmentPreparationCache,
          tolerance: tolerance
        , using: &execution)
      } catch {
        throw contextualized(
          error,
          stage:
            "trimmed intersection interval \(intervalOrdinal) midpoint containment at curve parameter \(midpoint)",
          tolerance: tolerance
        )
      }
      guard midpointIsContained else { continue }
      let startContact = try contactPoint(
        at: lower,
        contacts: contacts,
        domain: curve.parameterDomain,
        tolerance: tolerance
      , using: &execution)
      let endContact = try contactPoint(
        at: upper,
        contacts: contacts,
        domain: curve.parameterDomain,
        tolerance: tolerance
      , using: &execution)
      let startPoint: Point3D
      if let startContact {
        startPoint = startContact
      } else {
        startPoint = try curve.pointAssumingValid(
          at: lower,
          tolerance: tolerance
        , using: &execution)
      }
      let endPoint: Point3D
      if let endContact {
        endPoint = endContact
      } else {
        endPoint = try curve.pointAssumingValid(
          at: upper,
          tolerance: tolerance
        , using: &execution)
      }
      do {
        try OriginalParameterQueryStorage.append(
          TrimmedIntervalRecord(
            ordinal: intervalOrdinal,
            segment: try BooleanTrimmedFaceIntersection(
              intersection: intersection,
              startParameter: lower,
              endParameter: upper,
              start: try booleanUVPoint(
                startPoint,
                atCurveParameter: lower,
                intersection: intersection,
                targetSurface: targetSurface,
                toolSurface: toolSurface,
                tolerance: tolerance
              , using: &execution),
              end: try booleanUVPoint(
                endPoint,
                atCurveParameter: upper,
                intersection: intersection,
                targetSurface: targetSurface,
                toolSurface: toolSurface,
                tolerance: tolerance
              , using: &execution),
              tolerance: tolerance
            )
          ), to: &result, using: &execution)
      } catch {
        throw contextualized(
          error,
          stage:
            "trimmed intersection interval \(intervalOrdinal) endpoint construction over [\(lower), \(upper)]",
          tolerance: tolerance
        )
      }
    }
    // Containment state cannot change across the artificial seam of a
    // closed loop unless the seam itself is a contact, so a rejected
    // seam-adjacent sliver inherits its seam neighbor's kept state.
    if case .closed(let domainLower, let domainUpper) = curve.parameterDomain,
      let firstBoundary = boundaries.first,
      let lastBoundary = boundaries.last,
      abs(firstBoundary - domainLower) <= tolerance.angle,
      abs(lastBoundary - domainUpper) <= tolerance.angle,
      contacts.contains(where: {
        abs($0.parameter - domainLower) <= tolerance.angle
          || abs($0.parameter - domainUpper) <= tolerance.angle
      }) == false,
      try closesAtBoundedDomainBoundary(
        intersection,
        lower: domainLower,
        upper: domainUpper,
        tolerance: tolerance
      , using: &execution)
    {
      let keptOrdinals = Set(result.map(\.ordinal))
      let lastOrdinal = intervals.count - 1
      for (missing, neighbor) in [(0, lastOrdinal), (lastOrdinal, 0)]
      where keptOrdinals.contains(neighbor)
        && keptOrdinals.contains(missing) == false
      {
        let (lower, upper) = intervals[missing]
        guard upper - lower > tolerance.angle else { continue }
        try OriginalParameterQueryStorage.append(
          TrimmedIntervalRecord(
            ordinal: missing,
            segment: try BooleanTrimmedFaceIntersection(
              intersection: intersection,
              startParameter: lower,
              endParameter: upper,
              start: try booleanUVPoint(
                contactPoint(
                  at: lower,
                  contacts: contacts,
                  domain: curve.parameterDomain,
                  tolerance: tolerance
                , using: &execution)
                  ?? curve.pointAssumingValid(
                    at: lower,
                    tolerance: tolerance
                  , using: &execution),
                atCurveParameter: lower,
                intersection: intersection,
                targetSurface: targetSurface,
                toolSurface: toolSurface,
                tolerance: tolerance
              , using: &execution),
              end: try booleanUVPoint(
                contactPoint(
                  at: upper,
                  contacts: contacts,
                  domain: curve.parameterDomain,
                  tolerance: tolerance
                , using: &execution)
                  ?? curve.pointAssumingValid(
                    at: upper,
                    tolerance: tolerance
                  , using: &execution),
                atCurveParameter: upper,
                intersection: intersection,
                targetSurface: targetSurface,
                toolSurface: toolSurface,
                tolerance: tolerance
              , using: &execution),
              tolerance: tolerance
            )
          ), to: &result, using: &execution)
      }
      result.sort { $0.ordinal < $1.ordinal }
    }
    guard result.isEmpty == false else { return .empty }
    let joinsDomainSeam: Bool
    switch curve.parameterDomain {
    case .periodic:
      joinsDomainSeam = true
    case .closed(let lower, let upper):
      joinsDomainSeam = try closesAtBoundedDomainBoundary(
        intersection,
        lower: lower,
        upper: upper,
        tolerance: tolerance
      , using: &execution)
    case .unbounded:
      joinsDomainSeam = false
    }
    do {
      return .trimmed(
        try trimmedChains(
          result,
          intervalCount: intervals.count,
          joinsDomainSeam: joinsDomainSeam,
          tolerance: tolerance
        , using: &execution))
    } catch {
      throw contextualized(
        error,
        stage: "trimmed intersection chain assembly",
        tolerance: tolerance
      )
    }
  }

  private func trimmedChains(
    _ records: [TrimmedIntervalRecord],
    intervalCount: Int,
    joinsDomainSeam: Bool,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [BooleanTrimmedFaceIntersectionChain] {
    try execution.consumeWork(1)
    var remaining = records
    var result: [BooleanTrimmedFaceIntersectionChain] = []
    if joinsDomainSeam,
      remaining.count >= 2,
      remaining.first?.ordinal == 0,
      remaining.last?.ordinal == intervalCount - 1
    {
      let first = remaining.removeFirst().segment
      let last = remaining.removeLast().segment
      try OriginalParameterQueryStorage.append(
        try BooleanTrimmedFaceIntersectionChain(
          segments: [last, first],
          tolerance: tolerance
        ), to: &result, using: &execution)
    }
    try OriginalParameterQueryStorage.append(
      contentsOf: try remaining.map {
        try BooleanTrimmedFaceIntersectionChain(
          segments: [$0.segment],
          tolerance: tolerance
        )
      }, to: &result, using: &execution)
    return result
  }

  private func closesAtBoundedDomainBoundary(
    _ intersection: SurfaceSurfaceIntersectionCurve,
    lower: Double,
    upper: Double,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    if let certifiedClosure = intersection.truth.certifiedComponentClosure {
      return certifiedClosure
    }
    let start = try intersection.curve.pointAssumingValid(
      at: lower,
      tolerance: tolerance
    , using: &execution)
    let end = try intersection.curve.pointAssumingValid(
      at: upper,
      tolerance: tolerance
    , using: &execution)
    return start.isApproximatelyEqual(to: end, tolerance: tolerance.distance)
  }

  private func completeClosedClip(
    _ intersection: SurfaceSurfaceIntersectionCurve,
    lowerParameter: Double,
    upperParameter: Double,
    pair: BooleanFacePairCandidate,
    targetSurface: Surface3D,
    toolSurface: Surface3D,
    model: BRepModel,
    containmentCache: inout [FacePointContainmentCacheKey: Bool],
    containmentPreparationCache: inout FacePointContainmentPreparationCache,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> CurvedClipResult {
    try execution.consumeWork(1)
    // Fewer than two contacts on a closed component means the complete
    // curve-surface event sets contain no transverse boundary crossing.
    // These samples materialize a secondary parameter-space index; they
    // do not establish containment. Their states instead audit the event
    // completeness contract and must agree globally.
    let polygonSampleCount = 32
    var samples: [BooleanCurveUVSample] = []
    var certifiedContainment: Bool?
    for index in 0..<polygonSampleCount {
      let parameter =
        lowerParameter
        + (upperParameter - lowerParameter)
        * Double(index) / Double(polygonSampleCount)
      do {
        let evaluation =
          try intersection
          .evaluatedCorrespondenceAssumingValidated(
            atCurveParameter: parameter,
            firstSurface: targetSurface,
            secondSurface: toolSurface,
            tolerance: tolerance
          )
        let isContained = try containsIntersection(
          evaluation,
          pair: pair,
          targetSurface: targetSurface,
          toolSurface: toolSurface,
          model: model,
          cache: &containmentCache,
          preparationCache: &containmentPreparationCache,
          tolerance: tolerance
        , using: &execution)
        if let certifiedContainment,
          certifiedContainment != isContained
        {
          throw KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message:
              "A complete Boolean boundary-event set was contradicted by closed-component containment."
          )
        }
        certifiedContainment = isContained
        try OriginalParameterQueryStorage.append(
          try BooleanCurveUVSample(
            curveParameter: parameter,
            uvPoint: booleanUVPoint(evaluation, tolerance: tolerance, using: &execution),
            tolerance: tolerance
          ), to: &samples, using: &execution)
      } catch {
        throw contextualized(
          error,
          stage: "closed intersection sample \(index) at curve parameter \(parameter)",
          tolerance: tolerance
        )
      }
    }
    guard certifiedContainment == true else { return .empty }
    return .closed(
      try BooleanClosedFaceIntersection(
        intersection: intersection,
        correspondenceVerifiedSamples: samples,
        tolerance: tolerance
      ))
  }

  private func containsIntersection(
    _ evaluation: SurfaceSurfaceIntersectionCurveEvaluation,
    pair: BooleanFacePairCandidate,
    targetSurface: Surface3D,
    toolSurface: Surface3D,
    model: BRepModel,
    cache: inout [FacePointContainmentCacheKey: Bool],
    preparationCache: inout FacePointContainmentPreparationCache,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    if let parameterContainment =
      facePointContainment as? any FaceParameterContainmentPreparationCaching
    {
      guard
        try parameterContainment.contains(
          evaluation.parameters.first,
          on: pair.targetFaceID,
          in: model,
          preparationCache: &preparationCache,
          tolerance: tolerance
        , using: &execution)
      else {
        return false
      }
      return try parameterContainment.contains(
        evaluation.parameters.second,
        on: pair.toolFaceID,
        in: model,
        preparationCache: &preparationCache,
        tolerance: tolerance
      , using: &execution)
    }
    guard
      try contains(
        evaluation.point,
        faceID: pair.targetFaceID,
        surface: targetSurface,
        model: model,
        cache: &cache,
        preparationCache: &preparationCache,
        tolerance: tolerance
      , using: &execution)
    else {
      return false
    }
    return try contains(
      evaluation.point,
      faceID: pair.toolFaceID,
      surface: toolSurface,
      model: model,
      cache: &cache,
      preparationCache: &preparationCache,
      tolerance: tolerance
    , using: &execution)
  }

  private func booleanUVPoint(
    _ evaluation: SurfaceSurfaceIntersectionCurveEvaluation,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BooleanUVPoint {
    try execution.consumeWork(1)
    return try BooleanUVPoint(
      point: evaluation.point,
      targetU: evaluation.parameters.first.u,
      targetV: evaluation.parameters.first.v,
      toolU: evaluation.parameters.second.u,
      toolV: evaluation.parameters.second.v,
      residual: evaluation.residual,
      tolerance: tolerance
    )
  }

  private func deduplicatedParameters(
    _ parameters: [Double],
    domain: ParameterDomain,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    let canonical: [Double]
    if case .periodic(let period) = domain {
      canonical = parameters.map { parameter in
        let remainder = parameter.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
      }
    } else {
      canonical = parameters
    }
    let threshold = max(tolerance.angle, tolerance.distance)
    var result: [Double] = []
    for parameter in canonical.sorted() {
      if result.last.map({ abs($0 - parameter) <= threshold }) != true {
        try OriginalParameterQueryStorage.append(parameter, to: &result, using: &execution)
      }
    }
    if case .periodic(let period) = domain,
      let first = result.first,
      let last = result.last,
      first + period - last <= threshold
    {
      result.removeLast()
    }
    return result
  }

  private func deduplicatedContacts(
    _ contacts: [ClipContact],
    domain: ParameterDomain,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [ClipContact] {
    try execution.consumeWork(1)
    let canonical = contacts.map { contact in
      ClipContact(
        parameter: canonicalParameter(contact.parameter, domain: domain),
        point: contact.point,
        isRecovered: contact.isRecovered
      )
    }.sorted { lhs, rhs in
      if lhs.parameter != rhs.parameter {
        return lhs.parameter < rhs.parameter
      }
      return lexicographicPointOrder(lhs.point, rhs.point)
    }
    // A projection junction and its containment-recovered twin disagree
    // along-curve by the polygon offset over the crossing angle's sine;
    // near-tangential crossings stretch that to tens of tolerances, and
    // surviving twins seed micron slivers no later stage can certify.
    let threshold = max(tolerance.angle, tolerance.distance) * 32.0
    var result: [ClipContact] = []
    for contact in canonical {
      if let last = result.last,
        abs(last.parameter - contact.parameter) <= threshold
      {
        // A projection contact is the certified junction; its
        // containment-recovered twin only approximates it and
        // must never displace it.
        if last.isRecovered, contact.isRecovered == false {
          result[result.count - 1] = contact
        }
        continue
      }
      try OriginalParameterQueryStorage.append(contact, to: &result, using: &execution)
    }
    if case .periodic(let period) = domain,
      let first = result.first,
      let last = result.last,
      result.count > 1,
      first.parameter + period - last.parameter <= threshold
    {
      if first.isRecovered, last.isRecovered == false {
        result.removeFirst()
      } else {
        result.removeLast()
      }
    }
    return result
  }

  private func contactPoint(
    at parameter: Double,
    contacts: [ClipContact],
    domain: ParameterDomain,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Point3D? {
    try execution.consumeWork(1)
    let canonical = canonicalParameter(parameter, domain: domain)
    let threshold = max(tolerance.angle, tolerance.distance)
    let matches = contacts.filter {
      abs($0.parameter - canonical) <= threshold
    }
    guard matches.count <= 1 else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "A Boolean trim parameter resolved to multiple canonical boundary contacts."
      )
    }
    return matches.first?.point
  }

  private func canonicalParameter(
    _ parameter: Double,
    domain: ParameterDomain
  ) -> Double {
    guard case .periodic(let period) = domain else { return parameter }
    let remainder = parameter.truncatingRemainder(dividingBy: period)
    return remainder >= 0.0 ? remainder : remainder + period
  }

  private func booleanUVPoint(
    _ point: Point3D,
    atCurveParameter parameter: Double,
    intersection: SurfaceSurfaceIntersectionCurve,
    targetSurface: Surface3D,
    toolSurface: Surface3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BooleanUVPoint {
    try execution.consumeWork(1)
    let target: SurfaceParameter
    let tool: SurfaceParameter
    do {
      let pair = try intersection.surfaceParameterPair(
        atCurveParameter: parameter, tolerance: tolerance, using: &execution)
      target = pair.first
      tool = pair.second
    } catch {
      throw contextualized(
        error,
        stage:
          "intersection pcurve evaluation at parameter \(parameter) in domain \(intersection.curve.parameterDomain)",
        tolerance: tolerance
      )
    }
    let targetPoint: Point3D
    do {
      targetPoint = try targetSurface.point(
        u: target.u,
        v: target.v,
        tolerance: tolerance
      , using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: "target surface evaluation at UV (\(target.u), \(target.v))",
        tolerance: tolerance
      )
    }
    let toolPoint: Point3D
    do {
      toolPoint = try toolSurface.point(
        u: tool.u,
        v: tool.v,
        tolerance: tolerance
      , using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: "tool surface evaluation at UV (\(tool.u), \(tool.v))",
        tolerance: tolerance
      )
    }
    let residual = max(
      intersection.maximumResidual,
      (point - targetPoint).length,
      (point - toolPoint).length
    )
    guard residual <= tolerance.distance else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: residual,
        tolerance: tolerance,
        message: "Boolean UV split pcurves disagree with their intersection curve."
      )
    }
    return try BooleanUVPoint(
      point: point,
      targetU: target.u,
      targetV: target.v,
      toolU: tool.u,
      toolV: tool.v,
      residual: residual,
      tolerance: tolerance
    )
  }

  private func booleanUVPoint(
    _ intersection: SurfaceSurfaceIntersectionPoint,
    targetSurface: Surface3D,
    toolSurface: Surface3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BooleanUVPoint {
    try execution.consumeWork(1)
    let target = intersection.firstSurfaceParameter
    let tool = intersection.secondSurfaceParameter
    let targetPoint = try targetSurface.point(
      u: target.u,
      v: target.v,
      tolerance: tolerance
    , using: &execution)
    let toolPoint = try toolSurface.point(
      u: tool.u,
      v: tool.v,
      tolerance: tolerance
    , using: &execution)
    let residual = max(
      intersection.residual,
      max(
        (intersection.point - targetPoint).length,
        (intersection.point - toolPoint).length
      )
    )
    return try BooleanUVPoint(
      point: intersection.point,
      targetU: target.u,
      targetV: target.v,
      toolU: tool.u,
      toolV: tool.v,
      residual: residual,
      tolerance: tolerance
    )
  }

  private func containsSurfaceParameter(
    _ parameter: SurfaceParameter,
    fallbackPoint: Point3D,
    faceID: FaceID,
    surface: Surface3D,
    model: BRepModel,
    cache: inout [FacePointContainmentCacheKey: Bool],
    preparationCache: inout FacePointContainmentPreparationCache,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    if let parameterContainment =
      facePointContainment as? any FaceParameterContainmentPreparationCaching
    {
      return try parameterContainment.contains(
        parameter,
        on: faceID,
        in: model,
        preparationCache: &preparationCache,
        tolerance: tolerance
      , using: &execution)
    }
    return try contains(
      fallbackPoint,
      faceID: faceID,
      surface: surface,
      model: model,
      cache: &cache,
      preparationCache: &preparationCache,
      tolerance: tolerance
    , using: &execution)
  }

  private func clippedPoints(
    contacts: [BooleanBoundaryContact],
    pair: BooleanFacePairCandidate,
    targetSurface: Surface3D,
    toolSurface: Surface3D,
    model: BRepModel,
    containmentCache: inout [FacePointContainmentCacheKey: Bool],
    containmentPreparationCache: inout FacePointContainmentPreparationCache,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [BooleanUVPoint] {
    try execution.consumeWork(1)
    var points: [BooleanUVPoint] = []
    for contact in contacts {
      let candidates: [(point: Point3D, residual: Double)]
      switch contact.geometry {
      case .points(let intersections):
        candidates = intersections.map { ($0.point, $0.residual) }
      case .coincident:
        guard let edge = model.edges[contact.edgeID],
              let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
          throw TopologyError.missingReference("A coincident planar boundary lacks original geometry.")
        }
        candidates = [(try curve.point(at: trim.startParameter, tolerance: tolerance, using: &execution), 0),
                      (try curve.point(at: trim.endParameter, tolerance: tolerance, using: &execution), 0)]
      }
      for intersection in candidates {
        guard
          try contains(
            intersection.point,
            faceID: pair.targetFaceID,
            surface: targetSurface,
            model: model,
            cache: &containmentCache,
            preparationCache: &containmentPreparationCache,
            tolerance: tolerance
          , using: &execution),
          try contains(
            intersection.point,
            faceID: pair.toolFaceID,
            surface: toolSurface,
            model: model,
            cache: &containmentCache,
            preparationCache: &containmentPreparationCache,
            tolerance: tolerance
          , using: &execution)
        else {
          continue
        }
        let target = try targetSurface.parameterProjection(
          of: intersection.point, tolerance: tolerance, using: &execution)
        let tool = try toolSurface.parameterProjection(of: intersection.point, tolerance: tolerance, using: &execution)
        let point = try BooleanUVPoint(
          point: intersection.point,
          targetU: target.u,
          targetV: target.v,
          toolU: tool.u,
          toolV: tool.v,
          residual: max(intersection.residual, target.residual, tool.residual),
          tolerance: tolerance
        )
        if points.contains(where: { ($0.point - point.point).length <= tolerance.distance })
          == false
        {
          try OriginalParameterQueryStorage.append(point, to: &points, using: &execution)
        }
      }
    }
    return points
  }

  private func contains(
    _ point: Point3D,
    faceID: FaceID,
    surface: Surface3D,
    model: BRepModel,
    cache: inout [FacePointContainmentCacheKey: Bool],
    preparationCache: inout FacePointContainmentPreparationCache,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    _ = surface
    let key = FacePointContainmentCacheKey(faceID: faceID, point: point)
    if let cached = cache[key] {
      return cached
    }
    let result: Bool
    if let cachingTester = facePointContainment as? any FacePointContainmentPreparationCaching {
      result = try cachingTester.contains(
        point,
        on: faceID,
        in: model,
        preparationCache: &preparationCache,
        tolerance: tolerance
      , using: &execution)
    } else {
      result = try facePointContainment.contains(
        point,
        on: faceID,
        in: model,
        tolerance: tolerance
      , using: &execution)
    }
    cache[key] = result
    return result
  }

  private func vector(_ point: Point3D) -> Vector3D {
    Vector3D(x: point.x, y: point.y, z: point.z)
  }

  private enum CurvedClipResult {
    case empty
    case closed(BooleanClosedFaceIntersection)
    case trimmed([BooleanTrimmedFaceIntersectionChain])
  }

  private struct ClipContact {
    let parameter: Double
    let point: Point3D
    var isRecovered: Bool = false
  }

  private struct TrimmedIntervalRecord {
    let ordinal: Int
    let segment: BooleanTrimmedFaceIntersection
  }

  private struct FacePointContainmentCacheKey: Hashable {
    let faceID: FaceID
    let point: Point3D
  }
}
