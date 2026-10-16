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

/// Certifies a rectangular rational B-spline surface-flux integral. Every
/// active clamped or non-clamped span is reconstructed from outward-rounded
/// homogeneous basis derivatives. Tensor three-point Gauss values are widened
/// by sixth-derivative remainder bounds from each complete control net.
struct CertifiedRationalBezierSurfaceFluxIntegrator {
  enum AxisAlignedProjection: Sendable, Hashable {
    case normalX
    case normalY
    case normalZ
  }

  struct Bounds: Sendable, Hashable {
    let lower: Double
    let upper: Double

    var errorRadius: Double {
      (upper - lower) * 0.5
    }
  }

  struct PreparedField {
    struct SecondOrderBounds {
      typealias Interval = CertifiedUnivariateTaylorJet.Interval

      let value: Interval
      let derivativeU: Interval
      let derivativeV: Interval
      let secondDerivativeUU: Interval
      let secondDerivativeUV: Interval
      let secondDerivativeVV: Interval
    }

    struct ParameterSpan: Sendable, Hashable {
      let lower: Double
      let upper: Double
    }

    private struct SourcePatch {
      let patch: Patch
      let uLower: Double
      let uUpper: Double
      let vLower: Double
      let vUpper: Double
    }

    private let patches: [SourcePatch]
    private let sourceSurface: BSplineSurface3D
    private let reference: Point3D
    private let tolerance: ModelingTolerance

    let uSpans: [ParameterSpan]
    let vSpans: [ParameterSpan]

    fileprivate init(
      certifiedPatches: [CertifiedHomogeneousBezierSurfacePatch],
      sourceSurface: BSplineSurface3D,
      reference: Point3D,
      includeFluxNumerator: Bool,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
      patches = try OriginalParameterQueryStorage.map(
        certifiedPatches, using: &execution,
        transform: { element, execution in
          SourcePatch(
            patch: try Patch(
              certified: element,
              reference: reference,
              includeFluxNumerator: includeFluxNumerator,
              tolerance: tolerance, using: &execution
            ),
            uLower: element.uLower,
            uUpper: element.uUpper,
            vLower: element.vLower,
            vUpper: element.vUpper
          )
        })
      self.sourceSurface = sourceSurface
      self.reference = reference
      self.tolerance = tolerance
      uSpans =
        (try Self.distinctSpans(
          OriginalParameterQueryStorage.map(
            certifiedPatches, using: &execution,
            transform: { element, execution in
              ParameterSpan(lower: element.uLower, upper: element.uUpper)
            }), using: &execution
        ))
      vSpans =
        (try Self.distinctSpans(
          OriginalParameterQueryStorage.map(
            certifiedPatches, using: &execution,
            transform: { element, execution in
              ParameterSpan(lower: element.vLower, upper: element.vUpper)
            }), using: &execution
        ))
    }

    func exactPlanarAffineFluxTraversal(for curve: CertifiedImplicitSurfaceParameterCurve) throws
      -> CertifiedPlanarAffineFluxTraversal?
    {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try exactPlanarAffineFluxTraversal(for: curve, using: &execution)
    }

