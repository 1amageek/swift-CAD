import CADCore

package struct DefaultOriginalSurfaceEmbeddingPreparer: OriginalSurfaceEmbeddingPreparing {
  private let intersector: any SurfaceSurfaceIntersecting

  package init(intersector: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()) {
    self.intersector = intersector
  }

  package func prepare(
    surface: Surface3D, over domain: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> any OriginalSurfaceEmbeddingSession {
    let preparation = try execution.withPreparationScope { execution in
      try execution.checkpoint()
      let maximumSpanCount = execution.limits.maximumSpans
      let maximumSubdivisionDepth = execution.limits.maximumSubdivisionDepth
      let remainingSourceDepth = execution.limits.remainingSourceDepth
      try options.validate(tolerance: tolerance)
      guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
        throw KernelError(
          phase: .geometry, code: .invalidInput, tolerance: tolerance,
          message:
            "Original embedding requires independent nonnegative source and spatial capabilities.")
      }
      guard domain.u.lower.isFinite, domain.u.upper.isFinite,
        domain.v.lower.isFinite, domain.v.upper.isFinite,
        domain.u.width.isFinite, domain.v.width.isFinite,
        domain.u.lower < domain.u.upper, domain.v.lower < domain.v.upper
      else {
        throw KernelError(
          phase: .geometry, code: .invalidInput, tolerance: tolerance,
          message: "Original embedding requires a finite nondegenerate authored UV domain.")
      }
      var effective = options
      effective.maximumSubdivisionDepth = min(
        options.maximumSubdivisionDepth, maximumSubdivisionDepth)
      let pair = try intersector.prepareOriginalSelf(
        surface: surface, tolerance: tolerance,
        using: &execution)
      let exclusion: OriginalDraftedSelfExclusion?
      if case .procedural(.originalDrafted(let wall)) = surface,
        OriginalDraftedCoordinateProjection.supports(wall)
      {
        let limits = try OriginalDomainIdentityLimits(
          source: .init(remainingSourceDepth: remainingSourceDepth),
          maximumTransportDepth: execution.limits.maximumTransportDepth,
          maximumCharts: maximumSpanCount,
          maximumFamilies: maximumSpanCount, maximumIdentityProofs: maximumSpanCount)
        let pairs = maximumSpanCount.multipliedReportingOverflow(by: maximumSpanCount)
        exclusion = try OriginalDraftedSelfExclusion.prepare(
          wall, limits: limits,
          maximumPairs: pairs.overflow ? Int.max : pairs.partialValue, using: &execution)
      } else {
        exclusion = nil
      }
      let continuous = try pair.admitsFirstOrderContinuity(over: domain, using: &execution)
      try execution.checkpoint()
      return (pair: pair, options: effective, exclusion: exclusion, continuous: continuous)
    }
    try execution.retainStorage(
      bytes: MemoryLayout<any OriginalSurfacePairIntersecting>.stride
        + MemoryLayout<SurfaceParameterBox>.stride
        + MemoryLayout<SurfaceSurfaceIntersectionOptions>.stride
        + MemoryLayout<ModelingTolerance>.stride
        + MemoryLayout<OriginalDraftedSelfExclusion?>.stride
        + MemoryLayout<OriginalQueryBudget>.stride
        + MemoryLayout<OriginalQueryExecutionLimits>.stride
        + MemoryLayout<OriginalQueryPreparationDepth>.stride + 2
        * MemoryLayout<UnsafeRawPointer>.stride
        + MemoryLayout<Bool>.stride)
    let result = preparation.result
    return Session(
      pair: result.pair, domain: domain, options: result.options, tolerance: tolerance,
      continuousDomain: result.continuous, budget: execution.budget,
      executionLimits: execution.limits,
      exclusion: result.exclusion, depth: preparation.depth)
  }

  private final class Session: OriginalSurfaceEmbeddingSession {
    let pair: any OriginalSurfacePairIntersecting
    let domain: SurfaceParameterBox
    let options: SurfaceSurfaceIntersectionOptions
    let tolerance: ModelingTolerance
    let continuousDomain: Bool
    let budget: OriginalQueryBudget
    let executionLimits: OriginalQueryExecutionLimits
    let exclusion: OriginalDraftedSelfExclusion?
    let depth: OriginalQueryPreparationDepth

    init(
      pair: any OriginalSurfacePairIntersecting, domain: SurfaceParameterBox,
      options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
      continuousDomain: Bool, budget: OriginalQueryBudget,
      executionLimits: OriginalQueryExecutionLimits,
      exclusion: OriginalDraftedSelfExclusion?, depth: OriginalQueryPreparationDepth
    ) {
      self.pair = pair
      self.domain = domain
      self.options = options
      self.tolerance = tolerance
      self.continuousDomain = continuousDomain
      self.budget = budget
      self.executionLimits = executionLimits
      self.exclusion = exclusion
      self.depth = depth
    }

    func visitCrossContacts(
      using execution: inout OriginalQueryExecution,
      excluding: (SurfaceParameterBox, Int, inout OriginalQueryExecution) throws -> Bool,
      admit: (
        SurfaceSurfaceIntersection, SurfaceParameterBox, SurfaceParameterBox, Int,
        inout OriginalQueryExecution
      ) throws -> Void
    ) throws {
      _ = try execution.admitRetainedPreparation(
        owner: self, budget: budget, work: 1, storageBytes: 0,
        depth: depth.scalar, sourceDepth: depth.sourceDepth,
        geometricDepth: depth.geometricDepth, transportDepth: depth.transportDepth)
      try OriginalSurfaceSelfContactAtlas().visit(
        domain: domain, options: options,
        tolerance: tolerance, using: &execution,
        provesInjectivity: { try injective($0, depth: $1, using: &$2) },
        visitCrossPair: { first, second, depth, execution in
          // Complete source exclusion also covers every selected material subset.
          if exclusion != nil {
            try execution.admitGeometricDepth(depth)
            try execution.consumeWork(1)
            return
          }
          if try excluding(first, depth, &execution) || excluding(second, depth, &execution) {
            return
          }
          for contact in try pair.intersections(
            firstBox: first, secondBox: second, options: options, using: &execution)
          {
            try execution.admitGeometricDepth(depth)
            try execution.consumeWork(1)
            try admit(contact, first, second, depth, &execution)
          }
        })
      try execution.checkpoint()
    }

    func certify(using execution: inout OriginalQueryExecution) throws {
      try visitCrossContacts(
        using: &execution, excluding: { _, _, _ in false },
        admit: { contact, _, _, depth, execution in
          // FIXME(INCOMPLETE_IMPLEMENTATION): Drafted-sheet and other
          // full-domain embedding callers consume original implicit cells.
          // Critical/point/coincident contacts and unresolved shared UV
          // interfaces need original contact-sector proofs before success.
          guard case .curve(let curve) = contact, case .implicit(let graph) = curve.truth,
            !graph.cells.isEmpty
          else {
            throw unresolved(
              "Original embedding needs complete original critical/contact authority.")
          }
          for cell in graph.cells {
            try execution.admitGeometricDepth(depth)
            try execution.consumeWork(1)
            let original = cell.parameterBox
            let first = SurfaceParameterBox(u: original.firstU, v: original.firstV)
            let second = SurfaceParameterBox(u: original.secondU, v: original.secondV)
            let hull = try SurfaceParameterBox(
              u: ScalarInterval(
                lower: min(first.u.lower, second.u.lower), upper: max(first.u.upper, second.u.upper)
              ),
              v: ScalarInterval(
                lower: min(first.v.lower, second.v.lower), upper: max(first.v.upper, second.v.upper)
              ))
            guard contained(hull) else {
              throw unresolved("Original self-contact cell escapes the admitted chart domain.")
            }
            if try injective(hull, depth: depth, using: &execution) { continue }
            let separated =
              first.u.upper < second.u.lower || second.u.upper < first.u.lower
              || first.v.upper < second.v.lower || second.v.upper < first.v.lower
            if separated, strictlyInside(first), strictlyInside(second) {
              throw KernelError(
                phase: .topology, code: .topologyFailure, tolerance: tolerance,
                message: "Original surface self-intersects at distinct authored parameters.")
            }
            throw unresolved(
              "Original contact needs a shared UV interface or authored domain-boundary sector proof."
            )
          }
        })
    }

    private func injective(
      _ box: SurfaceParameterBox, depth: Int, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      try execution.admitGeometricDepth(depth)
      try execution.consumeWork(1)
      guard contained(box) else {
        throw unresolved("Embedding query escapes its original admitted chart.")
      }
      if !continuousDomain, try !pair.admitsFirstOrderContinuity(over: box, using: &execution) {
        return false
      }
      let enclosure = try pair.firstDifferentialEnclosure(over: box, using: &execution)
      return try OriginalSurfaceProjectionContraction.proves(enclosure, using: &execution)
    }

    private func contained(_ box: SurfaceParameterBox) -> Bool {
      box.u.lower >= domain.u.lower && box.u.upper <= domain.u.upper
        && box.v.lower >= domain.v.lower && box.v.upper <= domain.v.upper
    }

    private func strictlyInside(_ box: SurfaceParameterBox) -> Bool {
      box.u.lower > domain.u.lower && box.u.upper < domain.u.upper
        && box.v.lower > domain.v.lower && box.v.upper < domain.v.upper
    }

    private func unresolved(_ message: String) -> KernelError {
      KernelError(
        phase: .geometry, code: .classificationFailure, tolerance: tolerance, message: message)
    }
  }
}
