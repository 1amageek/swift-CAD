import HashTreeCollections
import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

/// Immutable invocation context for original B-rep validation algorithms.
struct OriginalBRepValidationInvocation: Sendable {
  let model: BRepModel
  let maximumSubdivisionDepth: Int
  let remainingSourceDepth: Int
  let maximumAlgebraicDepth: Int?

  init(model: BRepModel, maximumSubdivisionDepth: Int = 32, remainingSourceDepth: Int = 16,
       maximumAlgebraicDepth: Int? = nil) {
    self.model = model
    self.maximumSubdivisionDepth = min(32, maximumSubdivisionDepth)
    self.remainingSourceDepth = min(16, remainingSourceDepth)
    self.maximumAlgebraicDepth = maximumAlgebraicDepth
  }

  private var geometry: GeometryStore { model.geometry }
  private var bodies: PersistentMap<BodyID, Body> { model.bodies }
  private var shells: PersistentMap<ShellID, Shell> { model.shells }
  private var faces: PersistentMap<FaceID, Face> { model.faces }
  private var loops: PersistentMap<LoopID, Loop> { model.loops }
  private var edges: PersistentMap<EdgeID, Edge> { model.edges }
  private var vertices: PersistentMap<VertexID, Vertex> { model.vertices }

  private func charge(depth: Int = 0, using execution: inout OriginalQueryExecution) throws {
    try execution.checkpoint()
    guard maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0, depth >= 0, depth <= maximumSubdivisionDepth,
      maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
      throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: nil,
        message: "Original BRep validation exceeded its caller source or subdivision admission.")
    }
    try execution.consumeWork(1)
  }

  public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    try tolerance.validate()
    try validateTopologyTables(tolerance: tolerance, using: &execution)
    do {
      try geometry.validate(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
        maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }

    var referencedShellIDs = Set<ShellID>()
    var ownedShellIDs = Set<ShellID>()
    var sheetShellIDs = Set<ShellID>()
    for body in bodies.values {
      try charge(using: &execution)
      let bodyShellIDs = try shellIDs(of: body, using: &execution)
      guard !bodyShellIDs.isEmpty else {
        throw TopologyError.unreferencedTopology("Body \(body.id) has no shells.")
      }
      try validateNoDuplicateReferences(bodyShellIDs, owner: "Body \(body.id)", child: "shell", using: &execution)
      for shellID in bodyShellIDs {
        try charge(using: &execution)
        guard shells[shellID] != nil else {
          throw TopologyError.missingReference("Missing shell \(shellID).")
        }
        try recordOwnership(shellID, in: &ownedShellIDs, child: "shell", using: &execution)
        try OriginalParameterQueryStorage.insert(shellID, in: &referencedShellIDs, using: &execution)
        if body.kind == .sheet {
          try OriginalParameterQueryStorage.insert(shellID, in: &sheetShellIDs, using: &execution)
        }
      }
      if body.kind == .solid {
        _ = try model.solidShellComponents(for: body.id, tolerance: tolerance, using: &execution)
      }
    }
    try validateReferences(referencedShellIDs, cover: try declaredKeys(shells, using: &execution), label: "shell", using: &execution)

    var referencedFaceIDs = Set<FaceID>()
    var referencedLoopIDs = Set<LoopID>()
    var referencedSurfaceIDs = Set<SurfaceID>()
    var referencedEdgeIDs = Set<EdgeID>()
    var ownedFaceIDs = Set<FaceID>()
    var ownedLoopIDs = Set<LoopID>()
    var ownedShellEdgeIDs = Set<EdgeID>()
    var ownedShellVertexIDs = Set<VertexID>()
    for shell in shells.values {
      try charge(using: &execution)
      let isSheetShell = sheetShellIDs.contains(shell.id)
      guard !shell.faceIDs.isEmpty else {
        throw TopologyError.openShell(shell.id)
      }
      try validateNoDuplicateReferences(shell.faceIDs, owner: "Shell \(shell.id)", child: "face", using: &execution)
      var edgeUses: [EdgeID: EdgeUse] = [:]
      var shellEdgeIDs = Set<EdgeID>()
      var shellVertexIDs = Set<VertexID>()
      for faceID in shell.faceIDs {
        try charge(using: &execution)
        guard let face = faces[faceID] else {
          throw TopologyError.missingReference("Missing face \(faceID).")
        }
        try recordOwnership(faceID, in: &ownedFaceIDs, child: "face", using: &execution)
        try OriginalParameterQueryStorage.insert(faceID, in: &referencedFaceIDs, using: &execution)
        guard let surface = geometry.surfaces[face.surfaceID] else {
          throw TopologyError.missingSurface(face.surfaceID)
        }
        try OriginalParameterQueryStorage.insert(face.surfaceID, in: &referencedSurfaceIDs, using: &execution)
        guard !face.loops.isEmpty else {
          throw TopologyError.openShell(shell.id)
        }
        try validateNoDuplicateReferences(face.loops, owner: "Face \(face.id)", child: "loop", using: &execution)
        var outerLoopCount = 0
        for loopID in face.loops {
          try charge(using: &execution)
          guard let loop = loops[loopID] else {
            throw TopologyError.missingReference("Missing loop \(loopID).")
          }
          try recordOwnership(loopID, in: &ownedLoopIDs, child: "loop", using: &execution)
          if loop.role == .outer {
            outerLoopCount += 1
          }
          try OriginalParameterQueryStorage.insert(loopID, in: &referencedLoopIDs, using: &execution)
          try validate(loop: loop, tolerance: tolerance, using: &execution)
          do {
            try PeriodicFaceSeamValidator().validateRepeatedEdgeUses(in: loop, on: surface,
              tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
              remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
          }
          try validate(loop: loop, liesOn: surface, faceID: face.id, tolerance: tolerance, using: &execution)
          for orientedEdge in loop.edges {
            try charge(using: &execution)
            try OriginalParameterQueryStorage.insert(orientedEdge.edgeID, in: &referencedEdgeIDs, using: &execution)
            try OriginalParameterQueryStorage.insert(orientedEdge.edgeID, in: &shellEdgeIDs, using: &execution)
            if let edge = edges[orientedEdge.edgeID] {
              try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &shellVertexIDs, using: &execution)
              try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &shellVertexIDs, using: &execution)
            }
            var uses = edgeUses[orientedEdge.edgeID] ?? EdgeUse()
            uses.record(orientedEdge.orientation)
            try OriginalParameterQueryStorage.set(uses, for: orientedEdge.edgeID, in: &edgeUses, using: &execution)
          }
        }
        guard outerLoopCount == 1 else {
          throw TopologyError.invalidLoopRole(face.loops[0])
        }
      }

      for (edgeID, uses) in edgeUses {

        try charge(using: &execution)
        if let edge = edges[edgeID],
           try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: maximumSubdivisionDepth,
             remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth).kind(of: edge, in: model, tolerance: tolerance, using: &execution) == .singular {
          guard uses.count == 1 else { throw TopologyError.nonManifoldEdge(edgeID, count: uses.count) }
          continue
        }
        if isSheetShell {
          guard uses.count == 1 || uses.count == 2 else {
            throw TopologyError.nonManifoldEdge(edgeID, count: uses.count)
          }
          if uses.count == 2 {
            guard uses.forward == 1, uses.reversed == 1 else {
              throw TopologyError.inconsistentEdgeOrientation(edgeID)
            }
          }
        } else {
          guard uses.count == 2 else {
            throw TopologyError.nonManifoldEdge(edgeID, count: uses.count)
          }
          guard uses.forward == 1, uses.reversed == 1 else {
            throw TopologyError.inconsistentEdgeOrientation(edgeID)
          }
        }
      }
      if isSheetShell == false {
        try validateLineOnlyShellEnclosesVolume(shell, tolerance: tolerance, using: &execution)
      }
      for edgeID in shellEdgeIDs {
        try charge(using: &execution)
        try recordOwnership(edgeID, in: &ownedShellEdgeIDs, child: "edge", using: &execution)
      }
      for vertexID in shellVertexIDs {
        try charge(using: &execution)
        try recordOwnership(vertexID, in: &ownedShellVertexIDs, child: "vertex", using: &execution)
      }
    }

    try validateReferences(referencedFaceIDs, cover: try declaredKeys(faces, using: &execution), label: "face", using: &execution)
    try validateReferences(referencedLoopIDs, cover: try declaredKeys(loops, using: &execution), label: "loop", using: &execution)
    try validateReferences(referencedEdgeIDs, cover: try declaredKeys(edges, using: &execution), label: "edge", using: &execution)

    var referencedCurveIDs = Set<CurveID>()
    var referencedVertexIDs = Set<VertexID>()
    for edge in edges.values {
      try charge(using: &execution)
      try OriginalParameterQueryStorage.insert(edge.curveID, in: &referencedCurveIDs, using: &execution)
      try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &referencedVertexIDs, using: &execution)
      try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &referencedVertexIDs, using: &execution)
    }
    try validateReferences(referencedCurveIDs, cover: try declaredKeys(geometry.curves, using: &execution), label: "curve", using: &execution)
    try validateReferences(
      referencedSurfaceIDs, cover: try declaredKeys(geometry.surfaces, using: &execution), label: "surface", using: &execution)
    try validateReferences(referencedVertexIDs, cover: try declaredKeys(vertices, using: &execution), label: "vertex", using: &execution)
  }

  public func validate(
    level: BRepValidationLevel,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try validate(tolerance: tolerance, using: &execution)
    guard level != .modeling else {
      return
    }
    try validatePcurvesAfterBaseValidation(tolerance: tolerance, using: &execution)
    if level == .volumetric,
      bodies.values.contains(where: { $0.kind == .solid })
    {
      _ = try volumeAfterBaseValidation(tolerance: tolerance, using: &execution)
    }
  }

  public func diagnose(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> TopologyValidationReport {
    try DefaultBRepTopologyValidator().report(for: model, request: .all,
      tolerance: tolerance, using: &execution)
  }

  /// Validates the face-local parameter curves required by exact CAD exchange.
  /// This is intentionally separate from the base topology check because some
  /// development features still carry a geometric edge without a persisted p-curve.
  public func validatePcurves(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    try tolerance.validate()
    try validate(tolerance: tolerance, using: &execution)
    try validatePcurvesAfterBaseValidation(tolerance: tolerance, using: &execution)
  }

  private func validatePcurvesAfterBaseValidation(
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    for face in faces.values {
      try charge(using: &execution)
      guard let surface = geometry.surfaces[face.surfaceID] else {
        throw KernelError(
          phase: .topology,
          code: .missingReference,
          tolerance: tolerance,
          message: "Face-local p-curve validation references a missing surface."
        )
      }
      for loopID in face.loops {
        try charge(using: &execution)
        guard let loop = loops[loopID] else {
          throw KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: "Face-local p-curve validation references a missing loop."
          )
        }
        for coedge in loop.coedges {
          try charge(using: &execution)
          guard let pcurve = coedge.surfaceParameterCurve else {
            throw KernelError(
              phase: .topology,
              code: .topologyFailure,
              tolerance: tolerance,
              message: "Every coedge must carry a face-local p-curve for exact exchange."
            )
          }
          do {
            try pcurve.validate(on: surface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
              maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
          }
        }
      }
    }
  }

  public func volume(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
    try validate(tolerance: tolerance, using: &execution)
    return try volumeAfterBaseValidation(tolerance: tolerance, using: &execution)
  }

  public func volume(
    of bodyID: BodyID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try validate(tolerance: tolerance, using: &execution)
    guard bodies[bodyID] != nil else {
      throw TopologyError.missingReference("Missing measurable body \(bodyID).")
    }
    return try solidBodyVolumeAfterBaseValidation(
      bodyID: bodyID,
      tolerance: tolerance, using: &execution
    )
  }

  /// The certified signed volume one shell encloses under its own and its faces' orientation:
  /// positive when its faces face out of the region it bounds. A closed shell of a sheet body
  /// has a sign as well, which says which way its faces must face for it to bound a solid.
  public func signedVolume(
    ofShell shellID: ShellID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try validate(tolerance: tolerance, using: &execution)
    guard let shell = shells[shellID] else {
      throw TopologyError.missingReference("Missing measurable shell \(shellID).")
    }
    return try exactVolumeContribution(of: shell, tolerance: tolerance, using: &execution)
  }

  func volumeAfterBaseValidation(
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    var total = 0.0
    var foundSolid = false
    var bodyIDs: [BodyID] = []
    for bodyID in bodies.keys {
      try execution.consumeWork(1)
      try OriginalParameterQueryStorage.append(bodyID, to: &bodyIDs, using: &execution)
    }
    try OriginalParameterQueryStorage.sort(&bodyIDs, using: &execution, less: <)
    for bodyID in bodyIDs {
      try charge(using: &execution)
      guard bodies[bodyID]?.kind == .solid else {
        continue
      }
      foundSolid = true
      total += try solidBodyVolumeAfterBaseValidation(
        bodyID: bodyID,
        tolerance: tolerance, using: &execution
      )
    }
    guard foundSolid,
      total.isFinite,
      total > tolerance.distance * tolerance.distance * tolerance.distance
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "The B-rep does not contain a measurable solid volume."
      )
    }
    return total
  }

  private func solidBodyVolumeAfterBaseValidation(
    bodyID: BodyID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    let components = try model.solidShellComponents(
      for: bodyID,
      tolerance: tolerance, using: &execution
    )
    let minimumVolume = tolerance.distance * tolerance.distance * tolerance.distance
    var bodyVolume = 0.0
    for component in components {
      try charge(using: &execution)
      var componentVolume = 0.0
      for shellID in try component.originalShellIDs(using: &execution) {
        try charge(using: &execution)
        guard let shell = shells[shellID] else {
          throw TopologyError.missingReference("Missing shell \(shellID).")
        }
        componentVolume += try exactVolumeContribution(
          of: shell,
          tolerance: tolerance, using: &execution
        )
      }
      guard componentVolume.isFinite,
        componentVolume > minimumVolume
      else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          residual: componentVolume,
          tolerance: tolerance,
          message:
            "A solid component must retain positive material volume after subtracting its void shells; certified component volume was \(componentVolume)."
        )
      }
      bodyVolume += componentVolume
    }
    guard bodyVolume.isFinite, bodyVolume > minimumVolume else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "The B-rep body does not contain a measurable solid volume."
      )
    }
    return bodyVolume
  }

  private func exactVolumeContribution(
    of shell: Shell,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    let reference = try lineOnlyShellReferencePoint(shell, using: &execution)
    if let lineOnlyContribution = try lineOnlyShellVolume(
      shell,
      origin: reference,
      tolerance: tolerance, using: &execution
    ) {
      return lineOnlyContribution
    }
    if let analyticContribution = try AnalyticPrismaticVolumeEvaluator().volume(
      of: shell,
      in: model,
      tolerance: tolerance, using: &execution
    ) {
      return shell.orientation == .forward
        ? analyticContribution
        : -analyticContribution
    }
    if let trimmedAnalyticContribution = try TrimmedAnalyticSurfaceVolumeEvaluator().volume(
      of: shell,
      in: model,
      tolerance: tolerance, using: &execution
    ) {
      return shell.orientation == .forward
        ? trimmedAnalyticContribution
        : -trimmedAnalyticContribution
    }
    return try TrimmedParametricSurfaceVolumeEvaluator().volume(
      of: shell,
      in: model,
      tolerance: tolerance, using: &execution
    )
      * (shell.orientation == .forward ? 1.0 : -1.0)
  }

  public func orderedVertexIDs(for loopID: LoopID, using execution: inout OriginalQueryExecution) throws -> [VertexID] {
    guard let loop = loops[loopID] else {
      throw TopologyError.missingReference("Missing loop \(loopID).")
    }
    return try orderedVertexIDs(for: loop, using: &execution)
  }

  public func orderedPoints(for loopID: LoopID, using execution: inout OriginalQueryExecution) throws -> [Point3D] {
    let ids = try orderedVertexIDs(for: loopID, using: &execution)
    return try OriginalParameterQueryStorage.map(ids, using: &execution) { vertexID, execution in
      guard let vertex = vertices[vertexID] else {
        throw TopologyError.missingReference("Missing vertex \(vertexID).")
      }
      return vertex.point
    }
  }

  private func validate(
    loop: Loop,
    liesOn surface: Surface3D,
    faceID: FaceID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    for orientedEdge in loop.edges {
      try charge(using: &execution)
      guard let edge = edges[orientedEdge.edgeID],
        let startPoint = vertices[edge.startVertexID]?.point,
        let endPoint = vertices[edge.endVertexID]?.point,
        let curve = geometry.curves[edge.curveID]
      else {
        throw TopologyError.missingReference("Missing loop edge geometry.")
      }
      if let surfaceParameterCurve = orientedEdge.surfaceParameterCurve {
        let orientedStartVertexID = try startVertexID(for: orientedEdge, using: &execution)
        let orientedEndVertexID = try endVertexID(for: orientedEdge, using: &execution)
        guard let orientedStartPoint = vertices[orientedStartVertexID]?.point,
          let orientedEndPoint = vertices[orientedEndVertexID]?.point
        else {
          throw TopologyError.missingReference("Missing loop edge vertices.")
        }
        try validate(
          surfaceParameterCurve,
          on: surface,
          curve: curve,
          edge: edge,
          orientedEdge: orientedEdge,
          faceID: faceID,
          edgeID: orientedEdge.edgeID,
          startPoint: orientedStartPoint,
          endPoint: orientedEndPoint,
          tolerance: tolerance, using: &execution
        )
      } else {
        try validate(startPoint, liesOn: surface, faceID: faceID, tolerance: tolerance, using: &execution)
        try validate(endPoint, liesOn: surface, faceID: faceID, tolerance: tolerance, using: &execution)
        try validate(curve, liesOn: surface, faceID: faceID, tolerance: tolerance, using: &execution)
      }
    }
    try validateLoopArea(loop, liesOn: surface, tolerance: tolerance, using: &execution)
  }

  private func validate(
    _ surfaceParameterCurve: SurfaceParameterCurve,
    on surface: Surface3D,
    curve: Curve3D,
    edge: Edge,
    orientedEdge: Coedge,
    faceID: FaceID,
    edgeID: EdgeID,
    startPoint: Point3D,
    endPoint: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    let startResidual: Double
    let endResidual: Double
    do {
      do {
        try surfaceParameterCurve.validate(on: surface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
          maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let prepared = try PreparedCurveDifferentialEncloser(
          curve: .surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: surfaceParameterCurve)),
          tolerance: tolerance, remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        startResidual = try originalPointResidual(from: startPoint, at: 0,
          prepared: prepared, tolerance: tolerance, using: &execution)
        endResidual = try originalPointResidual(from: endPoint, at: 1,
          prepared: prepared, tolerance: tolerance, using: &execution)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw try contextualizedCoedgeError(error, faceID: faceID, edgeID: edgeID,
        stage: "pcurve endpoint validation", tolerance: tolerance)
    }
    // Boolean junction vertices snap to canonical points on source
    // boundary geometry, up to eight tolerances off the pcurve lift.
    guard startResidual <= tolerance.distance * 8.0,
      endResidual <= tolerance.distance * 8.0
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: max(startResidual, endResidual),
        tolerance: tolerance,
        message:
          "Face \(faceID) coedge \(edgeID) has pcurve endpoints inconsistent with orientation \(orientedEdge.orientation.rawValue); start residual \(startResidual), end residual \(endResidual)."
      )
    }
    let startCurveParameter: Double
    let endCurveParameter: Double
    if let trim = edge.trim {
      switch orientedEdge.orientation {
      case .forward:
        startCurveParameter = trim.startParameter
        endCurveParameter = trim.endParameter
      case .reversed:
        startCurveParameter = trim.endParameter
        endCurveParameter = trim.startParameter
      }
    } else {
      guard try isUnboundedLineCurve(curve, using: &execution) else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message:
            "Face \(faceID) coedge \(edgeID) references a non-linear edge without an exact curve trim."
        )
      }
      do {
        startCurveParameter = try originalLineParameter(startPoint, on: curve, tolerance: tolerance, using: &execution)
        endCurveParameter = try originalLineParameter(endPoint, on: curve, tolerance: tolerance, using: &execution)
      }
    }

    do {
      // Boolean junction endpoints snap pcurve ends to canonical
      // points up to eight tolerances off the exact curve, so the
      // lift-versus-curve bound certifies at the widened tolerance.
      let options = CurveSurfaceCorrespondenceValidationOptions(
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        maximumCellCount: 1_048_576,
        maximumDeviation: tolerance.distance * 8.0)
      // FIXME(INCOMPLETE_IMPLEMENTATION): Original bounded BRep validation now
      // forwards the caller into source preparation and complete residual cells.
      // Nonlinear/critical correspondence, continuous chart lifts and lower jet
      // temporary byte admission must close before full bounded validation.
      do {
        try DefaultCurveSurfaceCorrespondenceValidator().validate(
          curve: curve, from: startCurveParameter, to: endCurveParameter,
          surface: surface, parameterCurve: surfaceParameterCurve,
          options: options, tolerance: tolerance, maximumSpanCount: 1_048_576,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
      }
    } catch let error as KernelError {
      throw KernelError(
        phase: error.phase,
        code: error.code,
        featureID: error.featureID,
        subshapeID: error.subshapeID,
        residual: error.residual,
        tolerance: error.tolerance ?? tolerance,
        message:
          "Face \(faceID) coedge \(edgeID) failed exact curve-surface correspondence: \(error.message)"
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw try contextualizedCoedgeError(
        error,
        faceID: faceID,
        edgeID: edgeID,
        stage: "exact curve-surface correspondence",
        tolerance: tolerance
      )
    }
  }

  private func contextualizedCoedgeError(
    _ error: any Error,
    faceID: FaceID,
    edgeID: EdgeID,
    stage: String,
    tolerance: ModelingTolerance
  ) throws -> KernelError {
    if let original = error as? KernelError {
      return KernelError(phase: original.phase, code: original.code,
        featureID: original.featureID, subshapeID: original.subshapeID,
        residual: original.residual, tolerance: original.tolerance ?? tolerance,
        message: "Face \(faceID) coedge \(edgeID) failed \(stage): \(original.message)")
    }
    throw error
  }

  private func interpolated(_ start: Point3D, _ end: Point3D, fraction: Double) -> Point3D {
    Point3D(
      x: start.x + (end.x - start.x) * fraction,
      y: start.y + (end.y - start.y) * fraction,
      z: start.z + (end.z - start.z) * fraction
    )
  }

  private func validateLineOnlyShellEnclosesVolume(_ shell: Shell, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws
  {
    // A shell-local reference keeps plane offsets and projected areas stable
    // when geometry is placed far from the world origin. The same reference
    // must be used by every face so the divergence-theorem flux remains
    // translation invariant.
    let origin = try lineOnlyShellReferencePoint(shell, using: &execution)
    var signedVolume = 0.0
    for faceID in shell.faceIDs {
      try charge(using: &execution)
      guard let face = faces[faceID],
        let contribution = try lineOnlyFaceVolumeContribution(
          face,
          shellOrientation: shell.orientation,
          origin: origin,
          tolerance: tolerance, using: &execution
        )
      else {
        return
      }
      signedVolume += contribution
    }
    let minimumVolume = tolerance.distance * tolerance.distance * tolerance.distance
    guard signedVolume.isFinite, abs(signedVolume) > minimumVolume else {
      throw TopologyError.openShell(shell.id)
    }
  }

  private func lineOnlyShellReferencePoint(_ shell: Shell, using execution: inout OriginalQueryExecution) throws -> Point3D {
    try BRepShellReferencePointResolver().referencePoint(
      for: shell,
      in: model,
      context: "Line-only shell volume"
    )
  }

  private func lineOnlyShellVolume(
    _ shell: Shell,
    origin: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double? {
    var signedVolume = 0.0
    for faceID in shell.faceIDs {
      try charge(using: &execution)
      guard let face = faces[faceID],
        let contribution = try lineOnlyFaceVolumeContribution(
          face,
          shellOrientation: shell.orientation,
          origin: origin,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      signedVolume += contribution
    }
    return signedVolume
  }

  private func lineOnlyFaceVolumeContribution(
    _ face: Face,
    shellOrientation: Orientation,
    origin: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double? {
    guard face.loops.isEmpty == false else {
      return nil
    }
    guard let surface = geometry.surfaces[face.surfaceID] else {
      throw TopologyError.missingSurface(face.surfaceID)
    }
    guard
      let plane = try DefaultPlanarSurfaceResolver().exactPlane(
        for: surface,
        tolerance: tolerance
      )
    else {
      return nil
    }
    let planeOrigin = plane.origin
    let planeNormal = try plane.normal.normalized(tolerance: tolerance.distance)

    var materialArea = 0.0
    for loopID in face.loops {
      try charge(using: &execution)
      guard let loop = loops[loopID] else {
        throw TopologyError.missingReference("Missing face loop geometry.")
      }
      for orientedEdge in loop.edges {
        try charge(using: &execution)
        guard let edge = edges[orientedEdge.edgeID],
          let curve = geometry.curves[edge.curveID]
        else {
          throw TopologyError.missingReference("Missing loop edge geometry.")
        }
        guard case .line = curve else {
          return nil
        }
      }

      let points = try orderedPoints(for: loopID, using: &execution)
      guard points.count >= 3 else {
        throw TopologyError.degenerateLoop(loopID)
      }
      let anchor = points[0]
      var signedDoubleArea = 0.0
      for index in 1..<(points.count - 1) {
        try charge(using: &execution)
        signedDoubleArea += (points[index] - anchor)
          .cross(points[index + 1] - anchor)
          .dot(planeNormal)
      }
      let area = abs(signedDoubleArea) * 0.5
      guard area > tolerance.distance * tolerance.distance else {
        throw TopologyError.degenerateLoop(loopID)
      }
      materialArea += loop.role == .outer ? area : -area
    }
    guard materialArea > tolerance.distance * tolerance.distance else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: materialArea,
        tolerance: tolerance,
        message:
          "A planar face must retain positive material area after subtracting its inner loops."
      )
    }
    let faceSign = face.orientation == .forward ? 1.0 : -1.0
    let shellSign = shellOrientation == .forward ? 1.0 : -1.0
    let planeOffset = (planeOrigin - origin).dot(planeNormal)
    return shellSign * faceSign * planeOffset * materialArea / 3.0
  }

  private func validateLoopArea(
    _ loop: Loop,
    liesOn surface: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    if case .cylinder(let cylinder) = surface {
      try validateCylinderLoopArea(loop, liesOn: cylinder, tolerance: tolerance, using: &execution)
      return
    }
    if case .analytic(.sphere(let center, let radius)) = surface,
      loop.coedges.allSatisfy({ $0.surfaceParameterCurve != nil })
    {
      try validateSphericalLoopArea(
        loop,
        surface: surface,
        center: center,
        radius: radius,
        tolerance: tolerance, using: &execution
      )
      return
    }
    if loop.coedges.allSatisfy({ $0.surfaceParameterCurve != nil }) {
      let parameterTolerance = loopParameterTolerance(
        for: surface,
        tolerance: tolerance
      )
      let minimumParameterArea = max(
        parameterTolerance.u * parameterTolerance.v,
        Double.leastNormalMagnitude * 1_024.0
      )
      let bounds = try loopParameterAreaBounds(
        loop,
        uPeriod: periodicValue(surface.uDomain),
        vPeriod: periodicValue(surface.vDomain),
        minimumArea: minimumParameterArea,
        uClosureTolerance: parameterTolerance.u * 8.0,
        vClosureTolerance: parameterTolerance.v * 8.0,
        surface: surface,
        tolerance: tolerance, using: &execution
      )
      guard let bounds,
        bounds.minimumAbsoluteValue > minimumParameterArea
      else {
        throw TopologyError.degenerateLoop(loop.id)
      }
      return
    }
    for orientedEdge in loop.edges {
      try charge(using: &execution)
      guard let edge = edges[orientedEdge.edgeID],
        let curve = geometry.curves[edge.curveID]
      else {
        throw TopologyError.missingReference("Missing loop edge geometry.")
      }
      guard case .line = curve else {
        return
      }
    }

    let vertexIDs = try orderedVertexIDs(for: loop, using: &execution)
    guard vertexIDs.count >= 3 else {
      throw TopologyError.degenerateLoop(loop.id)
    }

    guard case .plane(let plane) = surface else {
      return
    }
    try plane.validate(tolerance: tolerance)
    let normal = try plane.normal.normalized(tolerance: tolerance.distance)
    let points = try vertexIDs.map { vertexID -> Point3D in
      guard let point = vertices[vertexID]?.point else {
        throw TopologyError.missingReference("Missing vertex \(vertexID).")
      }
      try point.validate()
      return point
    }

    var signedDoubleArea = 0.0
    for index in points.indices {
      try charge(using: &execution)
      let current = points[index] - plane.origin
      let next = points[(index + 1) % points.count] - plane.origin
      signedDoubleArea += current.cross(next).dot(normal)
    }
    let area = abs(signedDoubleArea) * 0.5
    guard area.isFinite, area > tolerance.distance * tolerance.distance else {
      throw TopologyError.degenerateLoop(loop.id)
    }
  }

  private func validateCylinderLoopArea(
    _ loop: Loop,
    liesOn cylinder: Cylinder3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try cylinder.validate(tolerance: tolerance)
    if let parameterArea = try loopParameterAreaBounds(
      loop,
      uPeriod: 2.0 * Double.pi,
      vPeriod: nil,
      minimumArea: tolerance.distance * tolerance.distance / cylinder.radius,
      uClosureTolerance: max(
        tolerance.angle,
        tolerance.distance / cylinder.radius
      ),
      vClosureTolerance: tolerance.distance,
      surface: .cylinder(cylinder),
      tolerance: tolerance, using: &execution
    ) {
      let guaranteedPhysicalArea =
        parameterArea.minimumAbsoluteValue
        * cylinder.radius
      guard guaranteedPhysicalArea.isFinite,
        guaranteedPhysicalArea > tolerance.distance * tolerance.distance
      else {
        throw TopologyError.degenerateLoop(loop.id)
      }
      return
    }

    let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
    var minimumHeight: Double?
    var maximumHeight: Double?
    var maximumCircularSpan = 0.0

    for orientedEdge in loop.edges {

      try charge(using: &execution)
      guard let edge = edges[orientedEdge.edgeID],
        let startPoint = vertices[edge.startVertexID]?.point,
        let endPoint = vertices[edge.endVertexID]?.point,
        let curve = geometry.curves[edge.curveID]
      else {
        throw TopologyError.missingReference("Missing loop edge geometry.")
      }
      for point in [startPoint, endPoint] {
        try charge(using: &execution)
        let height = (point - cylinder.origin).dot(axis)
        minimumHeight = min(minimumHeight ?? height, height)
        maximumHeight = max(maximumHeight ?? height, height)
      }
      guard case .circle = curve else {
        continue
      }
      guard let trim = edge.trim else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message:
            "Cylinder loop \(loop.id) contains circular edge \(edge.id) without an exact curve trim."
        )
      }
      let span: Double
      switch orientedEdge.orientation {
      case .forward:
        span = trim.endParameter - trim.startParameter
      case .reversed:
        span = trim.startParameter - trim.endParameter
      }
      maximumCircularSpan = max(maximumCircularSpan, abs(span))
    }

    guard let minimumHeight,
      let maximumHeight,
      maximumHeight - minimumHeight > tolerance.distance,
      maximumCircularSpan > max(tolerance.angle, tolerance.distance / cylinder.radius)
    else {
      throw TopologyError.degenerateLoop(loop.id)
    }
  }

  private func loopParameterAreaBounds(
    _ loop: Loop,
    uPeriod: Double?,
    vPeriod: Double?,
    minimumArea: Double,
    uClosureTolerance: Double,
    vClosureTolerance: Double,
    surface: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds? {
    guard loop.coedges.isEmpty == false else {
      return .zero
    }
    for coedge in loop.coedges {
      try charge(using: &execution)
      guard coedge.surfaceParameterCurve != nil else { return nil }
    }
    let minimumRequestedLoopWidth = minimumArea * 0.25
    let shiftedCurves: [SurfaceParameterLoopUnwrapper.UnwrappedCurve]
    do {
      let bytes = loop.coedges.count.multipliedReportingOverflow(by: MemoryLayout<SurfaceParameterCurve>.stride)
      guard !bytes.overflow else {
        throw GeometryConversionError.resourceLimitExceeded("Original loop curve storage count overflowed.")
      }
      try charge(using: &execution); try execution.retainStorage(bytes: bytes.partialValue)
      var curves: [SurfaceParameterCurve] = []
      curves.reserveCapacity(loop.coedges.count)
      for coedge in loop.coedges {
        try charge(using: &execution)
        guard let curve = coedge.surfaceParameterCurve else {
          throw GeometryConversionError.invalidInput("Original surface loop has an absent pcurve.")
        }
        try OriginalParameterQueryStorage.append(curve, to: &curves, using: &execution)
      }
      shiftedCurves = try SurfaceParameterLoopUnwrapper().unwrap(curves,
        uPeriod: uPeriod, vPeriod: vPeriod,
        uClosureTolerance: uClosureTolerance, vClosureTolerance: vClosureTolerance,
        on: surface, tolerance: tolerance, context: "Surface loop \(loop.id)",
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, using: &execution)
    }
    let integrator = SurfaceParameterCurveAreaIntegrator(
      maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth ?? 32)
    // A loose first request keeps singular-endpoint pcurve integrands
    // affordable for loops whose area dwarfs the degeneracy threshold;
    // the refinement loop tightens the request only when the enclosure
    // stays inconclusive.
    var requestedLoopWidth = max(minimumRequestedLoopWidth, 1.0)
    while true {
      try charge(using: &execution)
      let requestedCurveWidth =
        requestedLoopWidth
        / Double(shiftedCurves.count)
      var result = SurfaceParameterAreaBounds.zero
      for shiftedCurve in shiftedCurves {
        try charge(using: &execution)
        let bounds: SurfaceParameterAreaBounds
        do {
          bounds = try integrator.bounds(for: shiftedCurve.curve, on: surface,
            uShift: shiftedCurve.uShift, requestedWidth: requestedCurveWidth, tolerance: tolerance, using: &execution)
        }
        result = result.adding(bounds)
      }
      if result.minimumAbsoluteValue > minimumArea {
        return result
      }
      guard requestedLoopWidth > minimumRequestedLoopWidth else {
        return result
      }
      requestedLoopWidth = max(
        minimumRequestedLoopWidth,
        requestedLoopWidth / 16.0
      )
    }
  }

  private func periodicValue(_ domain: ParameterDomain) -> Double? {
    guard case .periodic(let period) = domain else {
      return nil
    }
    return period
  }

  private func loopParameterTolerance(
    for surface: Surface3D,
    tolerance: ModelingTolerance
  ) -> (u: Double, v: Double) {
    switch surface {
    case .plane:
      return (tolerance.distance, tolerance.distance)
    case .cylinder(let cylinder):
      return (
        max(tolerance.angle, tolerance.distance / cylinder.radius),
        tolerance.distance
      )
    case .analytic(let analytic):
      switch analytic {
      case .plane:
        return (tolerance.distance, tolerance.distance)
      case .cylinder(_, _, let radius):
        return (
          max(tolerance.angle, tolerance.distance / radius),
          tolerance.distance
        )
      case .cone:
        return (tolerance.angle, tolerance.distance)
      case .sphere(_, let radius):
        let angular = max(tolerance.angle, tolerance.distance / radius)
        return (angular, angular)
      case .torus(_, _, let majorRadius, let minorRadius):
        return (
          max(
            tolerance.angle,
            tolerance.distance / (majorRadius - minorRadius)
          ),
          max(tolerance.angle, tolerance.distance / minorRadius)
        )
      }
    case .bSpline(let spline):
      return (
        parameterResolution(spline.uDomain, tolerance: tolerance),
        parameterResolution(spline.vDomain, tolerance: tolerance)
      )
    case .procedural(let procedural):
      return (
        parameterResolution(procedural.uDomain, tolerance: tolerance),
        parameterResolution(procedural.vDomain, tolerance: tolerance)
      )
    }
  }

  private func parameterResolution(
    _ domain: ParameterDomain,
    tolerance: ModelingTolerance
  ) -> Double {
    let scale: Double
    switch domain {
    case .unbounded:
      scale = 1.0
    case .closed(let lower, let upper):
      scale = max(abs(lower), abs(upper), abs(upper - lower), 1.0)
    case .periodic(let period):
      scale = max(abs(period), 1.0)
    }
    return max(
      tolerance.relative * scale,
      Double.ulpOfOne * scale * 256.0
    )
  }

  private func validateSphericalLoopArea(
    _ loop: Loop,
    surface: Surface3D,
    center: Point3D,
    radius: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    if loop.coedges.allSatisfy({ coedge in
      guard let pcurve = coedge.surfaceParameterCurve else { return false }
      return sphericalGreatCircleDefinition(pcurve) != nil
    }) {
      try validateSphericalGreatCircleLoopArea(
        loop,
        radius: radius,
        tolerance: tolerance, using: &execution
      )
      return
    }

    let minimumSolidAngle = tolerance.distance * tolerance.distance / (radius * radius)
    var previous = try sampledSphericalLoopSolidAngle(
      loop,
      surface: surface,
      center: center,
      subdivisionsPerCoedge: 4,
      tolerance: tolerance, using: &execution
    )
    for subdivisions in [8, 16, 32, 64] {
      try charge(using: &execution)
      let current = try sampledSphericalLoopSolidAngle(
        loop,
        surface: surface,
        center: center,
        subdivisionsPerCoedge: subdivisions,
        tolerance: tolerance, using: &execution
      )
      let refinementError = abs(current - previous)
      if abs(current) - refinementError * 2.0 > minimumSolidAngle {
        return
      }
      previous = current
    }
    throw TopologyError.degenerateLoop(loop.id)
  }

  private func sampledSphericalLoopSolidAngle(
    _ loop: Loop,
    surface: Surface3D,
    center: Point3D,
    subdivisionsPerCoedge: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    var segments: [(start: Vector3D, end: Vector3D)] = []
    var referenceCandidates: [Vector3D] = []
    try OriginalParameterQueryStorage.reserve(6, in: &referenceCandidates, using: &execution)
    referenceCandidates.append(.unitX); referenceCandidates.append(-.unitX)
    referenceCandidates.append(.unitY); referenceCandidates.append(-.unitY)
    referenceCandidates.append(.unitZ); referenceCandidates.append(-.unitZ)
    for coedge in loop.coedges {
      try charge(using: &execution)
      guard let pcurve = coedge.surfaceParameterCurve else {
        throw TopologyError.missingReference(
          "Missing spherical pcurve for loop \(loop.id)."
        )
      }
      let startPoint = try sphericalPoint(
        for: pcurve,
        atNormalizedFraction: 0.0,
        on: surface,
        tolerance: tolerance, using: &execution
      )
      var start = try (startPoint - center).normalized(tolerance: tolerance.distance)
      for index in 1...subdivisionsPerCoedge {
        try charge(using: &execution)
        let point = try sphericalPoint(
          for: pcurve,
          atNormalizedFraction: Double(index) / Double(subdivisionsPerCoedge),
          on: surface,
          tolerance: tolerance, using: &execution
        )
        let end = try (point - center).normalized(tolerance: tolerance.distance)
        try OriginalParameterQueryStorage.append((start: start, end: end), to: &segments, using: &execution)
        let cross = start.cross(end)
        if cross.length > tolerance.angle {
          let normal = try cross.normalized(tolerance: tolerance.angle)
          try OriginalParameterQueryStorage.append(normal, to: &referenceCandidates, using: &execution)
          try OriginalParameterQueryStorage.append(-normal, to: &referenceCandidates, using: &execution)
        }
        start = end
      }
    }
    return try sphericalSolidAngle(
      segments: segments,
      referenceCandidates: referenceCandidates,
      loopID: loop.id, using: &execution
    )
  }

  private func sphericalPoint(
    for pcurve: SurfaceParameterCurve,
    atNormalizedFraction fraction: Double,
    on surface: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
    switch pcurve {
    case .certifiedAnalyticImplicit(let curve):
      let mapped =
        curve.startFraction
        + (curve.endFraction - curve.startFraction) * fraction
      return try curve.intersection.implicitCurve.point(
        atNormalizedFraction: mapped,
        tolerance: tolerance, using: &execution
      )
    case .periodicTranslation(let base, _, _):
      return try sphericalPoint(
        for: base,
        atNormalizedFraction: fraction,
        on: surface,
        tolerance: tolerance, using: &execution
      )
    case .affine, .constantU, .constantV, .harmonic, .sphericalGreatCircle,
      .polyline, .bSpline, .certifiedImplicit, .certifiedAnalyticPair,
      .projectedAnalytic, .rigidImage, .offsetSurfaceImage, .originalImage, .originalAffineWord, .originalBSplineContinuation:
      let parameter = try pcurve.parameter(
        atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution
      )
      return try surface.point(
        u: parameter.u,
        v: parameter.v,
        tolerance: tolerance, using: &execution
      )
    }
  }

  private func validateSphericalGreatCircleLoopArea(
    _ loop: Loop,
    radius: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    var segments: [(start: Vector3D, end: Vector3D)] = []
    var referenceCandidates: [Vector3D] = []
    try OriginalParameterQueryStorage.reserve(6, in: &referenceCandidates, using: &execution)
    referenceCandidates.append(.unitX); referenceCandidates.append(-.unitX)
    referenceCandidates.append(.unitY); referenceCandidates.append(-.unitY)
    referenceCandidates.append(.unitZ); referenceCandidates.append(-.unitZ)
    for coedge in loop.coedges {
      try charge(using: &execution)
      guard let pcurve = coedge.surfaceParameterCurve,
        let definition = sphericalGreatCircleDefinition(pcurve)
      else {
        throw TopologyError.missingReference(
          "Missing spherical great-circle pcurve for loop \(loop.id)."
        )
      }
      let normal = try definition.cosine.cross(definition.sine).normalized(
        tolerance: tolerance.distance
      )
      try OriginalParameterQueryStorage.append(normal, to: &referenceCandidates, using: &execution)
      try OriginalParameterQueryStorage.append(-normal, to: &referenceCandidates, using: &execution)

      let span = definition.endParameter - definition.startParameter
      let segmentCount = max(1, Int(ceil(abs(span) / (0.5 * Double.pi))))
      var start = try sphericalGreatCircleRadial(
        cosine: definition.cosine,
        sine: definition.sine,
        parameter: definition.startParameter,
        tolerance: tolerance, using: &execution
      )
      for index in 1...segmentCount {
        try charge(using: &execution)
        let fraction = Double(index) / Double(segmentCount)
        let parameter = definition.startParameter + span * fraction
        let end = try sphericalGreatCircleRadial(
          cosine: definition.cosine,
          sine: definition.sine,
          parameter: parameter,
          tolerance: tolerance, using: &execution
        )
        try OriginalParameterQueryStorage.append((start: start, end: end), to: &segments, using: &execution)
        start = end
      }
    }
    let solidAngle = try sphericalSolidAngle(
      segments: segments,
      referenceCandidates: referenceCandidates,
      loopID: loop.id, using: &execution
    )
    let physicalArea = abs(solidAngle) * radius * radius
    guard physicalArea.isFinite,
      physicalArea > tolerance.distance * tolerance.distance
    else {
      throw TopologyError.degenerateLoop(loop.id)
    }
  }

  private func sphericalSolidAngle(
    segments: [(start: Vector3D, end: Vector3D)],
    referenceCandidates: [Vector3D],
    loopID: LoopID, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    guard segments.isEmpty == false else {
      throw TopologyError.degenerateLoop(loopID)
    }

    var reference: Vector3D?
    var bestScore = -Double.infinity
    for candidate in referenceCandidates {
      try charge(using: &execution)
      var score = Double.infinity
      for segment in segments {
        try charge(using: &execution)
        let numerator = candidate.dot(segment.start.cross(segment.end))
        let denominator =
          1.0
          + candidate.dot(segment.start)
          + segment.start.dot(segment.end)
          + segment.end.dot(candidate)
        score = min(score, hypot(numerator, denominator))
      }
      if score > bestScore {
        bestScore = score
        reference = candidate
      }
    }
    guard let reference,
      bestScore > Double.ulpOfOne * 4_096.0
    else {
      throw TopologyError.degenerateLoop(loopID)
    }

    var solidAngle = 0.0
    for segment in segments {
      try charge(using: &execution)
      let numerator = reference.dot(segment.start.cross(segment.end))
      let denominator =
        1.0
        + reference.dot(segment.start)
        + segment.start.dot(segment.end)
        + segment.end.dot(reference)
      solidAngle += 2.0 * atan2(numerator, denominator)
    }
    return solidAngle
  }

  private func sphericalGreatCircleDefinition(
    _ curve: SurfaceParameterCurve
  ) -> (
    cosine: Vector3D,
    sine: Vector3D,
    startParameter: Double,
    endParameter: Double
  )? {
    switch curve {
    case .sphericalGreatCircle(let cosine, let sine, let startParameter, let endParameter):
      return (cosine, sine, startParameter, endParameter)
    case .periodicTranslation(let base, _, _):
      return sphericalGreatCircleDefinition(base)
    case .rigidImage(let image):
      guard
        let source = sphericalGreatCircleDefinition(
          image.source.parameterCurve
        )
      else {
        return nil
      }
      let span = source.endParameter - source.startParameter
      return (
        image.transform.applying(to: source.cosine),
        image.transform.applying(to: source.sine),
        source.startParameter + span * image.startFraction,
        source.startParameter + span * image.endFraction
      )
    case .offsetSurfaceImage(let image):
      return sphericalGreatCircleDefinition(image.source)
    case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline,
      .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
      .projectedAnalytic, .originalImage, .originalAffineWord, .originalBSplineContinuation:
      return nil
    }
  }

  private func sphericalGreatCircleRadial(
    cosine: Vector3D,
    sine: Vector3D,
    parameter: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Vector3D {
    try (cosine * cos(parameter) + sine * sin(parameter)).normalized(
      tolerance: tolerance.distance
    )
  }

  private func vector(from point: Point3D) -> Vector3D {
    Vector3D(x: point.x, y: point.y, z: point.z)
  }

  private func validate(
    _ point: Point3D,
    liesOn surface: Surface3D,
    faceID: FaceID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    switch surface {
    case .plane(let plane):
      try plane.validate(tolerance: tolerance)
      let normal = try plane.normal.normalized(tolerance: tolerance.distance)
      let distance = (point - plane.origin).dot(normal)
      guard abs(distance) <= tolerance.distance else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case .cylinder(let cylinder):
      try cylinder.validate(tolerance: tolerance)
      let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
      let offset = point - cylinder.origin
      let axialOffset = axis * offset.dot(axis)
      let radialOffset = offset - axialOffset
      guard abs(radialOffset.length - cylinder.radius) <= tolerance.distance else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case .bSpline(let surface):
      try surface.validate(tolerance: tolerance, using: &execution)
      guard try isPointOnBSplineBoundary(point, surface: surface, tolerance: tolerance, using: &execution) else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case .analytic(let surface):
      try surface.validate(tolerance: tolerance)
      let residual: Double
      switch surface {
      case .plane(let origin, let normal):
        residual = abs((point - origin).dot(normal))
      case .cylinder(let origin, let axis, let radius):
        let offset = point - origin
        let radial = offset - axis * offset.dot(axis)
        residual = abs(radial.length - radius)
      case .cone(let apex, let axis, let halfAngle):
        let offset = point - apex
        let axialDistance = offset.dot(axis)
        let radial = offset - axis * axialDistance
        residual = abs(radial.length - abs(axialDistance * tan(halfAngle)))
      case .sphere(let center, let radius):
        residual = abs((point - center).length - radius)
      case .torus(let center, let axis, let majorRadius, let minorRadius):
        let offset = point - center
        let axialDistance = offset.dot(axis)
        let radial = offset - axis * axialDistance
        residual = abs(hypot(radial.length - majorRadius, axialDistance) - minorRadius)
      }
      guard residual <= tolerance.distance else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case .procedural:
      let projection = try surface.parameterProjection(
        of: point,
        tolerance: tolerance, using: &execution
      )
      guard projection.residual <= tolerance.distance else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    }
  }

  private func validate(
    _ curve: Curve3D,
    liesOn surface: Surface3D,
    faceID: FaceID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    if case .rigidImage(let image) = curve {
      let sourceSurface = try image.transform.inverted().applying(
        to: surface,
        tolerance: tolerance
      )
      return try validate(
        image.source,
        liesOn: sourceSurface,
        faceID: faceID,
        tolerance: tolerance, using: &execution
      )
    }
    if case .surfaceLift(let lift) = curve {
      try lift.validate(tolerance: tolerance)
      guard lift.surface == surface else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
      return
    }
    if case .analytic(let analyticCurve) = curve {
      switch analyticCurve {
      case .line(let origin, let direction):
        return try validate(
          .line(Line3D(origin: origin, direction: direction)),
          liesOn: surface,
          faceID: faceID,
          tolerance: tolerance, using: &execution
        )
      case .circle(let center, let normal, let radius),
        .arc(let center, let normal, let radius, _, _):
        return try validate(
          .circle(Circle3D(center: center, normal: normal, radius: radius)),
          liesOn: surface,
          faceID: faceID,
          tolerance: tolerance, using: &execution
        )
      case .ellipse, .hyperbola, .parabola:
        return try AnalyticConicSurfaceValidator().validate(
          curve: analyticCurve,
          liesOn: surface,
          faceID: faceID,
          tolerance: tolerance
        )
      case .planeTorus(let intersection):
        try intersection.validate(tolerance: tolerance)
        guard
          surface == intersection.planeSurface
            || surface == intersection.torusSurface
        else {
          throw TopologyError.invalidFaceSurface(faceID)
        }
        return
      }
    }

    if case .analytic(let analyticSurface) = surface {
      switch analyticSurface {
      case .plane(let origin, let normal):
        return try validate(
          curve,
          liesOn: .plane(Plane3D(origin: origin, normal: normal)),
          faceID: faceID,
          tolerance: tolerance, using: &execution
        )
      case .cylinder(let origin, let axis, let radius):
        return try validate(
          curve,
          liesOn: .cylinder(Cylinder3D(origin: origin, axis: axis, radius: radius)),
          faceID: faceID,
          tolerance: tolerance, using: &execution
        )
      case .cone(let apex, let axis, let halfAngle):
        return try validate(
          curve,
          liesOnConeWithApex: apex,
          axis: axis,
          halfAngle: halfAngle,
          faceID: faceID,
          tolerance: tolerance, using: &execution
        )
      case .sphere(let center, let radius):
        return try validate(
          curve,
          liesOnSphereWithCenter: center,
          radius: radius,
          faceID: faceID,
          tolerance: tolerance, using: &execution
        )
      case .torus(let center, let axis, let majorRadius, let minorRadius):
        return try validate(
          curve,
          liesOnTorusWithCenter: center,
          axis: axis,
          majorRadius: majorRadius,
          minorRadius: minorRadius,
          faceID: faceID,
          tolerance: tolerance, using: &execution
        )
      }
    }

    if case .procedural(.offset(let offset)) = surface,
      let equivalent = try offset.exactChartPreservingSurface(
        tolerance: tolerance
      )
    {
      return try validate(
        curve,
        liesOn: equivalent,
        faceID: faceID,
        tolerance: tolerance, using: &execution
      )
    }

    switch (curve, surface) {
    case (.line(let line), .plane(let plane)):
      try line.validate(tolerance: tolerance)
      try plane.validate(tolerance: tolerance)
      let planeNormal = try plane.normal.normalized(tolerance: tolerance.distance)
      guard abs(line.direction.dot(planeNormal)) <= max(tolerance.distance, tolerance.angle) else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case (.line(let line), .cylinder(let cylinder)):
      try line.validate(tolerance: tolerance)
      try cylinder.validate(tolerance: tolerance)
      let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
      let direction = try line.direction.normalized(tolerance: tolerance.distance)
      guard abs(abs(direction.dot(axis)) - 1.0) <= max(tolerance.distance, tolerance.angle) else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
      try validate(line.origin, liesOn: surface, faceID: faceID, tolerance: tolerance, using: &execution)
    case (.circle(let circle), .plane(let plane)):
      try circle.validate(tolerance: tolerance)
      try plane.validate(tolerance: tolerance)
      try validate(circle.center, liesOn: surface, faceID: faceID, tolerance: tolerance, using: &execution)
      let circleNormal = try circle.normal.normalized(tolerance: tolerance.distance)
      let planeNormal = try plane.normal.normalized(tolerance: tolerance.distance)
      guard
        abs(abs(circleNormal.dot(planeNormal)) - 1.0) <= max(tolerance.distance, tolerance.angle)
      else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case (.circle(let circle), .cylinder(let cylinder)):
      try circle.validate(tolerance: tolerance)
      try cylinder.validate(tolerance: tolerance)
      let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
      let circleNormal = try circle.normal.normalized(tolerance: tolerance.distance)
      guard abs(abs(circleNormal.dot(axis)) - 1.0) <= max(tolerance.distance, tolerance.angle),
        abs(circle.radius - cylinder.radius) <= tolerance.distance
      else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
      let centerOffset = circle.center - cylinder.origin
      let radialCenterOffset = centerOffset - (axis * centerOffset.dot(axis))
      guard radialCenterOffset.length <= tolerance.distance else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case (.line(let line), .bSpline(let surface)):
      try line.validate(tolerance: tolerance)
      try surface.validate(tolerance: tolerance)
      guard try isLineOnBSplineBoundary(line, surface: surface, tolerance: tolerance, using: &execution) else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case (.bSpline(let curve), .bSpline(let surface)):
      try curve.validate(tolerance: tolerance)
      try surface.validate(tolerance: tolerance)
      guard
        try isBSplineCurveOnBSplineBoundary(
          curve,
          surface: surface,
          tolerance: tolerance, using: &execution
        )
      else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case (.circle, .bSpline):
      throw TopologyError.invalidFaceSurface(faceID)
    case (.bSpline, _):
      throw TopologyError.invalidFaceSurface(faceID)
    case (.implicit(let intersection), let surface):
      try intersection.validate(tolerance: tolerance)
      guard
        surface == intersection.firstSurface
          || surface == intersection.secondSurface
      else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case (.surfaceLift, _):
      throw TopologyError.invalidFaceSurface(faceID)
    case (.certifiedIntersection, _):
      throw TopologyError.invalidFaceSurface(faceID)
    case (.rigidImage, _):
      throw TopologyError.invalidFaceSurface(faceID)
    case (.originalPolyline, _), (.originalEndpointConnector, _), (.originalPlaneDerivative, _), (.originalDrafted, _), (.originalGuideTraversalChain, _), (.originalGuideEndpointConnector, _),
      (.originalConstructionChart, _), (.parameterImage, _):
      // Normalized original sources require their retained directed coedge path.
      throw TopologyError.invalidFaceSurface(faceID)
    case (.originalAngularTransport, _):
      // Angular source trims use the retained closed pcurve correspondence;
      // an untrimmed conic cannot be authorized by its underlying chart.
      throw TopologyError.invalidFaceSurface(faceID)
    case (.originalAffineWord, _):
      throw TopologyError.invalidFaceSurface(faceID)
    case (.affineImage, _):
      throw TopologyError.invalidFaceSurface(faceID)
    case (.analytic, _), (_, .analytic):
      throw TopologyError.invalidFaceSurface(faceID)
    case (_, .procedural):
      throw TopologyError.invalidFaceSurface(faceID)
    }
  }

  private func validate(
    _ curve: Curve3D,
    liesOnConeWithApex apex: Point3D,
    axis: Vector3D,
    halfAngle: Double,
    faceID: FaceID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    let normalizedAxis = try axis.normalized(tolerance: tolerance.distance)
    switch curve {
    case .line(let line):
      try line.validate(tolerance: tolerance)
      let direction = try line.direction.normalized(tolerance: tolerance.distance)
      let apexDistance = (apex - line.origin).cross(direction).length
      guard apexDistance <= tolerance.distance,
        abs(abs(direction.dot(normalizedAxis)) - cos(halfAngle)) <= tolerance.angle
      else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case .circle(let circle):
      try circle.validate(tolerance: tolerance)
      let normal = try circle.normal.normalized(tolerance: tolerance.distance)
      let centerOffset = circle.center - apex
      let axialDistance = centerOffset.dot(normalizedAxis)
      let radialCenter = centerOffset - normalizedAxis * axialDistance
      let expectedRadius = abs(axialDistance) * tan(halfAngle)
      guard abs(abs(normal.dot(normalizedAxis)) - 1.0) <= tolerance.angle,
        radialCenter.length <= tolerance.distance,
        abs(circle.radius - expectedRadius) <= tolerance.distance
      else {
        throw TopologyError.invalidFaceSurface(faceID)
      }
    case .analytic, .bSpline, .implicit, .surfaceLift,
      .certifiedIntersection, .rigidImage, .affineImage, .originalAffineWord, .originalAngularTransport, .originalPolyline, .originalEndpointConnector, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalConstructionChart, .parameterImage:
      throw TopologyError.invalidFaceSurface(faceID)
    }
  }

  private func validate(
    _ curve: Curve3D,
    liesOnSphereWithCenter center: Point3D,
    radius: Double,
    faceID: FaceID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    guard case .circle(let circle) = curve else {
      throw TopologyError.invalidFaceSurface(faceID)
    }
    try circle.validate(tolerance: tolerance)
    let normal = try circle.normal.normalized(tolerance: tolerance.distance)
    let centerOffset = circle.center - center
    let radialCenter = centerOffset - normal * centerOffset.dot(normal)
    guard radialCenter.length <= tolerance.distance,
      abs(hypot(centerOffset.length, circle.radius) - radius) <= tolerance.distance
    else {
      throw TopologyError.invalidFaceSurface(faceID)
    }
  }

  private func validate(
    _ curve: Curve3D,
    liesOnTorusWithCenter center: Point3D,
    axis: Vector3D,
    majorRadius: Double,
    minorRadius: Double,
    faceID: FaceID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    guard case .circle(let circle) = curve else {
      throw TopologyError.invalidFaceSurface(faceID)
    }
    try circle.validate(tolerance: tolerance)
    let normalizedAxis = try axis.normalized(tolerance: tolerance.distance)
    let normal = try circle.normal.normalized(tolerance: tolerance.distance)
    let centerOffset = circle.center - center
    let axialDistance = centerOffset.dot(normalizedAxis)
    let radialCenter = centerOffset - normalizedAxis * axialDistance
    let isAxialCoordinateCircle =
      abs(abs(normal.dot(normalizedAxis)) - 1.0) <= tolerance.angle
      && radialCenter.length <= tolerance.distance
      && abs(hypot(circle.radius - majorRadius, axialDistance) - minorRadius)
        <= tolerance.distance
    let isMeridionalCoordinateCircle =
      abs(normal.dot(normalizedAxis)) <= tolerance.angle
      && abs(axialDistance) <= tolerance.distance
      && abs(radialCenter.length - majorRadius) <= tolerance.distance
      && abs(circle.radius - minorRadius) <= tolerance.distance
      && abs(normal.dot(radialCenter)) <= tolerance.angle * max(majorRadius, 1.0)
    guard isAxialCoordinateCircle || isMeridionalCoordinateCircle else {
      throw TopologyError.invalidFaceSurface(faceID)
    }
  }

  private func isPointOnBSplineBoundary(
    _ point: Point3D,
    surface: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    for segment in try bSplineBoundarySegments(surface: surface, tolerance: tolerance, using: &execution) {
      try charge(using: &execution)
      if distance(point, toSegmentFrom: segment.start, to: segment.end) <= tolerance.distance {
        return true
      }
    }
    return false
  }

  private func isBSplineCurveOnBSplineBoundary(
    _ curve: BSplineCurve3D,
    surface: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    guard case .closed(let uLower, let uUpper) = surface.uDomain,
      case .closed(let vLower, let vUpper) = surface.vDomain
    else {
      return false
    }
    let boundaries = [
      try surface.uIsoparametricCurve(atV: vLower, tolerance: tolerance),
      try surface.uIsoparametricCurve(atV: vUpper, tolerance: tolerance),
      try surface.vIsoparametricCurve(atU: uLower, tolerance: tolerance),
      try surface.vIsoparametricCurve(atU: uUpper, tolerance: tolerance),
    ]
    for boundary in boundaries {
      try charge(using: &execution)
      if try bSplineCurvesMatch(
        curve,
        boundary,
        tolerance: tolerance, using: &execution
      ) {
        return true
      }
    }
    return false
  }

  private func bSplineCurvesMatch(
    _ lhs: BSplineCurve3D,
    _ rhs: BSplineCurve3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try tolerance.validate()
    if lhs == rhs {
      return true
    }
    let reversedRHS = try rhs.reversed(tolerance: tolerance)
    if lhs == reversedRHS { return true }
    if try commonBasisCurvesMatch(lhs, rhs, tolerance: tolerance, using: &execution) {
      return true
    }
    return try commonBasisCurvesMatch(
      lhs,
      reversedRHS,
      tolerance: tolerance, using: &execution
    )
  }

  private func commonBasisCurvesMatch(
    _ lhs: BSplineCurve3D,
    _ rhs: BSplineCurve3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    let common = try DefaultBSplineCurveCommonBasisResolver().resolve(
      first: lhs,
      second: rhs,
      tolerance: tolerance
    )
    guard common.first.degree == common.second.degree,
      common.first.knots == common.second.knots,
      common.first.controlPointCount == common.second.controlPointCount,
      let firstWeight = common.first.weights.first,
      let secondWeight = common.second.weights.first,
      firstWeight > 0.0,
      secondWeight > 0.0
    else {
      return false
    }
    let weightScale = firstWeight / secondWeight
    guard weightScale.isFinite, weightScale > 0.0 else {
      return false
    }
    for index in 0..<common.first.controlPointCount {
      try charge(using: &execution)
      guard
        common.first.controlPoints[index].isApproximatelyEqual(
          to: common.second.controlPoints[index],
          tolerance: tolerance.distance
        )
      else {
        return false
      }
      let expectedWeight = common.second.weights[index] * weightScale
      let weightMagnitude = max(
        abs(common.first.weights[index]),
        abs(expectedWeight),
        1.0
      )
      let weightTolerance = max(
        tolerance.relative * weightMagnitude,
        Double.ulpOfOne * weightMagnitude * 512.0
      )
      guard
        abs(common.first.weights[index] - expectedWeight)
          <= weightTolerance
      else {
        return false
      }
    }
    return true
  }

  private func isLineOnBSplineBoundary(
    _ line: Line3D,
    surface: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    let direction = try line.direction.normalized(tolerance: tolerance.distance)
    for segment in try bSplineBoundarySegments(surface: surface, tolerance: tolerance, using: &execution) {
      try charge(using: &execution)
      let segmentDirection = segment.end - segment.start
      guard segmentDirection.length > tolerance.distance else {
        continue
      }
      let normalizedSegment = try segmentDirection.normalized(tolerance: tolerance.distance)
      let isParallel =
        normalizedSegment.cross(direction).length <= max(tolerance.distance, tolerance.angle)
      let containsBoundaryStart =
        (segment.start - line.origin).cross(direction).length <= tolerance.distance
      let containsBoundaryEnd =
        (segment.end - line.origin).cross(direction).length <= tolerance.distance
      if isParallel && containsBoundaryStart && containsBoundaryEnd {
        return true
      }
    }
    return false
  }

  private func bSplineBoundarySegments(
    surface: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [(start: Point3D, end: Point3D)] {
    let uBounds = try parameterBounds(surface.uDomain, tolerance: tolerance, using: &execution)
    let vBounds = try parameterBounds(surface.vDomain, tolerance: tolerance, using: &execution)
    let bottomLeft = try surface.point(u: uBounds.lower, v: vBounds.lower, tolerance: tolerance, using: &execution)
    let bottomRight = try surface.point(u: uBounds.upper, v: vBounds.lower, tolerance: tolerance, using: &execution)
    let topRight = try surface.point(u: uBounds.upper, v: vBounds.upper, tolerance: tolerance, using: &execution)
    let topLeft = try surface.point(u: uBounds.lower, v: vBounds.upper, tolerance: tolerance, using: &execution)
    return [
      (bottomLeft, bottomRight),
      (bottomRight, topRight),
      (topRight, topLeft),
      (topLeft, bottomLeft),
    ]
  }

  private func parameterBounds(
    _ domain: ParameterDomain,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (lower: Double, upper: Double) {
    try domain.validate(tolerance: tolerance)
    guard case .closed(let lower, let upper) = domain else {
      throw GeometryError.invalidDistance(0.0)
    }
    return (lower, upper)
  }

  private func distance(
    _ point: Point3D,
    toSegmentFrom start: Point3D,
    to end: Point3D
  ) -> Double {
    let segment = end - start
    let lengthSquared = segment.dot(segment)
    guard lengthSquared > 0.0 else {
      return (point - start).length
    }
    let projection = max(0.0, min(1.0, (point - start).dot(segment) / lengthSquared))
    let closest = start + segment * projection
    return (point - closest).length
  }

  private func validate(loop: Loop, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    guard !loop.edges.isEmpty else {
      throw TopologyError.openLoop(loop.id)
    }
    let orderedVertexIDs = try orderedVertexIDs(for: loop, using: &execution)
    guard let firstVertexID = orderedVertexIDs.first, let lastEdge = loop.edges.last else {
      throw TopologyError.openLoop(loop.id)
    }
    let lastEndID = try endVertexID(for: lastEdge, using: &execution)
    guard firstVertexID == lastEndID else {
      throw TopologyError.openLoop(loop.id)
    }
    guard let first = vertices[firstVertexID]?.point else {
      throw TopologyError.missingReference("Missing vertex \(firstVertexID).")
    }
    guard let lastEnd = vertices[lastEndID]?.point else {
      throw TopologyError.missingReference("Missing vertex \(lastEndID).")
    }
    guard first.isApproximatelyEqual(to: lastEnd, tolerance: tolerance.distance) else {
      throw TopologyError.openLoop(loop.id)
    }
  }

  private func orderedVertexIDs(for loop: Loop, using execution: inout OriginalQueryExecution) throws -> [VertexID] {
    var ordered: [VertexID] = []
    var expectedStart: VertexID?
    for orientedEdge in loop.edges {
      try charge(using: &execution)
      let start = try startVertexID(for: orientedEdge, using: &execution)
      let end = try endVertexID(for: orientedEdge, using: &execution)
      if let expectedStart, expectedStart != start {
        throw TopologyError.openLoop(loop.id)
      }
      try OriginalParameterQueryStorage.append(start, to: &ordered, using: &execution)
      expectedStart = end
    }
    return ordered
  }

  private func startVertexID(for orientedEdge: Coedge, using execution: inout OriginalQueryExecution) throws -> VertexID {
    guard let edge = edges[orientedEdge.edgeID] else {
      throw TopologyError.missingReference("Missing edge \(orientedEdge.edgeID).")
    }
    guard geometry.curves[edge.curveID] != nil else {
      throw TopologyError.missingReference("Missing curve \(edge.curveID).")
    }
    guard vertices[edge.startVertexID] != nil, vertices[edge.endVertexID] != nil else {
      throw TopologyError.invalidEdge(edge.id)
    }
    switch orientedEdge.orientation {
    case .forward:
      return edge.startVertexID
    case .reversed:
      return edge.endVertexID
    }
  }

  private func endVertexID(for orientedEdge: Coedge, using execution: inout OriginalQueryExecution) throws -> VertexID {
    guard let edge = edges[orientedEdge.edgeID] else {
      throw TopologyError.missingReference("Missing edge \(orientedEdge.edgeID).")
    }
    guard geometry.curves[edge.curveID] != nil else {
      throw TopologyError.missingReference("Missing curve \(edge.curveID).")
    }
    guard vertices[edge.startVertexID] != nil, vertices[edge.endVertexID] != nil else {
      throw TopologyError.invalidEdge(edge.id)
    }
    switch orientedEdge.orientation {
    case .forward:
      return edge.endVertexID
    case .reversed:
      return edge.startVertexID
    }
  }

  private func validateTopologyTables(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    for (bodyID, body) in bodies {
      try charge(using: &execution)
      guard body.id == bodyID else {
        throw TopologyError.unreferencedTopology("Body table key does not match body ID \(bodyID).")
      }
    }
    for (shellID, shell) in shells {
      try charge(using: &execution)
      guard shell.id == shellID else {
        throw TopologyError.unreferencedTopology(
          "Shell table key does not match shell ID \(shellID).")
      }
    }
    for (faceID, face) in faces {
      try charge(using: &execution)
      guard face.id == faceID else {
        throw TopologyError.unreferencedTopology("Face table key does not match face ID \(faceID).")
      }
    }
    for (loopID, loop) in loops {
      try charge(using: &execution)
      guard loop.id == loopID else {
        throw TopologyError.unreferencedTopology("Loop table key does not match loop ID \(loopID).")
      }
    }
    for (edgeID, edge) in edges {
      try charge(using: &execution)
      guard edge.id == edgeID else {
        throw TopologyError.invalidEdge(edge.id)
      }
      if edge.startVertexID == edge.endVertexID,
         try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: maximumSubdivisionDepth,
             remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth).kind(of: edge, in: model, tolerance: tolerance, using: &execution) == .open {
        throw TopologyError.invalidEdge(edge.id)
      }
      try validateEdgeGeometry(edge, edgeID: edgeID, tolerance: tolerance, using: &execution)
    }
    for (vertexID, vertex) in vertices {
      try charge(using: &execution)
      guard vertex.id == vertexID else {
        throw TopologyError.unreferencedTopology(
          "Vertex table key does not match vertex ID \(vertexID).")
      }
      try vertex.point.validate()
    }
  }

  private func validateEdgeGeometry(_ edge: Edge, edgeID: EdgeID, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws
  {
    guard let curve = geometry.curves[edge.curveID] else {
      throw TopologyError.missingReference("Missing curve \(edge.curveID).")
    }
    guard let startPoint = vertices[edge.startVertexID]?.point,
      let endPoint = vertices[edge.endVertexID]?.point
    else {
      throw TopologyError.invalidEdge(edgeID)
    }
    if startPoint.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance),
       try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: maximumSubdivisionDepth,
             remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth).kind(of: edge, in: model, tolerance: tolerance, using: &execution) == .open {
      throw TopologyError.invalidEdge(edgeID)
    }
    if let trim = edge.trim {
      try trim.validate(on: curve, edgeID: edgeID, tolerance: tolerance,
        remainingSourceDepth: remainingSourceDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth ?? 32,
        maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
      do {
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
          remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let startResidual = try originalPointResidual(from: startPoint, at: trim.startParameter,
          prepared: prepared, tolerance: tolerance, using: &execution)
        let endResidual = try originalPointResidual(from: endPoint, at: trim.endParameter,
          prepared: prepared, tolerance: tolerance, using: &execution)
        guard startResidual <= tolerance.distance * 8, endResidual <= tolerance.distance * 8 else {
          throw TopologyError.invalidTrim(edgeID)
        }
        return
      }
      let curveStart = try point(on: curve, at: trim.startParameter, tolerance: tolerance, using: &execution)
      let curveEnd = try point(on: curve, at: trim.endParameter, tolerance: tolerance, using: &execution)
      // Boolean junction vertices snap to canonical points on source
      // boundary geometry, up to eight tolerances from the exact
      // curve position at the trim parameter.
      guard startPoint.isApproximatelyEqual(to: curveStart, tolerance: tolerance.distance * 8.0),
        endPoint.isApproximatelyEqual(to: curveEnd, tolerance: tolerance.distance * 8.0)
      else {
        throw TopologyError.invalidTrim(edgeID)
      }
    } else {
      let isUnboundedLine: Bool
      switch curve {
      case .line, .analytic(.line):
        isUnboundedLine = true
      case .parameterImage(let image):
        isUnboundedLine = try isUnboundedLineCurve(image.source, using: &execution)
      case .rigidImage(let image):
        isUnboundedLine = try isUnboundedLineCurve(image.source, using: &execution)
      case .originalAffineWord(let image):
        isUnboundedLine = try isUnboundedLineCurve(image.source, using: &execution)
      case .affineImage(let image):
        isUnboundedLine = try isUnboundedLineCurve(image.source, using: &execution)
      case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
        .certifiedIntersection, .originalAngularTransport, .originalPolyline, .originalEndpointConnector, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalConstructionChart:
        isUnboundedLine = false
      }
      guard isUnboundedLine else {
        throw TopologyError.invalidTrim(edgeID)
      }
      try validate(startPoint, liesOn: curve, edgeID: edgeID, tolerance: tolerance, using: &execution)
      try validate(endPoint, liesOn: curve, edgeID: edgeID, tolerance: tolerance, using: &execution)
    }
  }

  private func originalPointResidual(from point: Point3D, at parameter: Double,
    prepared: PreparedCurveDifferentialEncloser, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
    let bounds = try prepared.positionBounds(over: ScalarInterval(lower: parameter, upper: parameter),
      tolerance: tolerance, maximumSpanCount: 1_048_576,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, using: &execution)
    let originalPoint = IntervalVector3DBounds(x: .exact(point.x), y: .exact(point.y), z: .exact(point.z))
    let residual = (bounds - originalPoint).lengthUpperBound
    guard residual.isFinite else {
      throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Original endpoint residual is not finitely enclosed.")
    }
    return residual
  }

  private func point(on curve: Curve3D, at parameter: Double, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws
    -> Point3D
  {
    try curve.point(at: parameter, tolerance: tolerance, using: &execution)
  }

  private func validate(
    _ point: Point3D,
    liesOn curve: Curve3D,
    edgeID: EdgeID,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    switch curve {
    case .line(let line):
      try line.validate(tolerance: tolerance)
      let offset = point - line.origin
      guard offset.cross(line.direction).length <= tolerance.distance else {
        throw TopologyError.invalidEdge(edgeID)
      }
    case .circle(let circle):
      try circle.validate(tolerance: tolerance)
      let normal = try circle.normal.normalized(tolerance: tolerance.distance)
      let offset = point - circle.center
      guard abs(offset.dot(normal)) <= tolerance.distance,
        abs(offset.length - circle.radius) <= tolerance.distance
      else {
        throw TopologyError.invalidEdge(edgeID)
      }
    case .analytic(let curve):
      try curve.validate(tolerance: tolerance)
      switch curve {
      case .line(let origin, let direction):
        try validate(
          point,
          liesOn: .line(Line3D(origin: origin, direction: direction)),
          edgeID: edgeID,
          tolerance: tolerance, using: &execution
        )
      case .circle(let center, let normal, let radius),
        .arc(let center, let normal, let radius, _, _):
        try validate(
          point,
          liesOn: .circle(Circle3D(center: center, normal: normal, radius: radius)),
          edgeID: edgeID,
          tolerance: tolerance, using: &execution
        )
      case .ellipse(let center, let normal, let majorAxis, let majorRadius, let minorRadius):
        let minorAxis = try normal.cross(majorAxis).normalized(tolerance: tolerance.distance)
        let offset = point - center
        let planeResidual = abs(offset.dot(normal))
        let majorCoordinate = offset.dot(majorAxis) / majorRadius
        let minorCoordinate = offset.dot(minorAxis) / minorRadius
        let ellipseResidual = abs(
          majorCoordinate * majorCoordinate + minorCoordinate * minorCoordinate - 1.0
        )
        let normalizedDistanceTolerance = tolerance.distance / min(majorRadius, minorRadius)
        guard planeResidual <= tolerance.distance,
          ellipseResidual <= max(normalizedDistanceTolerance, tolerance.angle)
        else {
          throw TopologyError.invalidEdge(edgeID)
        }
      case .hyperbola, .parabola, .planeTorus:
        _ = try Curve3D.analytic(curve).parameterProjection(
          of: point,
          tolerance: tolerance, using: &execution
        )
      }
    case .bSpline:
      throw TopologyError.invalidEdge(edgeID)
    case .implicit(let intersection):
      _ = try Curve3D.implicit(intersection).parameterProjection(
        of: point,
        tolerance: tolerance, using: &execution
      )
    case .parameterImage(let image):
      _ = try Curve3D.parameterImage(image).parameterProjection(of: point, tolerance: tolerance, using: &execution)
    case .surfaceLift(let lift):
      _ = try Curve3D.surfaceLift(lift).parameterProjection(
        of: point,
        tolerance: tolerance, using: &execution
      )
    case .certifiedIntersection(let intersection):
      _ = try Curve3D.certifiedIntersection(intersection).parameterProjection(
        of: point,
        tolerance: tolerance, using: &execution
      )
    case .rigidImage(let image):
      try validate(
        image.transform.inverted().applying(to: point),
        liesOn: image.source,
        edgeID: edgeID,
        tolerance: tolerance, using: &execution
      )
    case .originalAffineWord:
      try validateOriginalLinePoint(point, on: curve, edgeID: edgeID, tolerance: tolerance, using: &execution)
    case .originalAngularTransport, .originalPolyline, .originalEndpointConnector, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalConstructionChart:
      // Untrimmed normalized sources are rejected before this membership path;
      // directed trims use the owning closed original endpoint receipts.
      throw TopologyError.invalidEdge(edgeID)
    case .affineImage:
      guard let line = curve.exactLinearLocus else {
        throw TopologyError.invalidEdge(edgeID)
      }
      let distance =
        (point - line.origin).cross(line.direction).length
        / line.direction.length
      guard distance <= tolerance.distance else {
        throw TopologyError.invalidEdge(edgeID)
      }
    }
  }

  private func validateOriginalLinePoint(_ point: Point3D, on curve: Curve3D,
    edgeID: EdgeID, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    guard try isUnboundedLineCurve(curve, using: &execution) else { throw TopologyError.invalidEdge(edgeID) }
    let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
      remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    let source = try prepared.closedNativeJets(over: .init(lower: 0, upper: 0),
      tolerance: tolerance, maximumSpanCount: 1_048_576,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, using: &execution)
    for span in source.spans {
      try charge(using: &execution)
      let jet = span.jet
      let origin = IntervalVector3DBounds(x: jet.x.value, y: jet.y.value, z: jet.z.value)
      let originalDirection = IntervalVector3DBounds(x: jet.x.derivativeU,
        y: jet.y.derivativeU, z: jet.z.derivativeU)
      let scale = max(abs(originalDirection.x.lower), abs(originalDirection.x.upper),
        abs(originalDirection.y.lower), abs(originalDirection.y.upper),
        abs(originalDirection.z.lower), abs(originalDirection.z.upper))
      guard scale.isFinite, scale > 0,
        let dx = originalDirection.x.divided(by: .exact(scale)),
        let dy = originalDirection.y.divided(by: .exact(scale)),
        let dz = originalDirection.z.divided(by: .exact(scale)),
        dx.isFinite, dy.isFinite, dz.isFinite else {
        throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Original line direction has no finite scaled interval enclosure.")
      }
      let direction = IntervalVector3DBounds(x: dx, y: dy, z: dz)
      let offset = IntervalVector3DBounds(x: .exact(point.x), y: .exact(point.y),
        z: .exact(point.z)) - origin
      let numerator = offset.cross(direction).lengthUpperBound
      let denominator = direction.lengthLowerBound
      guard numerator.isFinite, denominator.isFinite, denominator > 0,
        let residual = OutwardScalarInterval.exact(numerator)
          .divided(by: .exact(denominator)), residual.isFinite else {
        throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Original affine line membership has no finite regular source bound.")
      }
      guard residual.upper <= tolerance.distance else { throw TopologyError.invalidEdge(edgeID) }
    }
  }

  private func containsOriginalWord(_ curve: Curve3D, using execution: inout OriginalQueryExecution) throws -> Bool {
    try charge(using: &execution)
    switch curve {
    case .originalAffineWord: return true
    case .parameterImage(let image): return try containsOriginalWord(image.source, using: &execution)
    case .rigidImage(let image): return try containsOriginalWord(image.source, using: &execution)
    case .affineImage(let image): return try containsOriginalWord(image.source, using: &execution)
    default: return false
    }
  }

  private func originalLineParameter(_ point: Point3D, on curve: Curve3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
    guard try isUnboundedLineCurve(curve, using: &execution) else {
      throw GeometryConversionError.invalidInput("Original line parameter requires an unbounded linear source law.")
    }
    let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
      remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    let receipt = try prepared.closedNativeJets(over: .init(lower: 0, upper: 0),
      tolerance: tolerance, maximumSpanCount: 1_048_576,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, using: &execution)
    guard let span = receipt.spans.first, receipt.spans.count == 1 else {
      throw GeometryConversionError.invalidInput("Original line station requires one complete retained chart jet.")
    }
    var quotient: OutwardScalarInterval?
    var strength = 0.0
    func consider(_ coordinate: Double, _ jet: SurfaceIntervalJet) throws {
      try charge(using: &execution)
      let direction = jet.derivativeU
      guard direction.absoluteLowerBound > strength,
        let candidate = (OutwardScalarInterval.exact(coordinate) - jet.value).divided(by: direction),
        candidate.isFinite else { return }
      strength = direction.absoluteLowerBound; quotient = candidate
    }
    try consider(point.x, span.jet.x); try consider(point.y, span.jet.y); try consider(point.z, span.jet.z)
    guard let quotient, strength > 0, quotient.midpoint.isFinite else {
      throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Original line parameter has no finite regular coordinate quotient.")
    }
    let parameter = quotient.midpoint
    let bounds = try prepared.closedNativeJets(over: .init(lower: parameter, upper: parameter),
      tolerance: tolerance, maximumSpanCount: 1_048_576,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, using: &execution)
    guard let final = bounds.spans.first, bounds.spans.count == 1 else {
      throw GeometryConversionError.invalidInput("Original line parameter needs its complete closed position receipt.")
    }
    let position = IntervalVector3DBounds(x: final.jet.x.value, y: final.jet.y.value, z: final.jet.z.value)
    let vertex = IntervalVector3DBounds(x: .exact(point.x), y: .exact(point.y), z: .exact(point.z))
    let residual = (position - vertex).lengthUpperBound
    guard residual.isFinite, residual <= tolerance.distance * 8 else {
      throw KernelError(phase: .topology, code: .topologyFailure, residual: residual,
        tolerance: tolerance, message: "Original line candidate parameter does not meet the existing junction law.")
    }
    return parameter
  }

  private func isUnboundedLineCurve(_ curve: Curve3D, using execution: inout OriginalQueryExecution) throws -> Bool {
    try charge(using: &execution)
    guard case .unbounded = curve.parameterDomain else { return false }
    switch curve {
    case .line, .analytic(.line):
      return true
    case .parameterImage(let image):
      return try isUnboundedLineCurve(image.source, using: &execution)
    case .rigidImage(let image):
      return try isUnboundedLineCurve(image.source, using: &execution)
    case .originalAffineWord(let image):
      return try isUnboundedLineCurve(image.source, using: &execution)
    case .affineImage(let image):
      return try isUnboundedLineCurve(image.source, using: &execution)
    case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
      .certifiedIntersection, .originalAngularTransport, .originalPolyline, .originalEndpointConnector, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalConstructionChart:
      return false
    }
  }

  private func validateNoDuplicateReferences<ID: Hashable & CustomStringConvertible>(
    _ ids: [ID],
    owner: String,
    child: String, using execution: inout OriginalQueryExecution
  ) throws {
    var seen = Set<ID>()
    for id in ids {
      try charge(using: &execution)
      guard try OriginalParameterQueryStorage.insert(id, in: &seen, using: &execution) else {
        throw TopologyError.duplicateTopologyReference(
          "\(owner) contains duplicate \(child) \(id).")
      }
    }
  }

  private func recordOwnership<ID: Hashable & CustomStringConvertible>(
    _ id: ID,
    in owned: inout Set<ID>,
    child: String, using execution: inout OriginalQueryExecution
  ) throws {
    guard try OriginalParameterQueryStorage.insert(id, in: &owned, using: &execution) else {
      throw TopologyError.duplicateTopologyReference(
        "\(child) \(id) is referenced by multiple owners.")
    }
  }

  private func declaredKeys<ID: Hashable, Value>(_ table: PersistentMap<ID, Value>, using execution: inout OriginalQueryExecution) throws -> Set<ID> {
    var result = Set<ID>()
    for (id, _) in table { try OriginalParameterQueryStorage.insert(id, in: &result, using: &execution) }
    return result
  }

  private func shellIDs(of body: Body, using execution: inout OriginalQueryExecution) throws -> [ShellID] {
    try body.originalShellIDs(using: &execution)
  }

  private func validateReferences<ID: Hashable & CustomStringConvertible>(
    _ referenced: Set<ID>,
    cover declared: Set<ID>,
    label: String, using execution: inout OriginalQueryExecution
  ) throws {
    var missing: ID?
    for id in referenced {
      try charge(using: &execution)
      if !declared.contains(id), missing == nil || id.description < missing!.description { missing = id }
    }
    if let missing { throw TopologyError.missingReference("Missing \(label) \(missing).") }
    var unreferenced: ID?
    for id in declared {
      try charge(using: &execution)
      if !referenced.contains(id), unreferenced == nil || id.description < unreferenced!.description { unreferenced = id }
    }
    if let unreferenced { throw TopologyError.unreferencedTopology("Unreferenced \(label) \(unreferenced).") }
  }
}

private struct EdgeUse {
  var forward: Int = 0
  var reversed: Int = 0

  var count: Int {
    forward + reversed
  }

  mutating func record(_ orientation: Orientation) {
    switch orientation {
    case .forward:
      forward += 1
    case .reversed:
      reversed += 1
    }
  }
}