    func exactPlanarAffineFluxTraversal(
      for curve: CertifiedImplicitSurfaceParameterCurve,
      using execution: inout OriginalQueryExecution
    ) throws -> CertifiedPlanarAffineFluxTraversal? {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws
            -> CertifiedPlanarAffineFluxTraversal?
          {

            try execution.consumeWork(1)
            return

              try curve.exactPlanarAffineFluxTraversal(
                on: sourceSurface,
                reference: reference,
                tolerance: tolerance, using: &execution
              )
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    func preparedPolynomialGreenPrimitive(
      uBase: Double,
      coefficientOperations: inout Int, maximumCoefficientOperations: Int,
      using execution: inout OriginalQueryExecution
    ) throws -> CertifiedPiecewisePolynomialSurfaceFluxPrimitive? {
      try execution.consumeWork(1)

      try CurrentTaskCancellationChecker().checkCancellation()
      // FIXME(INCOMPLETE_IMPLEMENTATION): Periodic native charts have no prefix owner
      // on volumetric pcurve queries. Complete only with original cycle/seam coverage.
      guard !sourceSurface.isUPeriodic, !sourceSurface.isVPeriodic else {
        throw KernelError(
          phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
          message: "Polynomial Green prefixes require nonperiodic original charts.")
      }
      guard case .closed(let lower, let upper) = sourceSurface.uDomain,
        uBase.isFinite, uBase >= lower, uBase <= upper,
        let weight = sourceSurface.weights.first?.first, weight.isFinite, weight > 0
      else {
        throw KernelError(
          phase: .topology, code: .invalidInput, tolerance: tolerance,
          message:
            "Polynomial Green preparation requires a contained base and positive original weights.")
      }
      for row in sourceSurface.weights {
        try execution.consumeWork(1)

        try CurrentTaskCancellationChecker().checkCancellation()
        try OriginalPolynomialCoefficientOperations.record(
          row.count, count: &coefficientOperations, maximum: maximumCoefficientOperations,
          using: &execution)
        for value in row where value != weight {
          try execution.consumeWork(1)
          return nil
        }
      }
      try OriginalPolynomialCoefficientOperations.record(
        patches.count, count: &coefficientOperations, maximum: maximumCoefficientOperations,
        using: &execution)
      var inputs: [CertifiedPiecewisePolynomialSurfaceFluxPrimitive.NativePanel] = []
      (try OriginalParameterQueryStorage.reserve(patches.count, in: &inputs, using: &execution))
      for source in patches {
        try execution.consumeWork(1)

        try CurrentTaskCancellationChecker().checkCancellation()
        try OriginalPolynomialCoefficientOperations.record(
          5, count: &coefficientOperations, maximum: maximumCoefficientOperations, using: &execution
        )
        (try OriginalParameterQueryStorage.append(
          .init(
            uSpan: .init(lower: source.uLower, upper: source.uUpper),
            vSpan: .init(lower: source.vLower, upper: source.vUpper),
            fluxCoefficients: source.patch.polynomialFluxCoefficients(
              weight: weight, coefficientOperations: &coefficientOperations,
              maximumCoefficientOperations: maximumCoefficientOperations, tolerance: tolerance,
              using: &execution)), to: &inputs, using: &execution))
      }
      return try CertifiedPiecewisePolynomialSurfaceFluxPrimitive(
        source: sourceSurface, reference: reference, tolerance: tolerance, uBase: uBase,
        uSpans: uSpans, vSpans: vSpans, panels: inputs, field: self,
        coefficientOperations: &coefficientOperations,
        maximumCoefficientOperations: maximumCoefficientOperations, using: &execution)
    }

    func containingVSpan(_ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval) throws
      -> ParameterSpan?
    {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try containingVSpan(range, using: &execution)
    }

    func containingVSpan(
      _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
      using execution: inout OriginalQueryExecution
    ) throws -> ParameterSpan? {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws -> ParameterSpan? {

            try execution.consumeWork(1)
            return

              (try containingSpan(range, candidates: vSpans, using: &execution))
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    func strictlyContainingVSpan(_ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval) throws
      -> ParameterSpan?
    {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try strictlyContainingVSpan(range, using: &execution)
    }

    func strictlyContainingVSpan(
      _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
      using execution: inout OriginalQueryExecution
    ) throws -> ParameterSpan? {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws -> ParameterSpan? {

            try execution.consumeWork(1)
            return

              (try OriginalParameterQueryStorage.first(
                vSpans, using: &execution,
                predicate: { element, execution in
                  range.lower >= element.lower && range.upper <= element.upper
                }))
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    func containingUSpan(_ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval) throws
      -> ParameterSpan?
    {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try containingUSpan(range, using: &execution)
    }

    func containingUSpan(
      _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
      using execution: inout OriginalQueryExecution
    ) throws -> ParameterSpan? {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws -> ParameterSpan? {

            try execution.consumeWork(1)
            return

              (try containingSpan(range, candidates: uSpans, using: &execution))
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    func bounds(
      uLower: Double,
      uUpper: Double,
      vLower: Double,
      vUpper: Double
    ) throws -> Bounds {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try bounds(
        uLower: uLower, uUpper: uUpper, vLower: vLower, vUpper: vUpper, using: &execution)
    }

    func bounds(
      uLower: Double,
      uUpper: Double,
      vLower: Double,
      vUpper: Double, using execution: inout OriginalQueryExecution
    ) throws -> Bounds {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws -> Bounds {

            try execution.consumeWork(1)

            guard uLower.isFinite,
              uUpper.isFinite,
              vLower.isFinite,
              vUpper.isFinite,
              uLower <= uUpper,
              vLower <= vUpper
            else {
              throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message:
                  "Certified rational surface flux range requires finite ordered parameter bounds."
              )
            }
            var ranges: [Interval] = []
            for source in patches {
              try execution.consumeWork(1)

              let overlapULower = max(uLower, source.uLower)
              let overlapUUpper = min(uUpper, source.uUpper)
              let overlapVLower = max(vLower, source.vLower)
              let overlapVUpper = min(vUpper, source.vUpper)
              guard overlapULower <= overlapUUpper,
                overlapVLower <= overlapVUpper
              else {
                continue
              }
              let uSpan =
                Interval.exact(source.uUpper)
                - Interval.exact(source.uLower)
              let vSpan =
                Interval.exact(source.vUpper)
                - Interval.exact(source.vLower)
              guard uSpan.lower > 0.0,
                vSpan.lower > 0.0
              else {
                throw KernelError(
                  phase: .topology,
                  code: .topologyFailure,
                  tolerance: tolerance,
                  message:
                    "Certified rational surface flux field contains a degenerate Bezier patch."
                )
              }
              let localU =
                Interval(
                  lower: overlapULower,
                  upper: overlapUUpper
                ) - .exact(source.uLower)
              let localV =
                Interval(
                  lower: overlapVLower,
                  upper: overlapVUpper
                ) - .exact(source.vLower)
              let flux =
                try source.patch.flux(
                  u: localU / uSpan,
                  v: localV / vSpan,
                  tolerance: tolerance, using: &execution
                ) / (uSpan * vSpan)
              (try OriginalParameterQueryStorage.append(flux, to: &ranges, using: &execution))
            }
            guard !ranges.isEmpty else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message:
                  "Certified rational surface flux range does not overlap an extracted Bezier patch."
              )
            }
            let result = (try Interval.hull(ranges, using: &execution))
            return Bounds(lower: result.lower, upper: result.upper)
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    func bounds(
      u: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
      v: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
      uSpan: ParameterSpan,
      vSpan: ParameterSpan
    ) throws -> Bounds {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try bounds(u: u, v: v, uSpan: uSpan, vSpan: vSpan, using: &execution)
    }

    func bounds(
      u: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
      v: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
      uSpan: ParameterSpan,
      vSpan: ParameterSpan, using execution: inout OriginalQueryExecution
    ) throws -> Bounds {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws -> Bounds {

            try execution.consumeWork(1)

            guard
              let source =
                (try OriginalParameterQueryStorage.first(
                  patches, using: &execution,
                  predicate: { element, execution in
                    element.uLower == uSpan.lower
                      && element.uUpper == uSpan.upper
                      && element.vLower == vSpan.lower
                      && element.vUpper == vSpan.upper
                  }))
            else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message:
                  "Certified rational surface flux could not bind a point range to its Bezier patch."
              )
            }
            let clippedU = Interval(
              lower: max(u.lower, source.uLower),
              upper: min(u.upper, source.uUpper)
            )
            let clippedV = Interval(
              lower: max(v.lower, source.vLower),
              upper: min(v.upper, source.vUpper)
            )
            guard clippedU.lower <= clippedU.upper,
              clippedV.lower <= clippedV.upper
            else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message:
                  "Certified rational surface flux point range does not overlap its Bezier patch."
              )
            }
            let uWidth = Interval.exact(source.uUpper) - .exact(source.uLower)
            let vWidth = Interval.exact(source.vUpper) - .exact(source.vLower)
            guard uWidth.lower > 0.0, vWidth.lower > 0.0 else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Certified rational surface flux field contains a degenerate Bezier patch."
              )
            }
            let normalizedU = (clippedU - .exact(source.uLower)) / uWidth
            let normalizedV = (clippedV - .exact(source.vLower)) / vWidth
            let flux =
              try source.patch.flux(
                u: normalizedU,
                v: normalizedV,
                tolerance: tolerance, using: &execution
              ) / (uWidth * vWidth)
            return Bounds(lower: flux.lower, upper: flux.upper)
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    func directionalFluxJet(
      u: CertifiedUnivariateTaylorJet,
      v: CertifiedUnivariateTaylorJet,
      uSpan: ParameterSpan,
      vSpan: ParameterSpan
    ) throws -> CertifiedUnivariateTaylorJet {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try directionalFluxJet(u: u, v: v, uSpan: uSpan, vSpan: vSpan, using: &execution)
    }

    func directionalFluxJet(
      u: CertifiedUnivariateTaylorJet,
      v: CertifiedUnivariateTaylorJet,
      uSpan: ParameterSpan,
      vSpan: ParameterSpan, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedUnivariateTaylorJet {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws
            -> CertifiedUnivariateTaylorJet
          {

            try execution.consumeWork(1)

            guard
              let source =
                (try OriginalParameterQueryStorage.first(
                  patches, using: &execution,
                  predicate: { element, execution in
                    element.uLower == uSpan.lower
                      && element.uUpper == uSpan.upper
                      && element.vLower == vSpan.lower
                      && element.vUpper == vSpan.upper
                  }))
            else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message:
                  "Certified rational surface flux could not bind a directional jet to its Bezier patch."
              )
            }
            let clippedURange = CertifiedUnivariateTaylorJet.Interval(
              lower: max(u.value.lower, uSpan.lower),
              upper: min(u.value.upper, uSpan.upper)
            )
            let clippedVRange = CertifiedUnivariateTaylorJet.Interval(
              lower: max(v.value.lower, vSpan.lower),
              upper: min(v.value.upper, vSpan.upper)
            )
            guard clippedURange.lower <= clippedURange.upper,
              clippedVRange.lower <= clippedVRange.upper
            else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message:
                  "Certified rational surface flux directional jet does not overlap its Bezier patch."
              )
            }
            try execution.retainStorage(
              count: u.coefficients.count,
              stride: MemoryLayout<CertifiedUnivariateTaylorJet.Interval>.stride)
            try execution.retainStorage(
              count: v.coefficients.count,
              stride: MemoryLayout<CertifiedUnivariateTaylorJet.Interval>.stride)
            var patchU = u
            var patchV = v
            patchU.coefficients[0] = clippedURange
            patchV.coefficients[0] = clippedVRange
            let uWidth = Interval.exact(source.uUpper) - .exact(source.uLower)
            let vWidth = Interval.exact(source.vUpper) - .exact(source.vLower)
            let normalizedU = try patchU.subtracting(
              .constant(source.uLower, using: &execution), using: &execution
            ).divided(
              by: .constant(
                CertifiedUnivariateTaylorJet.Interval(
                  lower: uWidth.lower,
                  upper: uWidth.upper
                ), using: &execution),
              tolerance: tolerance, using: &execution
            )
            let normalizedV = try patchV.subtracting(
              .constant(source.vLower, using: &execution), using: &execution
            ).divided(
              by: .constant(
                CertifiedUnivariateTaylorJet.Interval(
                  lower: vWidth.lower,
                  upper: vWidth.upper
                ), using: &execution),
              tolerance: tolerance, using: &execution
            )
            // A directional jet is already evaluated over its certified value
            // box. Reparameterizing a trimmed patch scales its derivatives by
            // inverse powers of a small restriction width; although those
            // factors cancel algebraically, interval arithmetic loses the
            // correlation and can inflate higher derivatives by many orders
            // of magnitude. Positive Bernstein weights certify the original
            // patch denominator directly, so evaluate the original patch and
            // apply only the source-domain scale.
            let localFlux = try source.patch.directionalFluxJet(
              u: normalizedU,
              v: normalizedV,
              tolerance: tolerance, using: &execution
            )
            return try localFlux.divided(
              by: .constant(
                CertifiedUnivariateTaylorJet.Interval(
                  lower: (uWidth * vWidth).lower,
                  upper: (uWidth * vWidth).upper
                ), using: &execution),
              tolerance: tolerance, using: &execution
            )
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    func secondOrderBounds(
      u: CertifiedUnivariateTaylorJet.Interval,
      v: CertifiedUnivariateTaylorJet.Interval,
      uSpan: ParameterSpan,
      vSpan: ParameterSpan
    ) throws -> SecondOrderBounds {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try secondOrderBounds(u: u, v: v, uSpan: uSpan, vSpan: vSpan, using: &execution)
    }

    func secondOrderBounds(
      u: CertifiedUnivariateTaylorJet.Interval,
      v: CertifiedUnivariateTaylorJet.Interval,
      uSpan: ParameterSpan,
      vSpan: ParameterSpan, using execution: inout OriginalQueryExecution
    ) throws -> SecondOrderBounds {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws -> SecondOrderBounds {

            try execution.consumeWork(1)

            typealias TaylorInterval = CertifiedUnivariateTaylorJet.Interval
            func evaluate(
              u localU: TaylorInterval,
              v localV: TaylorInterval, using execution: inout OriginalQueryExecution
            ) throws -> SecondOrderBounds {
              try execution.consumeWork(1)

              let one = TaylorInterval.exact(1.0)
              let uVariable =
                (try CertifiedUnivariateTaylorJet.series(
                  OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
                    [localU, one]
                  }, using: &execution))
              let vVariable =
                (try CertifiedUnivariateTaylorJet.series(
                  OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
                    [localV, one]
                  }, using: &execution))
              let constantU = (try CertifiedUnivariateTaylorJet.constant(localU, using: &execution))
              let constantV = (try CertifiedUnivariateTaylorJet.constant(localV, using: &execution))
              let alongU = try directionalFluxJet(
                u: uVariable,
                v: constantV,
                uSpan: uSpan,
                vSpan: vSpan, using: &execution
              )
              let alongV = try directionalFluxJet(
                u: constantU,
                v: vVariable,
                uSpan: uSpan,
                vSpan: vSpan, using: &execution
              )
              let alongDiagonal = try directionalFluxJet(
                u: uVariable,
                v: vVariable,
                uSpan: uSpan,
                vSpan: vSpan, using: &execution
              )
              let two = TaylorInterval.exact(2.0)
              return SecondOrderBounds(
                value: alongDiagonal.coefficients[0],
                derivativeU: alongU.coefficients[1],
                derivativeV: alongV.coefficients[1],
                secondDerivativeUU: alongU.coefficients[2] * two,
                secondDerivativeUV: alongDiagonal.coefficients[2]
                  - alongU.coefficients[2]
                  - alongV.coefficients[2],
                secondDerivativeVV: alongV.coefficients[2] * two
              )
            }
            let subdivisionCount = 4
            let uBoundaries =
              (try OriginalParameterQueryStorage.map(
                (0...subdivisionCount), using: &execution,
                transform: { index, execution in
                  u.lower + (u.upper - u.lower)
                    * Double(index) / Double(subdivisionCount)
                }))
            let vBoundaries =
              (try OriginalParameterQueryStorage.map(
                (0...subdivisionCount), using: &execution,
                transform: { index, execution in
                  v.lower + (v.upper - v.lower)
                    * Double(index) / Double(subdivisionCount)
                }))
            var localBounds: [SecondOrderBounds] = []
            (try OriginalParameterQueryStorage.reserve(
              subdivisionCount * subdivisionCount, in: &localBounds, using: &execution))
            for vIndex in 0..<subdivisionCount {
              try execution.consumeWork(1)

              for uIndex in 0..<subdivisionCount {
                try execution.consumeWork(1)

                (try OriginalParameterQueryStorage.append(
                  evaluate(
                    u: TaylorInterval(
                      lower: uBoundaries[uIndex],
                      upper: uBoundaries[uIndex + 1]
                    ),
                    v: TaylorInterval(
                      lower: vBoundaries[vIndex],
                      upper: vBoundaries[vIndex + 1]
                    ), using: &execution
                  ), to: &localBounds, using: &execution))
              }
            }
            return SecondOrderBounds(
              value: TaylorInterval(
                lower: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.value.lower }), using: &execution,
                  projection: { element, _ in element }))?.lower ?? -.infinity,
                upper: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.value.upper }), using: &execution,
                  projection: { element, _ in element }))?.upper ?? .infinity
              ),
              derivativeU: TaylorInterval(
                lower: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.derivativeU.lower }),
                  using: &execution, projection: { element, _ in element }))?.lower ?? -.infinity,
                upper: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.derivativeU.upper }),
                  using: &execution, projection: { element, _ in element }))?.upper ?? .infinity
              ),
              derivativeV: TaylorInterval(
                lower: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.derivativeV.lower }),
                  using: &execution, projection: { element, _ in element }))?.lower ?? -.infinity,
                upper: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.derivativeV.upper }),
                  using: &execution, projection: { element, _ in element }))?.upper ?? .infinity
              ),
              secondDerivativeUU: TaylorInterval(
                lower: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.secondDerivativeUU.lower }),
                  using: &execution, projection: { element, _ in element }))?.lower
                  ?? -.infinity,
                upper: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.secondDerivativeUU.upper }),
                  using: &execution, projection: { element, _ in element }))?.upper
                  ?? .infinity
              ),
              secondDerivativeUV: TaylorInterval(
                lower: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.secondDerivativeUV.lower }),
                  using: &execution, projection: { element, _ in element }))?.lower
                  ?? -.infinity,
                upper: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.secondDerivativeUV.upper }),
                  using: &execution, projection: { element, _ in element }))?.upper
                  ?? .infinity
              ),
              secondDerivativeVV: TaylorInterval(
                lower: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.secondDerivativeVV.lower }),
                  using: &execution, projection: { element, _ in element }))?.lower
                  ?? -.infinity,
                upper: (try OriginalParameterQueryStorage.extrema(
                  OriginalParameterQueryStorage.map(
                    localBounds, using: &execution,
                    transform: { element, execution in element.secondDerivativeVV.upper }),
                  using: &execution, projection: { element, _ in element }))?.upper
                  ?? .infinity
              )
            )
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    func projectedBoundaryAreaJet(
      u: CertifiedUnivariateTaylorJet,
      v: CertifiedUnivariateTaylorJet,
      projection: AxisAlignedProjection,
      uSpan: ParameterSpan,
      vSpan: ParameterSpan
    ) throws -> CertifiedUnivariateTaylorJet {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try projectedBoundaryAreaJet(
        u: u, v: v, projection: projection, uSpan: uSpan, vSpan: vSpan, using: &execution)
    }

    func projectedBoundaryAreaJet(
      u: CertifiedUnivariateTaylorJet,
      v: CertifiedUnivariateTaylorJet,
      projection: AxisAlignedProjection,
      uSpan: ParameterSpan,
      vSpan: ParameterSpan, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedUnivariateTaylorJet {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws
            -> CertifiedUnivariateTaylorJet
          {

            try execution.consumeWork(1)

            guard
              let source =
                (try OriginalParameterQueryStorage.first(
                  patches, using: &execution,
                  predicate: { element, execution in
                    element.uLower == uSpan.lower
                      && element.uUpper == uSpan.upper
                      && element.vLower == vSpan.lower
                      && element.vUpper == vSpan.upper
                  }))
            else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message:
                  "Certified rational planar area could not bind a curve jet to its Bezier patch."
              )
            }
            let clippedURange = CertifiedUnivariateTaylorJet.Interval(
              lower: max(u.value.lower, uSpan.lower),
              upper: min(u.value.upper, uSpan.upper)
            )
            let clippedVRange = CertifiedUnivariateTaylorJet.Interval(
              lower: max(v.value.lower, vSpan.lower),
              upper: min(v.value.upper, vSpan.upper)
            )
            guard clippedURange.lower <= clippedURange.upper,
              clippedVRange.lower <= clippedVRange.upper
            else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message:
                  "Certified rational planar area curve jet does not overlap its Bezier patch."
              )
            }
            try execution.retainStorage(
              count: u.coefficients.count,
              stride: MemoryLayout<CertifiedUnivariateTaylorJet.Interval>.stride)
            try execution.retainStorage(
              count: v.coefficients.count,
              stride: MemoryLayout<CertifiedUnivariateTaylorJet.Interval>.stride)
            var patchU = u
            var patchV = v
            patchU.coefficients[0] = clippedURange
            patchV.coefficients[0] = clippedVRange
            let uWidth = Interval.exact(source.uUpper) - .exact(source.uLower)
            let vWidth = Interval.exact(source.vUpper) - .exact(source.vLower)
            let normalizedU = try patchU.subtracting(
              .constant(source.uLower, using: &execution), using: &execution
            ).divided(
              by: .constant(
                CertifiedUnivariateTaylorJet.Interval(
                  lower: uWidth.lower,
                  upper: uWidth.upper
                ), using: &execution),
              tolerance: tolerance, using: &execution
            )
            let normalizedV = try patchV.subtracting(
              .constant(source.vLower, using: &execution), using: &execution
            ).divided(
              by: .constant(
                CertifiedUnivariateTaylorJet.Interval(
                  lower: vWidth.lower,
                  upper: vWidth.upper
                ), using: &execution),
              tolerance: tolerance, using: &execution
            )
            let uRestriction =
              (try Self.positiveRestriction(
                containing: normalizedU.value, using: &execution
              ))
            let vRestriction =
              (try Self.positiveRestriction(
                containing: normalizedV.value, using: &execution
              ))
            let restrictedPatch = try source.patch.trimmed(
              uLower: uRestriction.lower,
              uUpper: uRestriction.upper,
              vLower: vRestriction.lower,
              vUpper: vRestriction.upper,
              sourceUDomain: .closed(0.0, 1.0),
              sourceVDomain: .closed(0.0, 1.0),
              includeFluxNumerator: false,
              tolerance: tolerance, using: &execution
            )
            let restrictedU = try normalizedU.subtracting(
              .constant(uRestriction.lower, using: &execution), using: &execution
            ).divided(
              by: .constant(uRestriction.upper - uRestriction.lower, using: &execution),
              tolerance: tolerance, using: &execution
            )
            let restrictedV = try normalizedV.subtracting(
              .constant(vRestriction.lower, using: &execution), using: &execution
            ).divided(
              by: .constant(vRestriction.upper - vRestriction.lower, using: &execution),
              tolerance: tolerance, using: &execution
            )
            return try restrictedPatch.projectedBoundaryAreaJet(
              u: restrictedU,
              v: restrictedV,
              projection: projection,
              tolerance: tolerance, using: &execution
            )
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    func projectedBoundaryAreaRange(
      u: CertifiedUnivariateTaylorJet,
      v: CertifiedUnivariateTaylorJet,
      projection: AxisAlignedProjection
    ) throws -> CertifiedUnivariateTaylorJet.Interval {
      var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(),
        limits: try OriginalQueryExecutionLimits(
          maximumValueDepth: 32, maximumCoefficientDepth: 32,
          maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
          maximumSubdivisionDepth: Int.max),
        context: .init(operation: .boundary, entry: .ordinary, stage: .source))
      return try projectedBoundaryAreaRange(u: u, v: v, projection: projection, using: &execution)
    }

    func projectedBoundaryAreaRange(
      u: CertifiedUnivariateTaylorJet,
      v: CertifiedUnivariateTaylorJet,
      projection: AxisAlignedProjection, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedUnivariateTaylorJet.Interval {
      do {
        return try execution.withProofScope { execution in
          func produce(using execution: inout OriginalQueryExecution) throws
            -> CertifiedUnivariateTaylorJet.Interval
          {

            try execution.consumeWork(1)

            let candidateUSpans =
              (try overlappingSpans(u.value, candidates: uSpans, using: &execution))
            let candidateVSpans =
              (try overlappingSpans(v.value, candidates: vSpans, using: &execution))
            guard !candidateUSpans.isEmpty, !candidateVSpans.isEmpty else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message:
                  "Certified rational planar area does not overlap an extracted Bezier patch."
              )
            }
            var ranges: [CertifiedUnivariateTaylorJet.Interval] = []
            (try OriginalParameterQueryStorage.reserve(
              candidateUSpans.count * candidateVSpans.count, in: &ranges, using: &execution))
            for uSpan in candidateUSpans {
              try execution.consumeWork(1)

              for vSpan in candidateVSpans {
                try execution.consumeWork(1)

                (try OriginalParameterQueryStorage.append(
                  projectedBoundaryAreaJet(
                    u: u,
                    v: v,
                    projection: projection,
                    uSpan: uSpan,
                    vSpan: vSpan, using: &execution
                  ).coefficients[0], to: &ranges, using: &execution))
              }
            }
            return CertifiedUnivariateTaylorJet.Interval(
              lower: ((try OriginalParameterQueryStorage.extrema(
                OriginalParameterQueryStorage.map(
                  ranges, using: &execution, transform: { element, execution in element.lower }),
                using: &execution, projection: { element, _ in element }))?.lower ?? -.infinity)
                .nextDown,
              upper: ((try OriginalParameterQueryStorage.extrema(
                OriginalParameterQueryStorage.map(
                  ranges, using: &execution, transform: { element, execution in element.upper }),
                using: &execution, projection: { element, _ in element }))?.upper ?? .infinity)
                .nextUp
            )
          }
          execution.context = execution.context.at(stage: .refinement)
          let result = try produce(using: &execution)
          execution.context = execution.context.at(stage: .publication)
          return result

        }
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }
    }

    private static func positiveRestriction(
      containing range: CertifiedUnivariateTaylorJet.Interval,
      using execution: inout OriginalQueryExecution
    ) throws -> (lower: Double, upper: Double) {
      try execution.consumeWork(1)

      var lower = max(0.0, range.lower)
      var upper = min(1.0, range.upper)
      let minimumWidth = 1.0 / 16.0
      if upper - lower >= minimumWidth {
        return (lower, upper)
      }
      let center = min(1.0, max(0.0, (lower + upper) * 0.5))
      lower = max(0.0, center - minimumWidth * 0.5)
      upper = min(1.0, lower + minimumWidth)
      lower = max(0.0, upper - minimumWidth)
      return (lower, upper)
    }

    private func containingSpan(
      _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
      candidates: [ParameterSpan], using execution: inout OriginalQueryExecution
    ) throws -> ParameterSpan? {
      try execution.consumeWork(1)

      if let exact =
        (try OriginalParameterQueryStorage.first(
          candidates, using: &execution,
          predicate: { element, execution in
            range.lower >= element.lower && range.upper <= element.upper
          }))
      {
        return exact
      }
      return
        (try OriginalParameterQueryStorage.first(
          candidates, using: &execution,
          predicate: { candidate, execution in
            let scale = max(1.0, abs(candidate.lower), abs(candidate.upper))
            let slack = Double.ulpOfOne * scale * 512.0
            return range.lower >= candidate.lower - slack
              && range.upper <= candidate.upper + slack
          }))
    }

    private func overlappingSpans(
      _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
      candidates: [ParameterSpan], using execution: inout OriginalQueryExecution
    ) throws -> [ParameterSpan] {
      try execution.consumeWork(1)
      return

        (try OriginalParameterQueryStorage.filter(
          candidates, using: &execution,
          predicate: { candidate, execution in
            let scale = max(1.0, abs(candidate.lower), abs(candidate.upper))
            let slack = Double.ulpOfOne * scale * 512.0
            return range.upper >= candidate.lower - slack
              && range.lower <= candidate.upper + slack
          }))
    }

    private static func distinctSpans(
      _ spans: [ParameterSpan],
      using execution: inout OriginalQueryExecution
    ) throws -> [ParameterSpan] {
      let ordered = try OriginalParameterQueryStorage.ordered(
        spans, using: &execution,
        less: {
          $0.lower == $1.lower ? $0.upper < $1.upper : $0.lower < $1.lower
        })
      var result: [ParameterSpan] = []
      for span in ordered {
        try execution.consumeWork(1)
        if result.last != span {
          try OriginalParameterQueryStorage.append(span, to: &result, using: &execution)
        }
      }
      return result
    }

  }

  private let maximumSubdivisionDepth: Int
  private let maximumCellCount: Int
  private let maximumExtractionControlOperations: Int

  init(
    maximumSubdivisionDepth: Int = 10,
    maximumCellCount: Int = 1_000_000,
    maximumExtractionControlOperations: Int = 4_000_000
  ) {
    self.maximumSubdivisionDepth = maximumSubdivisionDepth
    self.maximumCellCount = maximumCellCount
    self.maximumExtractionControlOperations = maximumExtractionControlOperations
  }

  func preparedField(
    surface: BSplineSurface3D,
    reference: Point3D,
    includeFluxNumerator: Bool = true,
    tolerance: ModelingTolerance
  ) throws -> PreparedField? {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumCellCount, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumSubdivisionDepth),
      context: .init(operation: .boundary, entry: .ordinary, stage: .source))
    return try preparedField(
      surface: surface, reference: reference, includeFluxNumerator: includeFluxNumerator,
      tolerance: tolerance, using: &execution)
  }

  func preparedField(
    surface: BSplineSurface3D,
    reference: Point3D,
    includeFluxNumerator: Bool = true,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> PreparedField? {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> PreparedField? {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          guard
            let extracted = try CertifiedBSplineSurfaceBezierExtractor(
              maximumControlOperations: maximumExtractionControlOperations
            ).patches(surface: surface, tolerance: tolerance, using: &execution)
          else {
            return nil
          }
          guard !extracted.isEmpty else {
            throw KernelError(
              phase: .topology,
              code: .topologyFailure,
              tolerance: tolerance,
              message: "Certified rational surface flux field extracted no active Bezier patch."
            )
          }
          return try PreparedField(
            certifiedPatches: extracted,
            sourceSurface: surface,
            reference: reference,
            includeFluxNumerator: includeFluxNumerator,
            tolerance: tolerance, using: &execution
          )
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  func integrate(
    surface: BSplineSurface3D,
    uLower: Double,
    uUpper: Double,
    vLower: Double,
    vUpper: Double,
    reference: Point3D,
    requestedError: Double,
    tolerance: ModelingTolerance
  ) throws -> Bounds? {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumCellCount, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumSubdivisionDepth),
      context: .init(operation: .boundary, entry: .ordinary, stage: .source))
    return try integrate(
      surface: surface, uLower: uLower, uUpper: uUpper, vLower: vLower, vUpper: vUpper,
      reference: reference, requestedError: requestedError, tolerance: tolerance, using: &execution)
  }

  func integrate(
    surface: BSplineSurface3D,
    uLower: Double,
    uUpper: Double,
    vLower: Double,
    vUpper: Double,
    reference: Point3D,
    requestedError: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bounds? {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Bounds? {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          guard requestedError.isFinite, requestedError > 0.0 else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: requestedError,
              tolerance: tolerance,
              message: "Certified rational surface flux requires a positive finite error bound."
            )
          }
          guard case .closed(let sourceULower, let sourceUUpper) = surface.uDomain,
            case .closed(let sourceVLower, let sourceVUpper) = surface.vDomain,
            uLower.isFinite,
            uUpper.isFinite,
            vLower.isFinite,
            vUpper.isFinite,
            uLower >= sourceULower,
            uUpper <= sourceUUpper,
            vLower >= sourceVLower,
            vUpper <= sourceVUpper,
            uUpper > uLower,
            vUpper > vLower
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              tolerance: tolerance,
              message:
                "Certified rational surface flux requires a positive trim inside the source domain."
            )
          }
          guard
            let extracted = try CertifiedBSplineSurfaceBezierExtractor(
              maximumControlOperations: maximumExtractionControlOperations
            ).patches(surface: surface, tolerance: tolerance, using: &execution)
          else {
            return nil
          }
          let activePatches =
            (try OriginalParameterQueryStorage.compactMap(
              extracted, using: &execution,
              transform: { source, execution -> ActivePatch? in
                let activeULower = max(uLower, source.uLower)
                let activeUUpper = min(uUpper, source.uUpper)
                let activeVLower = max(vLower, source.vLower)
                let activeVUpper = min(vUpper, source.vUpper)
                guard activeUUpper > activeULower,
                  activeVUpper > activeVLower
                else {
                  return nil
                }
                return ActivePatch(
                  source: source,
                  uLower: activeULower,
                  uUpper: activeUUpper,
                  vLower: activeVLower,
                  vUpper: activeVUpper
                )
              }))
          guard !activePatches.isEmpty else {
            throw KernelError(
              phase: .topology,
              code: .topologyFailure,
              tolerance: tolerance,
              message: "Certified rational surface flux trim did not intersect a Bezier span."
            )
          }
          var budget = CellCount(limit: maximumCellCount)
          let perPatchError = requestedError * 0.99 / Double(activePatches.count)
          var total = Interval.exact(0.0)
          for active in activePatches {
            try execution.consumeWork(1)

            let patch = try Patch(
              certified: active.source,
              reference: reference,
              tolerance: tolerance, using: &execution
            ).trimmed(
              uLower: active.uLower,
              uUpper: active.uUpper,
              vLower: active.vLower,
              vUpper: active.vUpper,
              sourceUDomain: .closed(active.source.uLower, active.source.uUpper),
              sourceVDomain: .closed(active.source.vLower, active.source.vUpper),
              tolerance: tolerance, using: &execution
            )
            total =
              total
              + (try certifiedIntegral(
                patch: patch,
                reference: reference,
                requestedError: perPatchError,
                depth: 0,
                budget: &budget,
                tolerance: tolerance, using: &execution
              ))
          }
          return Bounds(lower: total.lower, upper: total.upper)
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func certifiedIntegral(
    patch: Patch,
    reference: Point3D,
    requestedError: Double,
    depth: Int,
    budget: inout CellCount,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    try execution.visitGeometricCell(depth: depth)
    try budget.consume(tolerance: tolerance, using: &execution)
    let enclosure = try cellEnclosure(
      patch: patch,
      reference: reference,
      tolerance: tolerance, using: &execution
    )
    if enclosure.errorRadius <= requestedError {
      return enclosure
    }
    guard depth < min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
    else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: enclosure.errorRadius,
        tolerance: tolerance,
        message: "Certified rational surface flux exhausted its subdivision depth."
      )
    }
    let children = try patch.subdivided(tolerance: tolerance, using: &execution)
    var result = Interval.exact(0.0)
    for child in children {
      try execution.consumeWork(1)

      let childIntegral = try certifiedIntegral(
        patch: child,
        reference: reference,
        requestedError: requestedError * 0.25,
        depth: depth + 1,
        budget: &budget,
        tolerance: tolerance, using: &execution
      )
      result = result + childIntegral
    }
    return result
  }

  private func cellEnclosure(
    patch: Patch,
    reference: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let nodes = try Self.gaussNodes(tolerance: tolerance, using: &execution)
    var quadrature = Interval.exact(0.0)
    for u in nodes {
      try execution.consumeWork(1)

      for v in nodes {
        try execution.consumeWork(1)

        let value = try patch.flux(
          u: u.value,
          v: v.value,
          tolerance: tolerance, using: &execution
        )
        quadrature = quadrature + value * u.weight * v.weight
      }
    }
    let sixthU = try patch.sixthFluxDerivativeBound(
      primary: .u,
      reference: reference,
      tolerance: tolerance, using: &execution
    )
    let sixthV = try patch.sixthFluxDerivativeBound(
      primary: .v,
      reference: reference,
      tolerance: tolerance, using: &execution
    )
    let remainder = ((sixthU + sixthV) / Interval.exact(2_016_000.0))
      .maximumAbsolute
      .nextUp
    guard remainder.isFinite else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Certified rational surface flux remainder exceeded finite arithmetic."
      )
    }
    return Interval(
      lower: (quadrature.lower - remainder).nextDown,
      upper: (quadrature.upper + remainder).nextUp
    )
  }

  private static func gaussNodes(
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [(value: Interval, weight: Interval)] {
    try execution.consumeWork(1)

    let displacement = try (Interval.exact(3.0) / Interval.exact(5.0)).squareRoot(
      tolerance: tolerance)
    let half = Interval.exact(0.5)
    return
      (try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
        [
          (
            value: half * (Interval.exact(1.0) - displacement),
            weight: Interval.exact(5.0) / Interval.exact(18.0)
          ),
          (
            value: half,
            weight: Interval.exact(4.0) / Interval.exact(9.0)
          ),
          (
            value: half * (Interval.exact(1.0) + displacement),
            weight: Interval.exact(5.0) / Interval.exact(18.0)
          ),
        ]
      })
  }

  private enum Direction: Equatable {
    case u
    case v
  }

  private struct ActivePatch {
    let source: CertifiedHomogeneousBezierSurfacePatch
    let uLower: Double
    let uUpper: Double
    let vLower: Double
    let vUpper: Double
  }

  private struct Patch {
    let controls: [[HomogeneousPoint]]
    let reference: Point3D
    private let fluxNumerator: ScalarPolynomial2D?

    func hasExactConstantWeight(using execution: inout OriginalQueryExecution) throws -> Bool {
      guard let first = controls.first?.first?.weight,
        first.lower == first.upper
      else {
        return false
      }
      return try OriginalParameterQueryStorage.allSatisfy(
        controls, using: &execution,
        predicate: { row, execution in
          guard !row.isEmpty else { return false }
          return try OriginalParameterQueryStorage.allSatisfy(
            row, using: &execution,
            predicate: { point, _ in
              point.weight.lower == first.lower && point.weight.upper == first.upper
            })
        })
    }

    func polynomialFluxCoefficients(
      weight: Double, coefficientOperations: inout Int, maximumCoefficientOperations: Int,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [[CertifiedUnivariateTaylorJet.Interval]] {
      try execution.consumeWork(1)

      // Charge both row metadata traversals and the exact-weight control scan
      // before inspecting any prepared homogeneous coefficient.
      let rowWork = controls.count.multipliedReportingOverflow(by: 2)
      guard !rowWork.overflow else {
        throw KernelError(
          phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Polynomial Green control-admission row work overflowed.")
      }
      try OriginalPolynomialCoefficientOperations.record(
        rowWork.partialValue, count: &coefficientOperations, maximum: maximumCoefficientOperations,
        using: &execution)
      var controlWork = 0
      for row in controls {
        try execution.consumeWork(1)

        let next = controlWork.addingReportingOverflow(row.count)
        guard !next.overflow else {
          throw KernelError(
            phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Polynomial Green control-admission work overflowed.")
        }
        controlWork = next.partialValue
      }
      try OriginalPolynomialCoefficientOperations.record(
        controlWork, count: &coefficientOperations, maximum: maximumCoefficientOperations,
        using: &execution)
      guard try hasExactConstantWeight(using: &execution),
        controls.first?.first?.weight.lower == weight,
        let fluxNumerator
      else {
        throw KernelError(
          phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
          message:
            "Polynomial Green preparation requires retained original constant-weight determinant coefficients."
        )
      }
      try OriginalPolynomialCoefficientOperations.record(
        3, count: &coefficientOperations, maximum: maximumCoefficientOperations, using: &execution)
      let w = Interval.exact(weight)
      let denominator = Interval.exact(3) * w * w * w
      guard denominator.lower > 0, denominator.upper.isFinite else {
        throw KernelError(
          phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Polynomial Green weight scaling exceeded finite arithmetic.")
      }
      try OriginalPolynomialCoefficientOperations.record(
        fluxNumerator.coefficients.count, count: &coefficientOperations,
        maximum: maximumCoefficientOperations, using: &execution)
      var result: [[CertifiedUnivariateTaylorJet.Interval]] = []
      (try OriginalParameterQueryStorage.reserve(
        fluxNumerator.coefficients.count, in: &result, using: &execution))
      for row in fluxNumerator.coefficients {
        try execution.consumeWork(1)

        try OriginalPolynomialCoefficientOperations.record(
          row.count, count: &coefficientOperations, maximum: maximumCoefficientOperations,
          using: &execution)
        var values: [CertifiedUnivariateTaylorJet.Interval] = []
        (try OriginalParameterQueryStorage.reserve(row.count, in: &values, using: &execution))
        for coefficient in row {
          try execution.consumeWork(1)

          try OriginalPolynomialCoefficientOperations.record(
            1, count: &coefficientOperations, maximum: maximumCoefficientOperations,
            using: &execution)
          let quotient = coefficient / denominator
          (try OriginalParameterQueryStorage.append(
            .init(lower: quotient.lower, upper: quotient.upper), to: &values, using: &execution))
        }
        (try OriginalParameterQueryStorage.append(values, to: &result, using: &execution))
      }
      return result
    }

    init(
      certified: CertifiedHomogeneousBezierSurfacePatch,
      reference: Point3D,
      includeFluxNumerator: Bool = true,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
      let controls =
        (try OriginalParameterQueryStorage.map(
          certified.controls, using: &execution,
          transform: { row, execution in
            (try OriginalParameterQueryStorage.map(
              row, using: &execution,
              transform: { point, execution in
                HomogeneousPoint(
                  x: Interval(lower: point.x.lower, upper: point.x.upper),
                  y: Interval(lower: point.y.lower, upper: point.y.upper),
                  z: Interval(lower: point.z.lower, upper: point.z.upper),
                  weight: Interval(
                    lower: point.weight.lower,
                    upper: point.weight.upper
                  )
                )
              }))
          }))
      self.init(
        controls: controls,
        reference: reference,
        fluxNumerator: includeFluxNumerator
          ? try Self.makeFluxNumerator(
            controls: controls,
            reference: reference,
            tolerance: tolerance, using: &execution
          )
          : nil
      )
    }

    private init(
      controls: [[HomogeneousPoint]],
      reference: Point3D,
      fluxNumerator: ScalarPolynomial2D?
    ) {
      self.controls = controls
      self.reference = reference
      self.fluxNumerator = fluxNumerator
    }

    func trimmed(
      uLower: Double,
      uUpper: Double,
      vLower: Double,
      vUpper: Double,
      sourceUDomain: ParameterDomain,
      sourceVDomain: ParameterDomain,
      includeFluxNumerator: Bool = true,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Patch {
      try execution.consumeWork(1)

      let uBounds = try Self.normalizedBounds(
        lower: uLower,
        upper: uUpper,
        domain: sourceUDomain,
        tolerance: tolerance, using: &execution
      )
      let vBounds = try Self.normalizedBounds(
        lower: vLower,
        upper: vUpper,
        domain: sourceVDomain,
        tolerance: tolerance, using: &execution
      )
      var net = controls
      net = (try Self.trimRows(net, bounds: uBounds, using: &execution))
      net =
        (try Self.transpose(
          Self.trimRows(Self.transpose(net, using: &execution), bounds: vBounds, using: &execution),
          using: &execution))
      let uScale = uBounds.upper - uBounds.lower
      let vScale = vBounds.upper - vBounds.lower
      let trimmedFluxNumerator =
        includeFluxNumerator
        ? (try OriginalParameterQueryStorage.optionalMap(
          fluxNumerator, using: &execution,
          { element, execution in
            (try element.trimmed(u: uBounds, v: vBounds, using: &execution)
              .scaled(by: uScale * vScale, using: &execution))
          }))
        : nil
      return Patch(
        controls: net,
        reference: reference,
        fluxNumerator: trimmedFluxNumerator
      )
    }

    func subdivided(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
      throws -> [Patch]
    {
      try execution.consumeWork(1)

      guard let fluxNumerator else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message:
            "Certified rational surface flux subdivision requires a prepared determinant polynomial."
        )
      }
      let uHalves = (try Self.splitRows(controls, parameter: .exact(0.5), using: &execution))
      let lowerV =
        (try Self.splitRows(
          Self.transpose(uHalves.lower, using: &execution),
          parameter: .exact(0.5), using: &execution
        ))
      let upperV =
        (try Self.splitRows(
          Self.transpose(uHalves.upper, using: &execution),
          parameter: .exact(0.5), using: &execution
        ))
      let lower = BoundsPair(
        lower: .exact(0.0),
        upper: .exact(0.5)
      )
      let upper = BoundsPair(
        lower: .exact(0.5),
        upper: .exact(1.0)
      )
      let scale = Interval.exact(0.25)
      return
        (try OriginalParameterQueryStorage.values(count: 4, using: &execution) { execution in
          [
            Patch(
              controls: (try Self.transpose(lowerV.lower, using: &execution)),
              reference: reference,
              fluxNumerator: (try fluxNumerator
                .trimmed(u: lower, v: lower, using: &execution)
                .scaled(by: scale, using: &execution))
            ),
            Patch(
              controls: (try Self.transpose(upperV.lower, using: &execution)),
              reference: reference,
              fluxNumerator: (try fluxNumerator
                .trimmed(u: upper, v: lower, using: &execution)
                .scaled(by: scale, using: &execution))
            ),
            Patch(
              controls: (try Self.transpose(lowerV.upper, using: &execution)),
              reference: reference,
              fluxNumerator: (try fluxNumerator
                .trimmed(u: lower, v: upper, using: &execution)
                .scaled(by: scale, using: &execution))
            ),
            Patch(
              controls: (try Self.transpose(upperV.upper, using: &execution)),
              reference: reference,
              fluxNumerator: (try fluxNumerator
                .trimmed(u: upper, v: upper, using: &execution)
                .scaled(by: scale, using: &execution))
            ),
          ]
        })
    }

    func flux(
      u: Interval,
      v: Interval,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Interval {
      try execution.consumeWork(1)

      guard let fluxNumerator else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message:
            "Certified rational surface flux evaluation requires a prepared determinant polynomial."
        )
      }
      guard let restrictedU = u.intersection(.unit),
        let restrictedV = v.intersection(.unit)
      else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          tolerance: tolerance,
          message: "Certified rational surface flux parameters do not overlap the patch domain."
        )
      }
      let evaluatedWeight = try derivativeValue(
        component: { $0.weight },
        uOrder: 0,
        vOrder: 0,
        u: restrictedU,
        v: restrictedV,
        tolerance: tolerance, using: &execution
      )
      let weight = try certifiedWeightIntersection(
        evaluatedWeight,
        tolerance: tolerance, using: &execution
      )
      let evaluatedNumerator =
        (try fluxNumerator.evaluated(
          u: restrictedU,
          v: restrictedV, using: &execution
        ))
      // Restricted unit coordinates retain the nonnegative, partition-of-unity
      // tensor Bernstein basis. The same original determinant coefficient hull
      // therefore independently encloses this scalar numerator. Its scan reads
      // each coefficient once, bounded by the scalar evaluation already executed,
      // and creates no additional net, evaluation or private work allowance.
      var hullLower = Double.infinity
      var hullUpper = -Double.infinity
      var finiteCoefficients = true
      for row in fluxNumerator.coefficients {
        try execution.consumeWork(1)

        for coefficient in row {
          try execution.consumeWork(1)

          finiteCoefficients =
            finiteCoefficients
            && coefficient.lower.isFinite
            && coefficient.upper.isFinite
            && coefficient.lower <= coefficient.upper
          hullLower = min(hullLower, coefficient.lower)
          hullUpper = max(hullUpper, coefficient.upper)
        }
      }
      let numeratorLower = max(evaluatedNumerator.lower, hullLower)
      let numeratorUpper = min(evaluatedNumerator.upper, hullUpper)
      guard finiteCoefficients,
        evaluatedNumerator.lower.isFinite,
        evaluatedNumerator.upper.isFinite,
        hullLower.isFinite,
        hullUpper.isFinite,
        numeratorLower <= numeratorUpper
      else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message:
            "Certified rational surface flux numerator could not intersect its finite original coefficient hull."
        )
      }
      let numerator = Interval(lower: numeratorLower, upper: numeratorUpper)
      return numerator
        / (weight * weight * weight)
        / Interval.exact(3.0)
    }

    func directionalFluxJet(
      u: CertifiedUnivariateTaylorJet,
      v: CertifiedUnivariateTaylorJet,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedUnivariateTaylorJet {

      try execution.consumeWork(1)

      guard let fluxNumerator else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message:
            "Certified rational directional flux requires a prepared determinant polynomial."
        )
      }
      var weight = try univariateValue(
        component: { $0.weight },
        uOrder: 0,
        vOrder: 0,
        u: u,
        v: v,
        tolerance: tolerance, using: &execution
      )
      weight.coefficients[0] = try certifiedWeightIntersection(
        weight.coefficients[0],
        tolerance: tolerance, using: &execution
      )
      let inverseWeight = try weight.reciprocal(tolerance: tolerance, using: &execution)
      let numerator = (try fluxNumerator.evaluated(u: u, v: v, using: &execution))
      return try numerator.multiplied(by: inverseWeight, using: &execution).multiplied(
        by: inverseWeight, using: &execution
      ).multiplied(by: inverseWeight, using: &execution).divided(
        by: .constant(3.0, using: &execution), tolerance: tolerance, using: &execution)
    }

    func projectedBoundaryAreaJet(
      u: CertifiedUnivariateTaylorJet,
      v: CertifiedUnivariateTaylorJet,
      projection: AxisAlignedProjection,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedUnivariateTaylorJet {

      try execution.consumeWork(1)

      let components:
        (
          first: (HomogeneousPoint) -> Interval,
          second: (HomogeneousPoint) -> Interval
        )
      switch projection {
      case .normalX:
        components = ({ $0.y }, { $0.z })
      case .normalY:
        components = ({ $0.z }, { $0.x })
      case .normalZ:
        components = ({ $0.x }, { $0.y })
      }
      let first = try univariateValue(
        component: components.first,
        uOrder: 0,
        vOrder: 0,
        u: u,
        v: v,
        tolerance: tolerance, using: &execution
      )
      let second = try univariateValue(
        component: components.second,
        uOrder: 0,
        vOrder: 0,
        u: u,
        v: v,
        tolerance: tolerance, using: &execution
      )
      var weight = try univariateValue(
        component: { $0.weight },
        uOrder: 0,
        vOrder: 0,
        u: u,
        v: v,
        tolerance: tolerance, using: &execution
      )
      weight.coefficients[0] = try certifiedWeightIntersection(
        weight.coefficients[0],
        tolerance: tolerance, using: &execution
      )
      let inverseWeight = try weight.reciprocal(tolerance: tolerance, using: &execution)
      return try first.multiplied(by: second.derivative(using: &execution), using: &execution)
        .subtracting(
          second.multiplied(by: first.derivative(using: &execution), using: &execution),
          using: &execution
        ).multiplied(by: inverseWeight, using: &execution).multiplied(
          by: inverseWeight, using: &execution
        ).divided(
          by: .constant(2.0, using: &execution), tolerance: tolerance, using: &execution)
    }

    private static func makeFluxNumerator(
      controls: [[HomogeneousPoint]],
      reference: Point3D,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> ScalarPolynomial2D {
      try execution.consumeWork(1)

      let weight = ScalarPolynomial2D(
        (try OriginalParameterQueryStorage.map(
          controls, using: &execution,
          transform: { element, execution in
            (try OriginalParameterQueryStorage.map(
              element, using: &execution, transform: { element, execution in element.weight }))
          }))
      )
      let x = try ScalarPolynomial2D(
        OriginalParameterQueryStorage.map(
          controls, using: &execution,
          transform: { element, execution in
            (try OriginalParameterQueryStorage.map(
              element, using: &execution, transform: { element, execution in element.x }))
          })
      ).subtracting(
        weight.scaled(by: reference.x, using: &execution),
        tolerance: tolerance, using: &execution
      )
      let y = try ScalarPolynomial2D(
        OriginalParameterQueryStorage.map(
          controls, using: &execution,
          transform: { element, execution in
            (try OriginalParameterQueryStorage.map(
              element, using: &execution, transform: { element, execution in element.y }))
          })
      ).subtracting(
        weight.scaled(by: reference.y, using: &execution),
        tolerance: tolerance, using: &execution
      )
      let z = try ScalarPolynomial2D(
        OriginalParameterQueryStorage.map(
          controls, using: &execution,
          transform: { element, execution in
            (try OriginalParameterQueryStorage.map(
              element, using: &execution, transform: { element, execution in element.z }))
          })
      ).subtracting(
        weight.scaled(by: reference.z, using: &execution),
        tolerance: tolerance, using: &execution
      )
      let xU = (try x.derivativeU(using: &execution))
      let yU = (try y.derivativeU(using: &execution))
      let zU = (try z.derivativeU(using: &execution))
      let xV = (try x.derivativeV(using: &execution))
      let yV = (try y.derivativeV(using: &execution))
      let zV = (try z.derivativeV(using: &execution))
      let xTerm = try yU.multiplied(by: zV, using: &execution).subtracting(
        zU.multiplied(by: yV, using: &execution),
        tolerance: tolerance, using: &execution
      )
      let yTerm = try zU.multiplied(by: xV, using: &execution).subtracting(
        xU.multiplied(by: zV, using: &execution),
        tolerance: tolerance, using: &execution
      )
      let zTerm = try xU.multiplied(by: yV, using: &execution).subtracting(
        yU.multiplied(by: xV, using: &execution),
        tolerance: tolerance, using: &execution
      )
      return try x.multiplied(by: xTerm, using: &execution).adding(
        y.multiplied(by: yTerm, using: &execution),
        tolerance: tolerance, using: &execution
      ).adding(
        z.multiplied(by: zTerm, using: &execution),
        tolerance: tolerance, using: &execution
      )
    }

    private struct ScalarPolynomial2D {
      let coefficients: [[Interval]]

      private var uDegree: Int {
        (coefficients.first?.count ?? 1) - 1
      }

      private var vDegree: Int {
        coefficients.count - 1
      }

      init(_ coefficients: [[Interval]]) {
        self.coefficients = coefficients
      }

      func derivativeU(using execution: inout OriginalQueryExecution) throws -> Self {
        try execution.consumeWork(1)
        return

          Self(
            (try OriginalParameterQueryStorage.map(
              coefficients, using: &execution,
              transform: { row, execution in
                (try OriginalParameterQueryStorage.map(
                  (0..<uDegree), using: &execution,
                  transform: { index, execution in
                    (row[index + 1] - row[index])
                      * .exact(Double(uDegree))
                  }))
              })))
      }

      func derivativeV(using execution: inout OriginalQueryExecution) throws -> Self {
        try execution.consumeWork(1)
        return

          Self(
            (try OriginalParameterQueryStorage.map(
              (0..<vDegree), using: &execution,
              transform: { rowIndex, execution in
                (try OriginalParameterQueryStorage.map(
                  coefficients[rowIndex].indices, using: &execution,
                  transform: { columnIndex, execution in
                    (coefficients[rowIndex + 1][columnIndex]
                      - coefficients[rowIndex][columnIndex])
                      * .exact(Double(vDegree))
                  }))
              })))
      }

      func scaled(by value: Double, using execution: inout OriginalQueryExecution) throws -> Self {
        try execution.consumeWork(1)
        return

          (try scaled(by: .exact(value), using: &execution))
      }

      func scaled(by scale: Interval, using execution: inout OriginalQueryExecution) throws -> Self
      {
        try execution.consumeWork(1)

        return Self(
          (try OriginalParameterQueryStorage.map(
            coefficients, using: &execution,
            transform: { row, execution in
              (try OriginalParameterQueryStorage.map(
                row, using: &execution, transform: { element, execution in element * scale }))
            })))
      }

      func trimmed(u: BoundsPair, v: BoundsPair, using execution: inout OriginalQueryExecution)
        throws -> Self
      {
        try execution.consumeWork(1)

        let uTrimmed = (try Self.trimLines(coefficients, bounds: u, using: &execution))
        let transposed = (try Self.transpose(uTrimmed, using: &execution))
        let vTrimmed = (try Self.trimLines(transposed, bounds: v, using: &execution))
        return Self((try Self.transpose(vTrimmed, using: &execution)))
      }

      func evaluated(
        u: CertifiedUnivariateTaylorJet,
        v: CertifiedUnivariateTaylorJet, using execution: inout OriginalQueryExecution
      ) throws -> CertifiedUnivariateTaylorJet {
        try execution.consumeWork(1)

        let rows =
          (try OriginalParameterQueryStorage.map(
            coefficients, using: &execution,
            transform: { element, execution in
              (try Patch.evaluateUnivariate(element, parameter: u, using: &execution))
            }))
        return (try Patch.evaluateUnivariate(rows, parameter: v, using: &execution))
      }

      func evaluated(u: Interval, v: Interval, using execution: inout OriginalQueryExecution) throws
        -> Interval
      {
        try execution.consumeWork(1)

        let rows =
          (try OriginalParameterQueryStorage.map(
            coefficients, using: &execution,
            transform: { element, execution in
              (try Patch.evaluate(element, parameter: u, using: &execution))
            }))
        return (try Patch.evaluate(rows, parameter: v, using: &execution))
      }

      func adding(
        _ other: Self,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
      ) throws -> Self {
        try execution.consumeWork(1)

        try validateMatchingDegree(other, tolerance: tolerance, using: &execution)
        return Self(
          (try OriginalParameterQueryStorage.map(
            coefficients.indices, using: &execution,
            transform: { row, execution in
              (try OriginalParameterQueryStorage.map(
                coefficients[row].indices, using: &execution,
                transform: { column, execution in
                  coefficients[row][column]
                    + other.coefficients[row][column]
                }))
            })))
      }

      func subtracting(
        _ other: Self,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
      ) throws -> Self {
        try execution.consumeWork(1)

        try validateMatchingDegree(other, tolerance: tolerance, using: &execution)
        return Self(
          (try OriginalParameterQueryStorage.map(
            coefficients.indices, using: &execution,
            transform: { row, execution in
              (try OriginalParameterQueryStorage.map(
                coefficients[row].indices, using: &execution,
                transform: { column, execution in
                  coefficients[row][column]
                    - other.coefficients[row][column]
                }))
            })))
      }

      private func validateMatchingDegree(
        _ other: Self,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
      ) throws {
        try execution.consumeWork(1)

        guard uDegree == other.uDegree,
          vDegree == other.vDegree
        else {
          throw KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message: "Certified flux polynomial addition requires matching bidegrees."
          )
        }
      }

      func multiplied(by other: Self, using execution: inout OriginalQueryExecution) throws -> Self
      {
        try execution.consumeWork(1)

        let outputUDegree = self.uDegree + other.uDegree
        let outputVDegree = self.vDegree + other.vDegree
        var output = try OriginalParameterQueryStorage.map(
          0...outputVDegree, using: &execution,
          transform: { _, execution in
            try OriginalParameterQueryStorage.repeated(
              Interval.exact(0), count: outputUDegree + 1, using: &execution)
          })
        for outputV in 0...outputVDegree {
          try execution.consumeWork(1)

          let lhsVLower = max(0, outputV - other.vDegree)
          let lhsVUpper = min(self.vDegree, outputV)
          for outputU in 0...outputUDegree {
            try execution.consumeWork(1)

            let lhsULower = max(0, outputU - other.uDegree)
            let lhsUUpper = min(self.uDegree, outputU)
            var coefficient = Interval.exact(0.0)
            for lhsV in lhsVLower...lhsVUpper {
              try execution.consumeWork(1)

              let rhsV = outputV - lhsV
              let vWeight =
                (try Self.productWeight(
                  lhsDegree: self.vDegree,
                  lhsIndex: lhsV,
                  rhsDegree: other.vDegree,
                  rhsIndex: rhsV, using: &execution
                ))
              for lhsU in lhsULower...lhsUUpper {
                try execution.consumeWork(1)

                let rhsU = outputU - lhsU
                let uWeight =
                  (try Self.productWeight(
                    lhsDegree: self.uDegree,
                    lhsIndex: lhsU,
                    rhsDegree: other.uDegree,
                    rhsIndex: rhsU, using: &execution
                  ))
                coefficient =
                  coefficient
                  + self.coefficients[lhsV][lhsU]
                  * other.coefficients[rhsV][rhsU]
                  * uWeight * vWeight
              }
            }
            output[outputV][outputU] = coefficient
          }
        }
        return Self(output)
      }

      private static func productWeight(
        lhsDegree: Int,
        lhsIndex: Int,
        rhsDegree: Int,
        rhsIndex: Int, using execution: inout OriginalQueryExecution
      ) throws -> Interval {
        try execution.consumeWork(1)
        return

          (try binomial(lhsDegree, lhsIndex, using: &execution))
          * (try binomial(rhsDegree, rhsIndex, using: &execution))
          / (try binomial(
            lhsDegree + rhsDegree,
            lhsIndex + rhsIndex, using: &execution
          ))
      }

      private static func binomial(
        _ degree: Int, _ index: Int, using execution: inout OriginalQueryExecution
      ) throws -> Interval {
        try execution.consumeWork(1)

        let reducedIndex = min(index, degree - index)
        guard reducedIndex > 0 else { return .exact(1.0) }
        var value = Interval.exact(1.0)
        for factor in 1...reducedIndex {
          try execution.consumeWork(1)

          value =
            value
            * .exact(Double(degree - reducedIndex + factor))
            / .exact(Double(factor))
        }
        return value
      }

      private static func trimLines(
        _ lines: [[Interval]],
        bounds: BoundsPair, using execution: inout OriginalQueryExecution
      ) throws -> [[Interval]] {
        try execution.consumeWork(1)
        return

          (try OriginalParameterQueryStorage.map(
            lines, using: &execution,
            transform: { line, execution in
              var current = line
              if bounds.lower.upper > 0.0 {
                current = (try split(current, parameter: bounds.lower, using: &execution)).upper
              }
              if bounds.upper.lower < 1.0 {
                let localUpper =
                  (bounds.upper - bounds.lower)
                  / (Interval.exact(1.0) - bounds.lower)
                current = (try split(current, parameter: localUpper, using: &execution)).lower
              }
              return current
            }))
      }

      private static func split(
        _ values: [Interval],
        parameter: Interval, using execution: inout OriginalQueryExecution
      ) throws -> (lower: [Interval], upper: [Interval]) {
        try execution.consumeWork(1)

        let complement = Interval.exact(1.0) - parameter
        var levels =
          (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
            [values]
          })
        while let previous = levels.last, previous.count > 1 {
          try execution.consumeWork(1)

          (try OriginalParameterQueryStorage.append(
            OriginalParameterQueryStorage.map(
              (0..<(previous.count - 1)), using: &execution,
              transform: { index, execution in
                previous[index] * complement
                  + previous[index + 1] * parameter
              }), to: &levels, using: &execution))
        }
        return (
          (try OriginalParameterQueryStorage.map(
            levels, using: &execution, transform: { element, execution in element[0] })),
          (try OriginalParameterQueryStorage.map(
            levels.reversed(), using: &execution,
            transform: { element, execution in element[element.count - 1] }))
        )
      }

      private static func transpose(
        _ values: [[Interval]], using execution: inout OriginalQueryExecution
      ) throws -> [[Interval]] {
        try execution.consumeWork(1)

        guard let first = values.first else { return [] }
        return
          (try OriginalParameterQueryStorage.map(
            first.indices, using: &execution,
            transform: { column, execution in
              (try OriginalParameterQueryStorage.map(
                values.indices, using: &execution,
                transform: { row, execution in values[row][column] }))
            }))
      }
    }

    private func univariateValue(
      component: (HomogeneousPoint) -> Interval,
      uOrder: Int,
      vOrder: Int,
      u: CertifiedUnivariateTaylorJet,
      v: CertifiedUnivariateTaylorJet,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedUnivariateTaylorJet {
      try execution.consumeWork(1)

      let net = try derivativeNet(
        component: component,
        uOrder: uOrder,
        vOrder: vOrder,
        tolerance: tolerance, using: &execution
      )
      let rows =
        (try OriginalParameterQueryStorage.map(
          net, using: &execution,
          transform: { element, execution in
            (try Self.evaluateUnivariate(element, parameter: u, using: &execution))
          }))
      return (try Self.evaluateUnivariate(rows, parameter: v, using: &execution))
    }

    private func certifiedWeightIntersection(
      _ evaluated: Interval,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Interval {
      try execution.consumeWork(1)

      let controlHull =
        (try Interval.hull(
          OriginalParameterQueryStorage.flatMap(
            controls, using: &execution,
            { row, execution in
              (try OriginalParameterQueryStorage.map(
                row, using: &execution, transform: { element, execution in element.weight }))
            }), using: &execution
        ))
      guard let certified = evaluated.intersection(controlHull),
        certified.lower > 0.0
      else {
        throw KernelError(
          phase: .topology,
          code: .singularSystem,
          residual: evaluated.lower,
          tolerance: tolerance,
          message: "Certified rational surface flux could not prove a positive point weight."
        )
      }
      return certified
    }

    private func certifiedWeightIntersection(
      _ evaluated: CertifiedUnivariateTaylorJet.Interval,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedUnivariateTaylorJet.Interval {
      try execution.consumeWork(1)

      let interval = try certifiedWeightIntersection(
        Interval(lower: evaluated.lower, upper: evaluated.upper),
        tolerance: tolerance, using: &execution
      )
      return CertifiedUnivariateTaylorJet.Interval(
        lower: interval.lower,
        upper: interval.upper
      )
    }

    private static func evaluateUnivariate(
      _ values: [Interval],
      parameter: CertifiedUnivariateTaylorJet, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedUnivariateTaylorJet {
      try execution.consumeWork(1)
      return

        (try evaluateUnivariate(
          OriginalParameterQueryStorage.map(
            values, using: &execution,
            transform: { element, execution in
              (try CertifiedUnivariateTaylorJet.constant(
                CertifiedUnivariateTaylorJet.Interval(
                  lower: element.lower,
                  upper: element.upper
                ), using: &execution
              ))
            }),
          parameter: parameter, using: &execution
        ))
    }

    private static func evaluateUnivariate(
      _ values: [CertifiedUnivariateTaylorJet],
      parameter: CertifiedUnivariateTaylorJet, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedUnivariateTaylorJet {
      try execution.consumeWork(1)

      var level = values
      let complement =
        (try CertifiedUnivariateTaylorJet.constant(1.0, using: &execution).subtracting(
          parameter, using: &execution))
      while level.count > 1 {
        try execution.consumeWork(1)

        level =
          (try OriginalParameterQueryStorage.map(
            (0..<(level.count - 1)), using: &execution,
            transform: { index, execution in
              (try (level[index]).multiplied(by: complement, using: &execution).adding(
                (level[index + 1]).multiplied(by: parameter, using: &execution), using: &execution))
            }))
      }
      return level[0]
    }

    func sixthFluxDerivativeBound(
      primary: Direction,
      reference: Point3D,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Interval {
      try execution.consumeWork(1)

      let valueX = try coordinateJet(
        component: { $0.x },
        primary: primary,
        tolerance: tolerance, using: &execution
      )
      let valueY = try coordinateJet(
        component: { $0.y },
        primary: primary,
        tolerance: tolerance, using: &execution
      )
      let valueZ = try coordinateJet(
        component: { $0.z },
        primary: primary,
        tolerance: tolerance, using: &execution
      )
      let weight = try coordinateJet(
        component: { $0.weight },
        primary: primary,
        tolerance: tolerance, using: &execution
      )
      let secondaryWeight = try secondaryCoordinateJet(
        component: { $0.weight },
        primary: primary,
        tolerance: tolerance, using: &execution
      )
      let reciprocalWeight = try weight.reciprocal(tolerance: tolerance, using: &execution)
      let squaredReciprocal =
        (try reciprocalWeight.multiplied(by: reciprocalWeight, using: &execution))

      let position =
        (try IntervalVectorJet(
          x: valueX.multiplied(by: reciprocalWeight, using: &execution),
          y: valueY.multiplied(by: reciprocalWeight, using: &execution),
          z: valueZ.multiplied(by: reciprocalWeight, using: &execution)
        ).truncated(to: 6, using: &execution))
      let primaryTangent =
        (try positionFromFullJets(
          x: valueX.multiplied(by: reciprocalWeight, using: &execution),
          y: valueY.multiplied(by: reciprocalWeight, using: &execution),
          z: valueZ.multiplied(by: reciprocalWeight, using: &execution), using: &execution
        ).derivative(using: &execution))
      let secondaryX = try secondaryEuclideanJet(
        value: valueX,
        secondary: secondaryCoordinateJet(
          component: { $0.x },
          primary: primary,
          tolerance: tolerance, using: &execution
        ),
        weight: weight,
        secondaryWeight: secondaryWeight,
        squaredReciprocal: squaredReciprocal, using: &execution
      )
      let secondaryY = try secondaryEuclideanJet(
        value: valueY,
        secondary: secondaryCoordinateJet(
          component: { $0.y },
          primary: primary,
          tolerance: tolerance, using: &execution
        ),
        weight: weight,
        secondaryWeight: secondaryWeight,
        squaredReciprocal: squaredReciprocal, using: &execution
      )
      let secondaryZ = try secondaryEuclideanJet(
        value: valueZ,
        secondary: secondaryCoordinateJet(
          component: { $0.z },
          primary: primary,
          tolerance: tolerance, using: &execution
        ),
        weight: weight,
        secondaryWeight: secondaryWeight,
        squaredReciprocal: squaredReciprocal, using: &execution
      )
      let secondaryTangent = IntervalVectorJet(
        x: secondaryX,
        y: secondaryY,
        z: secondaryZ
      )
      let tangentU = primary == .u ? primaryTangent : secondaryTangent
      let tangentV = primary == .u ? secondaryTangent : primaryTangent
      let relative = (try position.subtracting(reference, using: &execution))
      let flux =
        (try relative.dot(tangentU.cross(tangentV, using: &execution), using: &execution)
          .scaled(by: Interval.exact(1.0) / Interval.exact(3.0), using: &execution))
      guard flux.values.count == 7 else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Certified rational surface flux did not construct a sixth derivative jet."
        )
      }
      return flux.values[6]
    }

    private func secondaryEuclideanJet(
      value: IntervalJet,
      secondary: IntervalJet,
      weight: IntervalJet,
      secondaryWeight: IntervalJet,
      squaredReciprocal: IntervalJet, using execution: inout OriginalQueryExecution
    ) throws -> IntervalJet {
      try execution.consumeWork(1)
      return

        (try secondary.multiplied(by: weight, using: &execution).subtracting(
          value.multiplied(by: secondaryWeight, using: &execution), using: &execution
        ).multiplied(by: squaredReciprocal, using: &execution))
    }

    private func positionFromFullJets(
      x: IntervalJet,
      y: IntervalJet,
      z: IntervalJet, using execution: inout OriginalQueryExecution
    ) throws -> IntervalVectorJet {
      try execution.consumeWork(1)
      return

        IntervalVectorJet(x: x, y: y, z: z)
    }

    private func coordinateJet(
      component: (HomogeneousPoint) -> Interval,
      primary: Direction,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> IntervalJet {
      try execution.consumeWork(1)

      let values = try OriginalParameterQueryStorage.map(
        (0...7), using: &execution,
        transform: { order, execution in
          try derivativeRange(
            component: component,
            uOrder: primary == .u ? order : 0,
            vOrder: primary == .v ? order : 0,
            tolerance: tolerance, using: &execution
          )
        })
      return IntervalJet(values)
    }

    private func secondaryCoordinateJet(
      component: (HomogeneousPoint) -> Interval,
      primary: Direction,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> IntervalJet {
      try execution.consumeWork(1)

      let values = try OriginalParameterQueryStorage.map(
        (0...6), using: &execution,
        transform: { order, execution in
          try derivativeRange(
            component: component,
            uOrder: primary == .u ? order : 1,
            vOrder: primary == .v ? order : 1,
            tolerance: tolerance, using: &execution
          )
        })
      return IntervalJet(values)
    }

    private func derivativeRange(
      component: (HomogeneousPoint) -> Interval,
      uOrder: Int,
      vOrder: Int,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Interval {
      try execution.consumeWork(1)

      let net = try derivativeNet(
        component: component,
        uOrder: uOrder,
        vOrder: vOrder,
        tolerance: tolerance, using: &execution
      )
      return
        (try Interval.hull(
          OriginalParameterQueryStorage.flatMap(
            net, using: &execution, { element, execution in element }), using: &execution))
    }

    private func pointValue(
      u: Interval,
      v: Interval,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> HomogeneousPoint {
      try execution.consumeWork(1)
      return

        HomogeneousPoint(
          x: try derivativeValue(
            component: { $0.x },
            uOrder: 0,
            vOrder: 0,
            u: u,
            v: v,
            tolerance: tolerance, using: &execution
          ),
          y: try derivativeValue(
            component: { $0.y },
            uOrder: 0,
            vOrder: 0,
            u: u,
            v: v,
            tolerance: tolerance, using: &execution
          ),
          z: try derivativeValue(
            component: { $0.z },
            uOrder: 0,
            vOrder: 0,
            u: u,
            v: v,
            tolerance: tolerance, using: &execution
          ),
          weight: try derivativeValue(
            component: { $0.weight },
            uOrder: 0,
            vOrder: 0,
            u: u,
            v: v,
            tolerance: tolerance, using: &execution
          )
        )
    }

    private func derivativeValue(
      uOrder: Int,
      vOrder: Int,
      u: Interval,
      v: Interval,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> HomogeneousPoint {
      try execution.consumeWork(1)
      return

        HomogeneousPoint(
          x: try derivativeValue(
            component: { $0.x },
            uOrder: uOrder,
            vOrder: vOrder,
            u: u,
            v: v,
            tolerance: tolerance, using: &execution
          ),
          y: try derivativeValue(
            component: { $0.y },
            uOrder: uOrder,
            vOrder: vOrder,
            u: u,
            v: v,
            tolerance: tolerance, using: &execution
          ),
          z: try derivativeValue(
            component: { $0.z },
            uOrder: uOrder,
            vOrder: vOrder,
            u: u,
            v: v,
            tolerance: tolerance, using: &execution
          ),
          weight: try derivativeValue(
            component: { $0.weight },
            uOrder: uOrder,
            vOrder: vOrder,
            u: u,
            v: v,
            tolerance: tolerance, using: &execution
          )
        )
    }

    private func derivativeValue(
      component: (HomogeneousPoint) -> Interval,
      uOrder: Int,
      vOrder: Int,
      u: Interval,
      v: Interval,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Interval {
      try execution.consumeWork(1)

      let net = try derivativeNet(
        component: component,
        uOrder: uOrder,
        vOrder: vOrder,
        tolerance: tolerance, using: &execution
      )
      let rows =
        (try OriginalParameterQueryStorage.map(
          net, using: &execution,
          transform: { element, execution in
            (try Self.evaluate(element, parameter: u, using: &execution))
          }))
      return (try Self.evaluate(rows, parameter: v, using: &execution))
    }

    private func derivativeNet(
      component: (HomogeneousPoint) -> Interval,
      uOrder: Int,
      vOrder: Int,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [[Interval]] {
      try execution.consumeWork(1)

      var net =
        (try OriginalParameterQueryStorage.map(
          controls, using: &execution,
          transform: { row, execution in
            (try OriginalParameterQueryStorage.map(
              row, using: &execution, transform: { element, execution in component(element) }))
          }))
      if let constant = (try Self.exactConstant(in: net, using: &execution)) {
        return uOrder == 0 && vOrder == 0
          ? (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
            [
              (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
                [constant]
              })
            ]
          })
          : (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
            [
              (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
                [.exact(0.0)]
              })
            ]
          })
      }
      for _ in 0..<uOrder {
        try execution.consumeWork(1)

        guard let columnCount = net.first?.count,
          columnCount >= 2
        else {
          return
            (try OriginalParameterQueryStorage.map(
              net, using: &execution,
              transform: { _, execution in
                (try OriginalParameterQueryStorage.values(count: 1, using: &execution) {
                  execution in [Interval.exact(0.0)]
                })
              }))
        }
        let degree = columnCount - 1
        net =
          (try OriginalParameterQueryStorage.map(
            net, using: &execution,
            transform: { row, execution in
              (try OriginalParameterQueryStorage.map(
                (0..<degree), using: &execution,
                transform: { index, execution in
                  (row[index + 1] - row[index]) * Interval.exact(Double(degree))
                }))
            }))
      }
      for _ in 0..<vOrder {
        try execution.consumeWork(1)

        guard net.count >= 2 else {
          return
            (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
              [
                (try OriginalParameterQueryStorage.repeated(
                  Interval.exact(0.0), count: net.first?.count ?? 1, using: &execution))
              ]
            })
        }
        let degree = net.count - 1
        net =
          (try OriginalParameterQueryStorage.map(
            (0..<degree), using: &execution,
            transform: { rowIndex, execution in
              (try OriginalParameterQueryStorage.map(
                net[rowIndex].indices, using: &execution,
                transform: { columnIndex, execution in
                  (net[rowIndex + 1][columnIndex] - net[rowIndex][columnIndex])
                    * Interval.exact(Double(degree))
                }))
            }))
      }
      guard !net.isEmpty,
        try OriginalParameterQueryStorage.allSatisfy(
          net, using: &execution, predicate: { element, execution in !element.isEmpty })
      else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Certified rational surface flux produced an empty derivative net."
        )
      }
      return net
    }

    private static func exactConstant(
      in net: [[Interval]], using execution: inout OriginalQueryExecution
    ) throws -> Interval? {
      try execution.consumeWork(1)

      guard let first = net.first?.first,
        first.lower == first.upper,
        try OriginalParameterQueryStorage.allSatisfy(
          net, using: &execution,
          predicate: { row, execution in
            try !row.isEmpty
              && (try OriginalParameterQueryStorage.allSatisfy(
                row, using: &execution,
                predicate: { element, execution in
                  element.lower == first.lower && element.upper == first.upper
                }))
          })
      else {
        return nil
      }
      return first
    }

    private static func evaluate(
      _ values: [Interval],
      parameter: Interval, using execution: inout OriginalQueryExecution
    ) throws -> Interval {
      try execution.consumeWork(1)

      var level = values
      let complement = Interval.exact(1.0) - parameter
      while level.count > 1 {
        try execution.consumeWork(1)

        level =
          (try OriginalParameterQueryStorage.map(
            (0..<(level.count - 1)), using: &execution,
            transform: { index, execution in
              level[index] * complement + level[index + 1] * parameter
            }))
      }
      return level[0]
    }

    private static func normalizedBounds(
      lower: Double,
      upper: Double,
      domain: ParameterDomain,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BoundsPair {
      try execution.consumeWork(1)

      guard case .closed(let domainLower, let domainUpper) = domain,
        lower >= domainLower,
        upper <= domainUpper,
        upper > lower
      else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "Rational Bezier surface trim lies outside its exact parameter domain."
        )
      }
      let span = Interval.exact(domainUpper) - Interval.exact(domainLower)
      let normalizedLower =
        lower == domainLower
        ? Interval.exact(0.0)
        : (Interval.exact(lower) - Interval.exact(domainLower)) / span
      let normalizedUpper =
        upper == domainUpper
        ? Interval.exact(1.0)
        : (Interval.exact(upper) - Interval.exact(domainLower)) / span
      guard let clampedLower = normalizedLower.intersection(.unit),
        let clampedUpper = normalizedUpper.intersection(.unit)
      else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "Rational Bezier surface trim normalization is empty."
        )
      }
      return BoundsPair(lower: clampedLower, upper: clampedUpper)
    }

    private static func trimRows(
      _ rows: [[HomogeneousPoint]],
      bounds: BoundsPair, using execution: inout OriginalQueryExecution
    ) throws -> [[HomogeneousPoint]] {
      try execution.consumeWork(1)
      return

        (try OriginalParameterQueryStorage.map(
          rows, using: &execution,
          transform: { row, execution in
            var current = row
            if bounds.lower.upper > 0.0 {
              current = (try split(row, parameter: bounds.lower, using: &execution)).upper
            }
            if bounds.upper.lower < 1.0 {
              let localUpper =
                (bounds.upper - bounds.lower)
                / (Interval.exact(1.0) - bounds.lower)
              current = (try split(current, parameter: localUpper, using: &execution)).lower
            }
            return current
          }))
    }

    private static func splitRows(
      _ rows: [[HomogeneousPoint]],
      parameter: Interval, using execution: inout OriginalQueryExecution
    ) throws -> (lower: [[HomogeneousPoint]], upper: [[HomogeneousPoint]]) {
      try execution.consumeWork(1)

      var lower: [[HomogeneousPoint]] = []
      var upper: [[HomogeneousPoint]] = []
      for row in rows {
        try execution.consumeWork(1)

        let halves = (try split(row, parameter: parameter, using: &execution))
        (try OriginalParameterQueryStorage.append(halves.lower, to: &lower, using: &execution))
        (try OriginalParameterQueryStorage.append(halves.upper, to: &upper, using: &execution))
      }
      return (lower, upper)
    }

    private static func split(
      _ values: [HomogeneousPoint],
      parameter: Interval, using execution: inout OriginalQueryExecution
    ) throws -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
      try execution.consumeWork(1)

      var levels =
        (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
          [values]
        })
      while let previous = levels.last, previous.count > 1 {
        try execution.consumeWork(1)

        (try OriginalParameterQueryStorage.append(
          OriginalParameterQueryStorage.map(
            (0..<(previous.count - 1)), using: &execution,
            transform: { index, execution in
              previous[index].interpolated(
                to: previous[index + 1],
                parameter: parameter
              )
            }), to: &levels, using: &execution))
      }
      return (
        (try OriginalParameterQueryStorage.map(
          levels, using: &execution, transform: { element, execution in element[0] })),
        (try OriginalParameterQueryStorage.map(
          levels.reversed(), using: &execution,
          transform: { element, execution in element[element.count - 1] }))
      )
    }

    private static func transpose(
      _ values: [[HomogeneousPoint]], using execution: inout OriginalQueryExecution
    ) throws -> [[HomogeneousPoint]] {
      try execution.consumeWork(1)

      guard let first = values.first else { return [] }
      return
        (try OriginalParameterQueryStorage.map(
          first.indices, using: &execution,
          transform: { column, execution in
            (try OriginalParameterQueryStorage.map(
              values.indices, using: &execution,
              transform: { row, execution in values[row][column] }))
          }))
    }
  }

  private struct BoundsPair {
    let lower: Interval
    let upper: Interval
  }

  private struct HomogeneousPoint {
    let x: Interval
    let y: Interval
    let z: Interval
    let weight: Interval

    func interpolated(
      to other: HomogeneousPoint,
      parameter: Interval
    ) -> HomogeneousPoint {
      let complement = Interval.exact(1.0) - parameter
      return HomogeneousPoint(
        x: x * complement + other.x * parameter,
        y: y * complement + other.y * parameter,
        z: z * complement + other.z * parameter,
        weight: weight * complement + other.weight * parameter
      )
    }

    func euclidean(tolerance: ModelingTolerance) throws -> IntervalVector3 {
      guard weight.lower > 0.0 else {
        throw Self.singularWeight(weight, tolerance: tolerance)
      }
      return IntervalVector3(
        x: x / weight,
        y: y / weight,
        z: z / weight
      )
    }

    static func euclideanDerivative(
      value: HomogeneousPoint,
      derivative: HomogeneousPoint,
      tolerance: ModelingTolerance
    ) throws -> IntervalVector3 {
      guard value.weight.lower > 0.0 else {
        throw Self.singularWeight(value.weight, tolerance: tolerance)
      }
      let denominator = value.weight * value.weight
      return IntervalVector3(
        x: (derivative.x * value.weight - value.x * derivative.weight)
          / denominator,
        y: (derivative.y * value.weight - value.y * derivative.weight)
          / denominator,
        z: (derivative.z * value.weight - value.z * derivative.weight)
          / denominator
      )
    }

    static func singularWeight(
      _ weight: Interval,
      tolerance: ModelingTolerance
    ) -> KernelError {
      KernelError(
        phase: .topology,
        code: .singularSystem,
        residual: weight.lower,
        tolerance: tolerance,
        message: "Certified rational surface flux encountered a non-positive weight enclosure."
      )
    }
  }

  private struct IntervalVector3 {
    let x: Interval
    let y: Interval
    let z: Interval

    init(x: Interval, y: Interval, z: Interval) {
      self.x = x
      self.y = y
      self.z = z
    }

    init(_ point: Point3D) {
      x = .exact(point.x)
      y = .exact(point.y)
      z = .exact(point.z)
    }

    static func - (lhs: IntervalVector3, rhs: IntervalVector3) -> IntervalVector3 {
      IntervalVector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    func cross(_ other: IntervalVector3, using execution: inout OriginalQueryExecution) throws
      -> IntervalVector3
    {
      try execution.consumeWork(1)
      return

        IntervalVector3(
          x: y * other.z - z * other.y,
          y: z * other.x - x * other.z,
          z: x * other.y - y * other.x
        )
    }

    func dot(_ other: IntervalVector3, using execution: inout OriginalQueryExecution) throws
      -> Interval
    {
      try execution.consumeWork(1)
      return

        x * other.x + y * other.y + z * other.z
    }
  }

  private struct UnivariateVector3 {
    let x: CertifiedUnivariateTaylorJet
    let y: CertifiedUnivariateTaylorJet
    let z: CertifiedUnivariateTaylorJet

    func subtracting(_ point: Point3D, using execution: inout OriginalQueryExecution) throws
      -> UnivariateVector3
    {
      try execution.consumeWork(1)
      return

        UnivariateVector3(
          x: try x.subtracting(.constant(point.x, using: &execution), using: &execution),
          y: try y.subtracting(.constant(point.y, using: &execution), using: &execution),
          z: try z.subtracting(.constant(point.z, using: &execution), using: &execution)
        )
    }

    func cross(_ other: UnivariateVector3, using execution: inout OriginalQueryExecution) throws
      -> UnivariateVector3
    {
      try execution.consumeWork(1)
      return

        UnivariateVector3(
          x: (try y.multiplied(by: other.z, using: &execution).subtracting(
            z.multiplied(by: other.y, using: &execution), using: &execution)),
          y: (try z.multiplied(by: other.x, using: &execution).subtracting(
            x.multiplied(by: other.z, using: &execution), using: &execution)),
          z: (try x.multiplied(by: other.y, using: &execution).subtracting(
            y.multiplied(by: other.x, using: &execution), using: &execution))
        )
    }

    func dot(_ other: UnivariateVector3, using execution: inout OriginalQueryExecution) throws
      -> CertifiedUnivariateTaylorJet
    {
      try execution.consumeWork(1)
      return

        (try x.multiplied(by: other.x, using: &execution).adding(
          y.multiplied(by: other.y, using: &execution), using: &execution
        ).adding(z.multiplied(by: other.z, using: &execution), using: &execution))
    }
  }

  private struct IntervalVectorJet {
    let x: IntervalJet
    let y: IntervalJet
    let z: IntervalJet

    func truncated(to order: Int, using execution: inout OriginalQueryExecution) throws
      -> IntervalVectorJet
    {
      try execution.consumeWork(1)
      return

        IntervalVectorJet(
          x: (try x.truncated(to: order, using: &execution)),
          y: (try y.truncated(to: order, using: &execution)),
          z: (try z.truncated(to: order, using: &execution))
        )
    }

    func derivative(using execution: inout OriginalQueryExecution) throws -> IntervalVectorJet {
      try execution.consumeWork(1)
      return

        IntervalVectorJet(
          x: (try x.derivative(using: &execution)), y: (try y.derivative(using: &execution)),
          z: (try z.derivative(using: &execution)))
    }

    func subtracting(_ point: Point3D, using execution: inout OriginalQueryExecution) throws
      -> IntervalVectorJet
    {
      try execution.consumeWork(1)
      return

        IntervalVectorJet(
          x: (try x.subtracting(constant: point.x, using: &execution)),
          y: (try y.subtracting(constant: point.y, using: &execution)),
          z: (try z.subtracting(constant: point.z, using: &execution))
        )
    }

    func cross(_ other: IntervalVectorJet, using execution: inout OriginalQueryExecution) throws
      -> IntervalVectorJet
    {
      try execution.consumeWork(1)
      return

        IntervalVectorJet(
          x: (try y.multiplied(by: other.z, using: &execution).subtracting(
            z.multiplied(by: other.y, using: &execution), using: &execution)),
          y: (try z.multiplied(by: other.x, using: &execution).subtracting(
            x.multiplied(by: other.z, using: &execution), using: &execution)),
          z: (try x.multiplied(by: other.y, using: &execution).subtracting(
            y.multiplied(by: other.x, using: &execution), using: &execution))
        )
    }

    func dot(_ other: IntervalVectorJet, using execution: inout OriginalQueryExecution) throws
      -> IntervalJet
    {
      try execution.consumeWork(1)
      return

        (try x.multiplied(by: other.x, using: &execution).adding(
          y.multiplied(by: other.y, using: &execution), using: &execution
        ).adding(z.multiplied(by: other.z, using: &execution), using: &execution))
    }
  }

  private struct IntervalJet {
    let values: [Interval]

    init(_ values: [Interval]) {
      self.values = values
    }

    var order: Int {
      values.count - 1
    }

    func truncated(to requestedOrder: Int, using execution: inout OriginalQueryExecution) throws
      -> IntervalJet
    {
      try execution.consumeWork(1)
      return

        IntervalJet(
          (try OriginalParameterQueryStorage.materialize(
            values.prefix(requestedOrder + 1), using: &execution)))
    }

    func derivative(using execution: inout OriginalQueryExecution) throws -> IntervalJet {
      try execution.consumeWork(1)
      return

        IntervalJet(
          (try OriginalParameterQueryStorage.materialize(values.dropFirst(), using: &execution)))
    }

    func subtracting(constant: Double, using execution: inout OriginalQueryExecution) throws
      -> IntervalJet
    {
      try execution.consumeWork(1)

      try execution.retainStorage(count: values.count, stride: MemoryLayout<Interval>.stride)
      var result = values
      result[0] = result[0] - .exact(constant)
      return IntervalJet(result)
    }

    func scaled(by scale: Interval, using execution: inout OriginalQueryExecution) throws
      -> IntervalJet
    {
      try execution.consumeWork(1)
      return

        IntervalJet(
          (try OriginalParameterQueryStorage.map(
            values, using: &execution, transform: { element, execution in element * scale })))
    }

    func reciprocal(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
      throws -> IntervalJet
    {
      try execution.consumeWork(1)

      guard values[0].lower > 0.0 || values[0].upper < 0.0 else {
        throw KernelError(
          phase: .topology,
          code: .singularSystem,
          residual: values[0].minimumAbsolute,
          tolerance: tolerance,
          message: "Certified rational surface flux encountered a singular reciprocal jet."
        )
      }
      var result =
        (try OriginalParameterQueryStorage.repeated(
          Interval.exact(0.0), count: values.count, using: &execution))
      result[0] = Interval.exact(1.0) / values[0]
      if order > 0 {
        for derivativeOrder in 1...order {
          try execution.consumeWork(1)

          var sum = Interval.exact(0.0)
          for index in 1...derivativeOrder {
            try execution.consumeWork(1)

            sum =
              sum + Interval.exact(
                Double((try Self.binomial(derivativeOrder, index, using: &execution))))
              * values[index] * result[derivativeOrder - index]
          }
          result[derivativeOrder] = -(sum / values[0])
        }
      }
      return IntervalJet(result)
    }

    func adding(_ other: IntervalJet, using execution: inout OriginalQueryExecution) throws
      -> IntervalJet
    {
      try execution.consumeWork(1)

      let order = min(self.order, other.order)
      return IntervalJet(
        (try OriginalParameterQueryStorage.map(
          (0...order), using: &execution,
          transform: { element, execution in self.values[element] + other.values[element] })))
    }

    func subtracting(_ other: IntervalJet, using execution: inout OriginalQueryExecution) throws
      -> IntervalJet
    {
      try execution.consumeWork(1)

      let order = min(self.order, other.order)
      return IntervalJet(
        (try OriginalParameterQueryStorage.map(
          (0...order), using: &execution,
          transform: { element, execution in self.values[element] - other.values[element] })))
    }

    func multiplied(by other: IntervalJet, using execution: inout OriginalQueryExecution) throws
      -> IntervalJet
    {
      try execution.consumeWork(1)

      let order = min(self.order, other.order)
      return IntervalJet(
        (try OriginalParameterQueryStorage.map(
          (0...order), using: &execution,
          transform: { derivativeOrder, execution in
            var value = Interval.exact(0.0)
            for index in 0...derivativeOrder {
              try execution.consumeWork(1)

              value =
                value + Interval.exact(
                  Double((try Self.binomial(derivativeOrder, index, using: &execution))))
                * self.values[index] * other.values[derivativeOrder - index]
            }
            return value
          })))
    }

    private static func binomial(_ n: Int, _ k: Int, using execution: inout OriginalQueryExecution)
      throws -> Int
    {
      try execution.consumeWork(1)

      let reducedK = min(k, n - k)
      guard reducedK > 0 else { return 1 }
      var result = 1
      for index in 1...reducedK {
        try execution.consumeWork(1)

        result = result * (n - reducedK + index) / index
      }
      return result
    }
  }

  private struct CellCount {
    let limit: Int
    var consumed = 0

    mutating func consume(
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
      try execution.consumeWork(1)

      guard consumed < limit else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: Double(consumed),
          tolerance: tolerance,
          message: "Certified rational surface flux exhausted its cell budget."
        )
      }
      consumed += 1
    }
  }

  private struct Interval: Sendable, Hashable {
    static let unit = Interval(lower: 0.0, upper: 1.0)

    let lower: Double
    let upper: Double

    init(lower: Double, upper: Double) {
      self.lower = lower
      self.upper = upper
    }

    static func exact(_ value: Double) -> Interval {
      Interval(lower: value, upper: value)
    }

    var errorRadius: Double {
      (upper - lower) * 0.5
    }

    var maximumAbsolute: Double {
      max(abs(lower), abs(upper)).nextUp
    }

    var minimumAbsolute: Double {
      if lower <= 0.0, upper >= 0.0 { return 0.0 }
      return min(abs(lower), abs(upper)).nextDown
    }

    static func hull(_ values: [Interval], using execution: inout OriginalQueryExecution) throws
      -> Interval
    {
      try execution.consumeWork(1)
      return

        Interval(
          lower: ((try OriginalParameterQueryStorage.extrema(
            OriginalParameterQueryStorage.map(
              values, using: &execution, transform: { element, execution in element.lower }),
            using: &execution, projection: { element, _ in element }))?.lower ?? -.infinity)
            .nextDown,
          upper: ((try OriginalParameterQueryStorage.extrema(
            OriginalParameterQueryStorage.map(
              values, using: &execution, transform: { element, execution in element.upper }),
            using: &execution, projection: { element, _ in element }))?.upper ?? .infinity).nextUp
        )
    }

    func intersection(_ other: Interval) -> Interval? {
      let resultLower = max(lower, other.lower)
      let resultUpper = min(upper, other.upper)
      guard resultLower <= resultUpper else { return nil }
      return Interval(lower: resultLower, upper: resultUpper)
    }

    func squareRoot(
      tolerance: ModelingTolerance
    ) throws -> Interval {
      guard lower >= 0.0, upper.isFinite else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          tolerance: tolerance,
          message: "Certified interval square root requires a finite nonnegative interval."
        )
      }
      return Interval(
        lower: sqrt(lower).nextDown,
        upper: sqrt(upper).nextUp
      )
    }

    static prefix func - (value: Interval) -> Interval {
      Interval(lower: (-value.upper).nextDown, upper: (-value.lower).nextUp)
    }

    static func + (lhs: Interval, rhs: Interval) -> Interval {
      Interval(
        lower: (lhs.lower + rhs.lower).nextDown,
        upper: (lhs.upper + rhs.upper).nextUp
      )
    }

    static func - (lhs: Interval, rhs: Interval) -> Interval {
      lhs + (-rhs)
    }

    static func * (lhs: Interval, rhs: Interval) -> Interval {
      let first = lhs.lower * rhs.lower
      let second = lhs.lower * rhs.upper
      let third = lhs.upper * rhs.lower
      let fourth = lhs.upper * rhs.upper
      var lower = first
      var upper = first
      if second < lower { lower = second }
      if upper < second { upper = second }
      if third < lower { lower = third }
      if upper < third { upper = third }
      if fourth < lower { lower = fourth }
      if upper < fourth { upper = fourth }
      return Interval(lower: lower.nextDown, upper: upper.nextUp)
    }

    static func / (lhs: Interval, rhs: Interval) -> Interval {
      guard rhs.lower > 0.0 || rhs.upper < 0.0 else {
        // Preserve a conservative enclosure; result publication
        // rejects non-finite certified bounds through a typed error.
        return Interval(lower: -.infinity, upper: .infinity)
      }
      return lhs
        * Interval(
          lower: (1.0 / rhs.upper).nextDown,
          upper: (1.0 / rhs.lower).nextUp
        )
    }
  }
}
