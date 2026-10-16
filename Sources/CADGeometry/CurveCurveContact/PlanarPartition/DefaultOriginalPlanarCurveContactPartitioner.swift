import CADCore

/// Complete exact original native planar contacts using the shared source algebra.
public struct DefaultOriginalPlanarCurveContactPartitioner: OriginalPlanarCurveContactPartitioning {
  public init() {}

  public func sideWinding(
    of span: OriginalCurveRootSpan3D,
    forward: Bool,
    contours: [[OriginalPlanarDirectedCurve]],
    on plane: Plane3D,
    retaining partitions: [OriginalPlanarCurveContactPartition],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveSideWinding
  {
    execution.context = .init(
      operation: .curveCurveContact, entry: .admitted, stage: .request,
      first: .init(role: .curve, request: .wholeSourceSupport))
    do {
      try execution.checkpoint()
      execution.context = execution.context.at(stage: .source)
      let result = try resolveSideWinding(
        of: span, forward: forward, contours: contours, on: plane, retaining: partitions,
        tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolveSideWinding(
    of span: OriginalCurveRootSpan3D,
    forward: Bool,
    contours: [[OriginalPlanarDirectedCurve]],
    on plane: Plane3D,
    retaining partitions: [OriginalPlanarCurveContactPartition],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveSideWinding
  {
    return try execution.withProofScope(
      maximum: try ExactScalarDepth(
        value: min(32, execution.effectiveLimits.maximumValueDepth), coefficient: Int.max)
    ) { execution in
      let source = try prepareWinding(
        contours: contours,
        on: plane,
        tolerance: tolerance,
        using: &execution)
      return try sideWinding(
        of: span,
        forward: forward,
        retainingSource: source,
        retaining: partitions,
        tolerance: tolerance,
        using: &execution)

    }
  }

  public func prepareWinding(
    contours: [[OriginalPlanarDirectedCurve]],
    on plane: Plane3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveWindingSource
  {
    execution.context = .init(
      operation: .curveCurveContact, entry: .admitted, stage: .request,
      first: .init(role: .curve, request: .wholeSourceSupport))
    do {
      try execution.checkpoint()
      execution.context = execution.context.at(stage: .source)
      let result = try resolvePrepareWinding(
        contours: contours, on: plane, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolvePrepareWinding(
    contours: [[OriginalPlanarDirectedCurve]],
    on plane: Plane3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveWindingSource
  {
    return try execution.withProofScope(
      maximum: try ExactScalarDepth(
        value: min(32, execution.effectiveLimits.maximumValueDepth), coefficient: Int.max)
    ) { execution in
      return try OriginalPlanarCurveWindingProducer().prepare(
        contours: contours,
        plane: plane,
        tolerance: tolerance,
        using: &execution)

    }
  }

  public func sideWinding(
    of span: OriginalCurveRootSpan3D,
    forward: Bool,
    retainingSource: OriginalPlanarCurveWindingSource,
    retaining partitions: [OriginalPlanarCurveContactPartition],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveSideWinding
  {
    execution.context = .init(
      operation: .curveCurveContact, entry: .admitted, stage: .request,
      first: .init(role: .curve, request: .wholeSourceSupport))
    do {
      try execution.checkpoint()
      execution.context = execution.context.at(stage: .source)
      let result = try resolveSideWinding(
        of: span, forward: forward, retainingSource: retainingSource, retaining: partitions,
        tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolveSideWinding(
    of span: OriginalCurveRootSpan3D,
    forward: Bool,
    retainingSource: OriginalPlanarCurveWindingSource,
    retaining partitions: [OriginalPlanarCurveContactPartition],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveSideWinding
  {
    return try execution.withProofScope(
      maximum: try ExactScalarDepth(
        value: min(32, execution.effectiveLimits.maximumValueDepth), coefficient: Int.max)
    ) { execution in
      return try OriginalPlanarCurveWindingProducer().produce(
        span: span,
        forward: forward,
        source: retainingSource,
        partitions: partitions,
        tolerance: tolerance,
        using: &execution)

    }
  }

  private struct Owner {
    let index: Int
    let parameters: ScalarInterval
    let homogeneous: [ExactBivariatePolynomial]
  }

  public func monotoneOverlaps(
    retaining partition: OriginalPlanarCurveContactPartition,
    firstMerged: OriginalPlanarCurveMergedPartition,
    secondMerged: OriginalPlanarCurveMergedPartition,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> [OriginalPlanarCurveMonotoneOverlap]
  {
    execution.context = .init(
      operation: .curveCurveContact, entry: .admitted, stage: .request,
      first: .init(role: .curve, request: .curveRange(partition.firstParameters)),
      second: .init(role: .curve, request: .curveRange(partition.secondParameters)))
    do {
      try execution.checkpoint()
      execution.context = execution.context.at(stage: .source)
      let result = try resolveMonotoneOverlaps(
        retaining: partition, firstMerged: firstMerged, secondMerged: secondMerged,
        tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolveMonotoneOverlaps(
    retaining partition: OriginalPlanarCurveContactPartition,
    firstMerged: OriginalPlanarCurveMergedPartition,
    secondMerged: OriginalPlanarCurveMergedPartition,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> [OriginalPlanarCurveMonotoneOverlap]
  {
    return try execution.withProofScope(
      maximum: try ExactScalarDepth(
        value: min(32, execution.effectiveLimits.maximumValueDepth), coefficient: Int.max)
    ) { execution in
      return try OriginalPlanarCurveOverlapProducer().produce(
        partition: partition,
        first: firstMerged,
        second: secondMerged,
        tolerance: tolerance,
        using: &execution)

    }
  }

  public func orderOutgoingGerms(
    _ germs: [OriginalPlanarCurveOutgoingGerm],
    on plane: Plane3D,
    retaining partitions: [OriginalPlanarCurveContactPartition],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveGermOrder
  {
    execution.context = .init(
      operation: .curveCurveContact, entry: .admitted, stage: .request,
      first: .init(role: .curve, request: .wholeSourceSupport))
    do {
      try execution.checkpoint()
      execution.context = execution.context.at(stage: .source)
      let result = try resolveOrderOutgoingGerms(
        germs, on: plane, retaining: partitions, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolveOrderOutgoingGerms(
    _ germs: [OriginalPlanarCurveOutgoingGerm],
    on plane: Plane3D,
    retaining partitions: [OriginalPlanarCurveContactPartition],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveGermOrder
  {
    return try execution.withProofScope(
      maximum: try ExactScalarDepth(
        value: min(32, execution.effectiveLimits.maximumValueDepth), coefficient: Int.max)
    ) { execution in
      return try OriginalPlanarCurveGermOrderProducer().produce(
        germs: germs,
        plane: plane,
        partitions: partitions,
        tolerance: tolerance,
        using: &execution)

    }
  }

  public func mergeCuts(
    source: BSplineCurve3D,
    parameters: ScalarInterval,
    endpoints: [OriginalCurveRootEndpoint],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalPlanarCurveMergedPartition {
    execution.context = .init(
      operation: .curveCurveContact, entry: .admitted, stage: .request,
      first: .init(role: .curve, request: .curveRange(parameters)))
    do {
      try execution.checkpoint()
      execution.context = execution.context.at(stage: .source)
      let result = try resolveMergeCuts(
        source: source, parameters: parameters, endpoints: endpoints, tolerance: tolerance,
        using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolveMergeCuts(
    source: BSplineCurve3D,
    parameters: ScalarInterval,
    endpoints: [OriginalCurveRootEndpoint],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalPlanarCurveMergedPartition {
    return try execution.withProofScope(
      maximum: try ExactScalarDepth(
        value: min(32, execution.effectiveLimits.maximumValueDepth), coefficient: Int.max)
    ) { execution in
      try tolerance.validate()

      try Curve3D.bSpline(source).validateOriginalSource(
        tolerance: tolerance,
        remainingSourceDepth: 0,
        maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
        using: &execution)

      guard (1...3).contains(source.degree), !source.isPeriodic,
        parameters.width > 0, parameters.lower >= source.knots[source.degree],
        parameters.upper <= source.knots[source.controlPointCount]
      else {
        throw GeometryConversionError.invalidInput(
          "Merged exact native planar cuts need degree-one/two/three contained positive trims.")
      }
      for endpoint in endpoints {
        try execution.consumeWork(1)
        switch endpoint {
        case .authored(let value):
          guard value.isFinite, value >= parameters.lower, value <= parameters.upper else {
            throw GeometryConversionError.invalidInput(
              "Authored merged endpoint lies outside its original trim.")
          }
        case .algebraic(let root):
          try GeometryStructuralComparisonWork.charge(curve: .bSpline(source), using: &execution)
          try GeometryStructuralComparisonWork.charge(
            curve: .bSpline(root.source), using: &execution)
          guard root.source == source, root.certificationTolerance == tolerance,
            root.spanIndex >= source.degree, root.spanIndex < source.controlPointCount,
            source.knots[root.spanIndex] < parameters.upper,
            source.knots[root.spanIndex + 1] > parameters.lower
          else {
            throw GeometryConversionError.invalidInput(
              "Algebraic merged endpoint lacks the original source/trim owner.")
          }
        }
      }
      let partition = try OriginalPlanarCurveCutProducer().produce(
        source: source,
        parameters: parameters,
        events: [],
        firstSource: true,
        mergeEndpoints: endpoints,
        tolerance: tolerance,
        using: &execution)
      try RationalAlgebraStorage.retain(
        partition.cuts.count, of: OriginalPlanarCurveMergedCut.self, usage: &execution)
      return .init(
        source: source, parameters: parameters, tolerance: tolerance,
        cuts: partition.cuts.map(OriginalPlanarCurveMergedCut.init), segments: partition.segments)

    }
  }

  public func partition(
    first: BSplineCurve3D,
    firstParameters: ScalarInterval,
    second: BSplineCurve3D,
    secondParameters: ScalarInterval,
    on plane: Plane3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveContactPartition
  {
    execution.context = .init(
      operation: .curveCurveContact, entry: .admitted, stage: .request,
      first: .init(role: .curve, request: .curveRange(firstParameters)),
      second: .init(role: .curve, request: .curveRange(secondParameters)))
    do {
      try execution.checkpoint()
      execution.context = execution.context.at(stage: .source)
      let result = try resolvePartition(
        first: first, firstParameters: firstParameters, second: second,
        secondParameters: secondParameters, on: plane, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolvePartition(
    first: BSplineCurve3D,
    firstParameters: ScalarInterval,
    second: BSplineCurve3D,
    secondParameters: ScalarInterval,
    on plane: Plane3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveContactPartition
  {
    try tolerance.validate()
    try plane.validate(tolerance: tolerance)
    func validate(
      _ source: BSplineCurve3D,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws {

      try Curve3D.bSpline(source).validateOriginalSource(
        tolerance: tolerance,
        remainingSourceDepth: 0,
        maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
        using: &execution)

    }
    try validate(
      first,
      tolerance: tolerance,
      using: &execution)
    try validate(
      second,
      tolerance: tolerance,
      using: &execution)
    guard
      (1...3).contains(first.degree), (1...3).contains(second.degree),
      !first.isPeriodic, !second.isPeriodic, firstParameters.width > 0, secondParameters.width > 0,
      firstParameters.lower >= first.knots[first.degree],
      firstParameters.upper <= first.knots[first.controlPointCount],
      secondParameters.lower >= second.knots[second.degree],
      secondParameters.upper <= second.knots[second.controlPointCount],
      try first.domain.containsSpan(
        from: firstParameters.lower, to: firstParameters.upper, tolerance: tolerance),
      try second.domain.containsSpan(
        from: secondParameters.lower, to: secondParameters.upper, tolerance: tolerance)
    else {
      throw GeometryConversionError.invalidInput(
        "Exact planar partition requires original nonperiodic degree-one/two/three contained positive trims and one tolerance."
      )
    }
    let normal = plane.normal
    let axes: (Int, Int)
    if abs(normal.x) >= abs(normal.y), abs(normal.x) >= abs(normal.z) {
      axes = (1, 2)
    } else if abs(normal.y) >= abs(normal.z) {
      axes = (0, 2)
    } else {
      axes = (0, 1)
    }
    func owners(
      _ source: BSplineCurve3D,
      over range: ScalarInterval,
      alongU: Bool,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> [Owner] {
      var result: [Owner] = []
      for index in source.degree..<source.controlPointCount {
        try execution.consumeWork(1)
        guard source.knots[index] < source.knots[index + 1] else { continue }
        let lower = max(range.lower, source.knots[index])
        let upper = min(range.upper, source.knots[index + 1])
        guard lower < upper else { continue }
        let original = try OriginalRationalCurvePolynomial(
          source: source, spanIndex: index,
          tolerance: tolerance, usage: &execution)
        let values: [ExactBivariatePolynomial]
        if alongU {
          values = original.homogeneous
        } else {
          try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &execution)
          values = try original.homogeneous.map { try $0.exchangedAxes(usage: &execution) }
        }
        try RationalAlgebraStorage.retain(3, of: (Double, Double).self, usage: &execution)
        var planeResidual = ExactBivariatePolynomial.zero
        for (axis, originalValues) in [
          (normal.x, plane.origin.x), (normal.y, plane.origin.y),
          (normal.z, plane.origin.z),
        ].enumerated() {
          let residual = try values[axis].subtracting(
            values[3].scaled(
              by: .originalDouble(originalValues.1, usage: &execution), usage: &execution),
            usage: &execution)
          planeResidual = try planeResidual.adding(
            residual.scaled(
              by: .originalDouble(originalValues.0, usage: &execution), usage: &execution),
            usage: &execution)
        }
        guard planeResidual.isZero else {
          throw GeometryConversionError.invalidInput(
            "Original planar contact partition cannot project a nonplanar native law into its supplied plane."
          )
        }
        try RationalAlgebraStorage.retain(1, of: Owner.self, usage: &execution)
        result.append(
          Owner(
            index: index, parameters: try .init(lower: lower, upper: upper), homogeneous: values))
      }
      guard !result.isEmpty else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      return result
    }
    let a = try owners(
      first,
      over: firstParameters,
      alongU: true,
      tolerance: tolerance,
      using: &execution)
    let b = try owners(
      second,
      over: secondParameters,
      alongU: false,
      tolerance: tolerance,
      using: &execution)
    var events: [OriginalPlanarCurveContactEvent] = []
    var overlaps: [OriginalPlanarCurveContactOverlap] = []
    for firstOwner in a {
      for secondOwner in b {
        try execution.consumeCells()
        let domain = SurfaceParameterBox(u: firstOwner.parameters, v: secondOwner.parameters)
        try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &execution)
        var equations: [ExactBivariatePolynomial] = []
        equations.reserveCapacity(3)
        for axis in 0..<3 {
          equations.append(
            try firstOwner.homogeneous[axis].multiplied(
              by: secondOwner.homogeneous[3],
              usage: &execution
            ).subtracting(
              secondOwner.homogeneous[axis].multiplied(
                by: firstOwner.homogeneous[3], usage: &execution), usage: &execution))
        }
        let x = equations[axes.0]
        let y = equations[axes.1]
        let common = try ExactBivariateGCD().greatestCommonDivisor(x, y, usage: &execution)
        let depth = min(32, execution.effectiveLimits.maximumValueDepth)
        func endpoint(
          _ coordinate: ExactMonotoneGraphEndpoint,
          source: BSplineCurve3D,
          index: Int,
          tolerance: ModelingTolerance,
          using execution: inout OriginalQueryExecution
        ) throws -> OriginalCurveRootEndpoint {
          let root: ExactAlgebraicRealRoot
          switch coordinate {
          case .algebraic(let retained): root = retained
          case .authored(let value):
            let enclosure = try value.outwardInterval(usage: &execution)
            if enclosure.lower == enclosure.upper { return .authored(enclosure.lower) }
            let polynomial = try ExactBivariatePolynomial.coordinate(
              alongU: true, usage: &execution
            )
            .subtracting(.constant(value, usage: &execution), usage: &execution)
            root = try .init(
              polynomial: polynomial,
              isolation: .init(
                lower: value, upper: value, isRationalStation: true,
                isolationDepth: coordinate.depth, excludesLowerEndpoint: false,
                excludesUpperEndpoint: false),
              usage: &execution)
          }
          return try .algebraic(
            OriginalCurveRootBoundary.retaining(
              source: source, spanIndex: index,
              coordinate: root,
              maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
              tolerance: tolerance, usage: &execution,
              maximumAlgebraicDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth)))
        }
        func event(
          _ root: ExactBivariateSystemRoot,
          overlap: Bool,
          exchanged: Bool = false,
          tolerance: ModelingTolerance,
          using execution: inout OriginalQueryExecution
        ) throws -> OriginalPlanarCurveContactEvent {
          for equation in equations {
            let originalEquation =
              try exchanged ? equation.exchangedAxes(usage: &execution) : equation
            guard
              case .zero = try root.sign(
                of: originalEquation, maximumDepth: depth, usage: &execution)
            else {
              throw GeometryConversionError.invalidInput(
                "Original planar contact is not an exact zero of all original XYZ equations.")
            }
          }
          let firstCoordinate = try root.originalCoordinate(
            alongU: !exchanged, maximumDepth: depth, usage: &execution)
          let secondCoordinate = try root.originalCoordinate(
            alongU: exchanged, maximumDepth: depth, usage: &execution)
          try RationalAlgebraStorage.retain(
            1, of: OriginalPlanarCurveContactEvent.self, usage: &execution)
          return try .init(
            firstEndpoint: endpoint(
              firstCoordinate,
              source: first,
              index: firstOwner.index,
              tolerance: tolerance,
              using: &execution),
            secondEndpoint: endpoint(
              secondCoordinate,
              source: second,
              index: secondOwner.index,
              tolerance: tolerance,
              using: &execution),
            firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
            belongsToCommonFactor: overlap, originalPair: root, originalPairAxesExchanged: exchanged
          )
        }
        func span(
          _ source: BSplineCurve3D,
          owner: Owner,
          tolerance: ModelingTolerance,
          using execution: inout OriginalQueryExecution
        ) throws -> OriginalCurveRootSpan3D {
          let maximumSpans = max(1, execution.availableWork)
          return try .init(
            source: .bSpline(source), start: .authored(owner.parameters.lower),
            end: .authored(owner.parameters.upper), nativeSpanIndex: owner.index,
            maximumParameterWidth: tolerance.relative, maximumSubdivisionDepth: depth,
            tolerance: tolerance, usage: &execution,
            maximumSpanCount: maximumSpans, remainingSourceDepth: 0)
        }
        var componentEvents: [OriginalPlanarCurveContactEvent] = []
        var projection: OriginalRationalPlaneCurveProjection?
        var atlas: OriginalRationalPlaneCurveAtlas?
        var oppositeProjection: OriginalRationalPlaneCurveProjection?
        var hasContinuousComponent = common.isZero
        if common.isZero {
          guard equations.allSatisfy({ $0.isZero }) else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original curve contact exhausted its local source or proof ceiling.")
          }
          for u in [domain.u.lower, domain.u.upper] {
            for v in [domain.v.lower, domain.v.upper] {
              try RationalAlgebraStorage.retain(
                1, of: OriginalPlanarCurveContactEvent.self, usage: &execution)
              componentEvents.append(
                .init(
                  firstEndpoint: .authored(u), secondEndpoint: .authored(v),
                  firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
                  belongsToCommonFactor: true, originalPair: nil))
            }
          }
        } else if common.uDegree > 0 || common.vDegree > 0 {
          for equation in equations {
            _ = try equation.dividedExactly(by: common, usage: &execution)
          }
          let zeroLaw = try OriginalRationalZeroSetAuthority(original: common, usage: &execution)
          let originalProjection = try OriginalRationalPlaneCurveProjection(
            original: zeroLaw,
            over: domain, maximumDepth: depth, usage: &execution)
          projection = originalProjection
          if let finite = try originalProjection.finiteOriginalRoots(usage: &execution) {
            for root in finite {
              events.append(
                try event(
                  root,
                  overlap: false,
                  tolerance: tolerance,
                  using: &execution))
            }
          } else {
            hasContinuousComponent = true
          }
          for station in originalProjection.stations {
            for root in station.roots where hasContinuousComponent {
              componentEvents.append(
                try event(
                  root,
                  overlap: true,
                  tolerance: tolerance,
                  using: &execution))
            }
          }
          for coordinate in originalProjection.verticalComponents {
            for v in [domain.v.lower, domain.v.upper] {
              for equation in equations {
                let transverse = try equation.restricted(
                  alongU: false,
                  station: .originalDouble(v, usage: &execution), usage: &execution)
                guard
                  case .zero = try coordinate.sign(
                    of: transverse, maximumDepth: depth,
                    usage: &execution)
                else {
                  throw GeometryConversionError.resourceLimitExceeded(
                    "Original curve contact exhausted its local source or proof ceiling.")
                }
              }
              try RationalAlgebraStorage.retain(
                1, of: OriginalPlanarCurveContactEvent.self, usage: &execution)
              componentEvents.append(
                try .init(
                  firstEndpoint: endpoint(
                    coordinate,
                    source: first,
                    index: firstOwner.index,
                    tolerance: tolerance,
                    using: &execution), secondEndpoint: .authored(v),
                  firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
                  belongsToCommonFactor: true, originalPair: nil))
            }
          }
          for v in originalProjection.horizontalComponents {
            for u in [domain.u.lower, domain.u.upper] {
              try RationalAlgebraStorage.retain(
                1, of: OriginalPlanarCurveContactEvent.self, usage: &execution)
              componentEvents.append(
                try .init(
                  firstEndpoint: .authored(u),
                  secondEndpoint: endpoint(
                    .authored(v),
                    source: second,
                    index: secondOwner.index,
                    tolerance: tolerance,
                    using: &execution),
                  firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
                  belongsToCommonFactor: true, originalPair: nil))
            }
          }
          if hasContinuousComponent {
            let oppositeLaw = try OriginalRationalZeroSetAuthority(
              original: common.exchangedAxes(usage: &execution),
              usage: &execution)
            let opposite = try OriginalRationalPlaneCurveProjection(
              original: oppositeLaw,
              over: .init(u: domain.v, v: domain.u), maximumDepth: depth, usage: &execution)
            oppositeProjection = opposite
            for station in opposite.stations {
              for root in station.roots {
                componentEvents.append(
                  try event(
                    root,
                    overlap: true,
                    exchanged: true,
                    tolerance: tolerance,
                    using: &execution))
              }
            }
            for coordinate in opposite.verticalComponents {
              for u in [domain.u.lower, domain.u.upper] {
                for equation in equations {
                  let transverse = try equation.restricted(
                    alongU: true,
                    station: .originalDouble(u, usage: &execution), usage: &execution)
                  guard
                    case .zero = try coordinate.sign(
                      of: transverse, maximumDepth: depth,
                      usage: &execution)
                  else {
                    throw GeometryConversionError.resourceLimitExceeded(
                      "Original curve contact exhausted its local source or proof ceiling.")
                  }
                }
                try RationalAlgebraStorage.retain(
                  1, of: OriginalPlanarCurveContactEvent.self, usage: &execution)
                componentEvents.append(
                  try .init(
                    firstEndpoint: .authored(u),
                    secondEndpoint: endpoint(
                      coordinate,
                      source: second,
                      index: secondOwner.index,
                      tolerance: tolerance,
                      using: &execution),
                    firstNativeSpanIndex: firstOwner.index,
                    secondNativeSpanIndex: secondOwner.index,
                    belongsToCommonFactor: true, originalPair: nil))
              }
            }
            for u in opposite.horizontalComponents {
              for v in [domain.v.lower, domain.v.upper] {
                try RationalAlgebraStorage.retain(
                  1, of: OriginalPlanarCurveContactEvent.self, usage: &execution)
                componentEvents.append(
                  try .init(
                    firstEndpoint: endpoint(
                      .authored(u),
                      source: first,
                      index: firstOwner.index,
                      tolerance: tolerance,
                      using: &execution), secondEndpoint: .authored(v),
                    firstNativeSpanIndex: firstOwner.index,
                    secondNativeSpanIndex: secondOwner.index,
                    belongsToCommonFactor: true, originalPair: nil))
              }
            }
          }
          if originalProjection.sectors.contains(where: { !$0.fiberRoots.isEmpty }) {
            atlas = try OriginalRationalPlaneCurveAtlas(
              retaining: originalProjection,
              maximumDepth: depth, usage: &execution)
          }
        }
        if hasContinuousComponent {
          try RationalAlgebraStorage.retain(
            1, of: OriginalPlanarCurveContactOverlap.self, usage: &execution)
          overlaps.append(
            try .init(
              firstSpan: span(
                first,
                owner: firstOwner,
                tolerance: tolerance,
                using: &execution),
              secondSpan: span(
                second,
                owner: secondOwner,
                tolerance: tolerance,
                using: &execution), factor: common,
              coversAllParameterPairs: common.isZero, events: componentEvents,
              projection: projection, atlas: atlas, oppositeAxisProjection: oppositeProjection))
          try RationalAlgebraStorage.retain(
            componentEvents.count,
            of: OriginalPlanarCurveContactEvent.self, usage: &execution)
          events.append(contentsOf: componentEvents)
        }
        if common.isZero { continue }
        let firstQuotient = try x.dividedExactly(by: common, usage: &execution)
        let secondQuotient = try y.dividedExactly(by: common, usage: &execution)
        try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &execution)
        let remaining: [ExactBivariateSystemRoot]
        do {
          remaining = try ExactBivariateSystemSolver.isolatedRoots(
            of: [firstQuotient, secondQuotient],
            over: domain, maximumDepth: depth, usage: &execution)
        } catch let classification as ExactBivariateSystemClassification {
          switch classification {
          // FIXME(INCOMPLETE_IMPLEMENTATION): A residual nonfinite ideal
          // cannot publish a complete drawing/repair partition. The full
          // component decomposition must be retained before this source
          // branch may succeed; no partial event list is returned.
          case .positiveDimensionalOriginalIdeal:
            throw GeometryConversionError.resourceLimitExceeded(
              "Original curve contact exhausted its local source or proof ceiling.")
          }
        }
        for root in remaining {
          events.append(
            try event(
              root,
              overlap: false,
              tolerance: tolerance,
              using: &execution))
        }
      }
    }
    let firstPartition = try OriginalPlanarCurveCutProducer().produce(
      source: first,
      parameters: firstParameters,
      events: events,
      firstSource: true,
      tolerance: tolerance,
      using: &execution)
    let secondPartition = try OriginalPlanarCurveCutProducer().produce(
      source: second,
      parameters: secondParameters,
      events: events,
      firstSource: false,
      tolerance: tolerance,
      using: &execution)
    return .init(
      first: first, firstParameters: firstParameters, second: second,
      secondParameters: secondParameters, plane: plane, tolerance: tolerance,
      events: events, overlaps: overlaps, firstCuts: firstPartition.cuts,
      secondCuts: secondPartition.cuts,
      firstSegments: firstPartition.segments, secondSegments: secondPartition.segments)
  }
}
