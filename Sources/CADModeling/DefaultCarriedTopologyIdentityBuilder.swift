import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct DefaultCarriedTopologyIdentityBuilder: CarriedTopologyIdentityBuilding {
  package init() {}

  package func identity(
    featureID: FeatureID,
    bodyID: BodyID,
    model: BRepModel,
    context: EvaluationContext
  ) throws -> CarriedTopologyIdentity {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try identity(
      featureID: featureID, bodyID: bodyID, model: model, context: context, using: &execution)
  }

  package func identity(
    featureID: FeatureID,
    bodyID: BodyID,
    model: BRepModel,
    context: EvaluationContext, using execution: inout OriginalQueryExecution
  ) throws -> CarriedTopologyIdentity {
    try execution.consumeWork(1)
    let references = try topologyReferences(bodyID: bodyID, model: model, using: &execution)
    try execution.retainStorage(
      count: references.count,
      stride: MemoryLayout<(SubshapeID, TopologyReference)>.stride
        + MemoryLayout<(SubshapeID, TopologyLineage)>.stride + MemoryLayout<(String, Int)>.stride)
    var subshapes: [SubshapeID: TopologyReference] = [:]
    var lineage: [SubshapeID: TopologyLineage] = [:]
    var ordinals: [String: Int] = [:]
    for entry in references {
      try execution.consumeWork(1)

      for _ in entry.role.utf8 { try execution.consumeWork(1) }
      let ordinal = ordinals[entry.role, default: 0]
      let nextOrdinal = ordinal.addingReportingOverflow(1)
      guard !nextOrdinal.overflow else { throw ExactScalarFailure.countOverflow }
      ordinals[entry.role] = nextOrdinal.partialValue
      let output = SubshapeID(featureID: featureID, role: entry.role, ordinal: ordinal)
      for _ in output.role.utf8 { try execution.consumeWork(1) }
      subshapes[output] = entry.reference
      let parents = try sourceSubshapeIDs(for: entry.reference, context: context, using: &execution)
      let relation: TopologyLineageRelation =
        switch parents.count {
        case 0: .generated
        case 1: .preserved
        default: .merged
        }
      // The Core checked entry retains this sorted unique array and performs
      // linear validity checks; admit their actual parent and role reads here.
      try execution.consumeWork(1)
      var previous: SubshapeID?
      for parent in parents {
        try execution.consumeWork(1)
        for _ in parent.role.utf8 { try execution.consumeWork(1) }
        for _ in output.role.utf8 { try execution.consumeWork(1) }
        if let previous {
          try execution.consumeWork(1)
          for _ in previous.role.utf8 { try execution.consumeWork(1) }
          for _ in parent.role.utf8 { try execution.consumeWork(1) }
        }
        previous = parent
      }
      guard let carriedLineage = TopologyLineage(output: output,
        canonicalParents: parents, relation: relation) else {
        throw KernelError(phase: .topology, code: .invalidInput, featureID: featureID,
          tolerance: context.tolerance,
          message: "Carried topology requires valid strictly canonical parent lineage.")
      }
      for _ in output.role.utf8 { try execution.consumeWork(1) }
      lineage[output] = carriedLineage
    }
    return CarriedTopologyIdentity(subshapes: subshapes, lineage: lineage)
  }

  private func topologyReferences(
    bodyID: BodyID,
    model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> [(role: String, reference: TopologyReference)] {
    try execution.consumeWork(1)
    guard let body = model.bodies[bodyID] else {
      throw TopologyError.missingReference("Carried topology body is missing.")
    }
    var faceIDs = Set<FaceID>()
    var edgeIDs = Set<EdgeID>()
    var vertexIDs = Set<VertexID>()
    for shellID in try body.originalShellIDs(using: &execution) {
      try execution.consumeWork(1)

      guard let shell = model.shells[shellID] else {
        throw TopologyError.missingReference("Carried topology shell is missing.")
      }
      for faceID in shell.faceIDs {
        try execution.consumeWork(1)

        if !faceIDs.contains(faceID) {
          try execution.retainStorage(count: 1, stride: MemoryLayout<FaceID>.stride)
          faceIDs.insert(faceID)
        }
        guard let face = model.faces[faceID] else {
          throw TopologyError.missingReference("Carried topology face is missing.")
        }
        for loopID in face.loops {
          try execution.consumeWork(1)

          guard let loop = model.loops[loopID] else {
            throw TopologyError.missingReference("Carried topology loop is missing.")
          }
          for coedge in loop.coedges {
            try execution.consumeWork(1)

            if !edgeIDs.contains(coedge.edgeID) {
              try execution.retainStorage(count: 1, stride: MemoryLayout<EdgeID>.stride)
              edgeIDs.insert(coedge.edgeID)
            }
            guard let edge = model.edges[coedge.edgeID] else {
              throw TopologyError.missingReference("Carried topology edge is missing.")
            }
            try execution.retainStorage(count: 2, stride: MemoryLayout<VertexID>.stride)
            for vertexID in [edge.startVertexID, edge.endVertexID] {
              try execution.consumeWork(1)
              if !vertexIDs.contains(vertexID) {
                try execution.retainStorage(count: 1, stride: MemoryLayout<VertexID>.stride)
                vertexIDs.insert(vertexID)
              }
            }
          }
        }
      }
    }
    var referenceCount = 1
    try execution.retainStorage(count: 3, stride: MemoryLayout<Int>.stride)
    for count in [faceIDs.count, edgeIDs.count, vertexIDs.count] {
      try execution.consumeWork(1)
      let nextCount = referenceCount.addingReportingOverflow(count)
      guard !nextCount.overflow else { throw ExactScalarFailure.countOverflow }
      referenceCount = nextCount.partialValue
    }
    try execution.retainStorage(
      count: referenceCount,
      stride: MemoryLayout<(role: String, reference: TopologyReference)>.stride)
    var references: [(role: String, reference: TopologyReference)] = [
      (GeneratedSubshapeRole.body.rawValue, .body(bodyID))
    ]
    references.reserveCapacity(referenceCount)
    try execution.retainStorage(
      count: faceIDs.count,
      stride: MemoryLayout<FaceID>.stride
        + MemoryLayout<(role: String, reference: TopologyReference)>.stride)
    references.append(
      contentsOf: try faceIDs.sorted { first, second in
        try execution.consumeWork(1)
        return first < second
      }.map {
        try execution.consumeWork(1)
        return (GeneratedSubshapeRole.face.rawValue, .face($0))
      })
    try execution.retainStorage(
      count: edgeIDs.count,
      stride: MemoryLayout<EdgeID>.stride
        + MemoryLayout<(role: String, reference: TopologyReference)>.stride)
    references.append(
      contentsOf: try edgeIDs.sorted { first, second in
        try execution.consumeWork(1)
        return first < second
      }.map {
        try execution.consumeWork(1)
        return (GeneratedSubshapeRole.edge.rawValue, .edge($0))
      })
    try execution.retainStorage(
      count: vertexIDs.count,
      stride: MemoryLayout<VertexID>.stride
        + MemoryLayout<(role: String, reference: TopologyReference)>.stride)
    references.append(
      contentsOf: try vertexIDs.sorted { first, second in
        try execution.consumeWork(1)
        return first < second
      }.map {
        try execution.consumeWork(1)
        return (GeneratedSubshapeRole.vertex.rawValue, .vertex($0))
      })
    return references
  }

  private func sourceSubshapeIDs(
    for reference: TopologyReference,
    context: EvaluationContext, using execution: inout OriginalQueryExecution
  ) throws -> [SubshapeID] {
    try execution.consumeWork(1)
    return try context.subshapeIDs(for: reference, using: &execution)
  }
}
