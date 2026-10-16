import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Complete exact topology input for one body sewing operation.
public struct BRepSewingRequest: Sendable {
  public let featureID: FeatureID
  public let bodyTopology: BRepSewingBodyTopology
  public let shells: [BRepSewingShell]
  public let bodyParentSubshapeIDs: [SubshapeID]
  public let topologyNamespace: BRepSewingTopologyNamespace

  public var bodyKind: BodyKind {
    bodyTopology.bodyKind
  }

  public init(
    featureID: FeatureID,
    bodyTopology: BRepSewingBodyTopology,
    shells: [BRepSewingShell],
    bodyParentSubshapeIDs: [SubshapeID] = [],
    topologyNamespace: BRepSewingTopologyNamespace = .feature
  ) {
    self.featureID = featureID
    self.bodyTopology = bodyTopology
    self.shells = shells
    self.bodyParentSubshapeIDs = Array(Set(bodyParentSubshapeIDs)).sorted()
    self.topologyNamespace = topologyNamespace
  }

  public init(
    featureID: FeatureID,
    bodyKind: BodyKind,
    shells: [BRepSewingShell],
    bodyParentSubshapeIDs: [SubshapeID] = [],
    topologyNamespace: BRepSewingTopologyNamespace = .feature
  ) {
    self.featureID = featureID
    self.bodyTopology = Self.inferredBodyTopology(
      bodyKind: bodyKind,
      shells: shells
    )
    self.shells = shells
    self.bodyParentSubshapeIDs = Array(Set(bodyParentSubshapeIDs)).sorted()
    self.topologyNamespace = topologyNamespace
  }

  package init(
    featureID: FeatureID,
    bodyTopology: BRepSewingBodyTopology,
    shells: [BRepSewingShell],
    bodyParentSubshapeIDs: [SubshapeID] = [],
    topologyNamespace: BRepSewingTopologyNamespace = .feature,
    using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)
    self.featureID = featureID
    self.bodyTopology = bodyTopology
    self.shells = shells
    self.bodyParentSubshapeIDs = try AdmittedSewingProvenance.canonical(
      bodyParentSubshapeIDs, using: &execution)
    self.topologyNamespace = topologyNamespace
  }

  package init(
    featureID: FeatureID,
    bodyKind: BodyKind,
    shells: [BRepSewingShell],
    bodyParentSubshapeIDs: [SubshapeID] = [],
    topologyNamespace: BRepSewingTopologyNamespace = .feature,
    using execution: inout OriginalQueryExecution
  ) throws {
    let topology = try Self.inferredBodyTopology(
      bodyKind: bodyKind, shells: shells, using: &execution)
    try self.init(
      featureID: featureID, bodyTopology: topology, shells: shells,
      bodyParentSubshapeIDs: bodyParentSubshapeIDs, topologyNamespace: topologyNamespace,
      using: &execution)
  }

  private static func inferredBodyTopology(
    bodyKind: BodyKind, shells: [BRepSewingShell], using execution: inout OriginalQueryExecution
  ) throws -> BRepSewingBodyTopology {
    try execution.consumeWork(1)
    try execution.retainStorage(count: shells.count, stride: MemoryLayout<String>.stride)
    if bodyKind == .sheet {
      return .sheet(
        shellStableIDs: try shells.map { shell in
          try execution.consumeWork(1)
          return shell.stableID
        })
    }
    try execution.retainStorage(count: shells.count, stride: MemoryLayout<String>.stride)
    var outerShellStableIDs: [String] = []
    var voidShellStableIDs: [String] = []
    for shell in shells {
      try execution.consumeWork(1)
      if shell.orientation == .forward { outerShellStableIDs.append(shell.stableID) }
      if shell.orientation == .reversed { voidShellStableIDs.append(shell.stableID) }
    }
    if outerShellStableIDs.count == 1 {
      try execution.retainStorage(count: 1, stride: MemoryLayout<BRepSewingSolidComponent>.stride)
      return .solid(components: [
        BRepSewingSolidComponent(
          outerShellStableID: outerShellStableIDs[0], voidShellStableIDs: voidShellStableIDs)
      ])
    }
    try execution.retainStorage(
      count: outerShellStableIDs.count, stride: MemoryLayout<BRepSewingSolidComponent>.stride)
    return .solid(
      components: try outerShellStableIDs.map { id in
        try execution.consumeWork(1)
        return BRepSewingSolidComponent(outerShellStableID: id)
      })
  }

  public func namespaced(
    as topologyNamespace: BRepSewingTopologyNamespace
  ) -> BRepSewingRequest {
    BRepSewingRequest(
      featureID: featureID,
      bodyTopology: bodyTopology,
      shells: shells,
      bodyParentSubshapeIDs: bodyParentSubshapeIDs,
      topologyNamespace: topologyNamespace
    )
  }

  public func validate(tolerance: ModelingTolerance) throws {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    return try validate(tolerance: tolerance, using: &execution)
  }

  public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws
  {
    try execution.consumeWork(1)
    try execution.consumeWork(shells.count)
    try execution.retainStorage(count: shells.count, stride: MemoryLayout<String>.stride)
    try execution.retainStorage(count: shells.count, stride: MemoryLayout<String>.stride)
    guard shells.isEmpty == false,
      Set(shells.map { $0.stableID }).count == shells.count,
      try bodyParentSubshapeIDs.allSatisfy({ parent in
        try execution.consumeWork(1)
        return parent.isValid
      })
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "B-rep sewing requires uniquely identified shells."
      )
    }
    for shell in shells {
      try execution.consumeWork(1)
      do {
        try shell.validate(tolerance: tolerance, using: &execution)
      } catch {
        throw contextualizedSewingFailure(
          error, tolerance: tolerance,
          context: execution.context,
          message: "B-rep sewing request contains invalid shell \(shell.stableID).")
      }
    }
    try bodyTopology.validate(shells: shells, tolerance: tolerance, using: &execution)
    var stableIDs: [String] = []
    for shell in shells {
      try sewingAppend(shell.stableID, to: &stableIDs, using: &execution)
      for patch in shell.patches {
        try sewingAppend(patch.stableID, to: &stableIDs, using: &execution)
        for loop in patch.loops {
          try sewingAppend(loop.stableID, to: &stableIDs, using: &execution)
          for edge in loop.edges {
            try sewingAppend(edge.stableID, to: &stableIDs, using: &execution)
          }
        }
      }
    }
    try execution.retainStorage(count: stableIDs.count, stride: MemoryLayout<String>.stride)
    try execution.consumeWork(stableIDs.count)
    guard Set(stableIDs).count == stableIDs.count else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "B-rep sewing stable identities must be unique across the request."
      )
    }
  }

  private static func inferredBodyTopology(
    bodyKind: BodyKind,
    shells: [BRepSewingShell]
  ) -> BRepSewingBodyTopology {
    switch bodyKind {
    case .sheet:
      return .sheet(shellStableIDs: shells.map { $0.stableID })
    case .solid:
      let outerShellStableIDs = shells.compactMap {
        $0.orientation == .forward ? $0.stableID : nil
      }
      let voidShellStableIDs = shells.compactMap {
        $0.orientation == .reversed ? $0.stableID : nil
      }
      if outerShellStableIDs.count == 1 {
        return .solid(components: [
          BRepSewingSolidComponent(
            outerShellStableID: outerShellStableIDs[0],
            voidShellStableIDs: voidShellStableIDs
          )
        ])
      }
      return .solid(
        components: outerShellStableIDs.map {
          BRepSewingSolidComponent(outerShellStableID: $0)
        })
    }
  }

}

package func contextualizedSewingFailure(
  _ error: any Error, tolerance: ModelingTolerance,
  context: OriginalQueryFailureContext, message: String
) -> any Error {
  let published = OriginalQueryFailure.published(error, context: context, tolerance: tolerance)
  let classification = KernelError.wrapping(published, phase: .topology, tolerance: tolerance)
  return OriginalQueryFailure.contextualizing(
    published,
    classification: KernelError(
      phase: classification.phase, code: classification.code, residual: classification.residual,
      tolerance: tolerance, message: "\(message) \(classification.message)"))
}

/// Appends to an invocation-local owning buffer and admits every capacity expansion.
package func sewingAppend<Element>(
  _ element: Element, to buffer: inout [Element],
  using execution: inout OriginalQueryExecution
) throws {
  try execution.consumeWork(1)
  if buffer.count == buffer.capacity {
    let doubled = buffer.capacity.multipliedReportingOverflow(by: 2)
    guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
    let capacity = max(1, doubled.partialValue)
    try execution.retainStorage(count: capacity, stride: MemoryLayout<Element>.stride)
    buffer.reserveCapacity(capacity)
  }
  buffer.append(element)
}
