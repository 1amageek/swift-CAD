import CADCore

/// Orders genuine outgoing branches by an exactly proved local circle section.
struct OriginalPlanarCurveGermOrderProducer {
  private struct Native {
    let source: BSplineCurve3D
    let owner: Int
    var origin: ExactMonotoneGraphEndpoint
    var target: ExactMonotoneGraphEndpoint
    let direction: Int
    let localUpper: ExactRationalCoefficient
  }
  private struct Prepared {
    let homogeneous: [OriginalSingularFieldPolynomial]
    let point: [OriginalSingularFieldElement]
    let radial: OriginalSingularFieldPolynomial
    let localUpper: ExactRationalCoefficient
    let depth: Int
  }
  private struct CirclePoint {
    let index: Int
    let x: OriginalSingularFieldElement
    let y: OriginalSingularFieldElement
  }

  func produce(
    germs: [OriginalPlanarCurveOutgoingGerm],
    plane: Plane3D,
    partitions: [OriginalPlanarCurveContactPartition],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveGermOrder
  {
    try plane.validate(tolerance: tolerance)
    if germs.isEmpty { return .init(plane: plane, germs: germs, sectors: []) }
    let maximumDepth = min(32, execution.effectiveLimits.maximumValueDepth)
    try RationalAlgebraStorage.retain(germs.count, of: Native.self, usage: &execution)
    var native: [Native] = []
    for germ in germs {
      guard case .bSpline(let source) = germ.span.source, let owner = germ.span.nativeSpanIndex,
        (1...3).contains(source.degree), !source.isPeriodic,
        germ.span.certificationTolerance == tolerance
      else {
        throw GeometryConversionError.invalidInput(
          "Outgoing planar sectors require source-bound native degree-one/two/three spans.")
      }
      var origin = try coordinate(
        germ.atStart ? germ.span.start : germ.span.end,
        tolerance: tolerance,
        using: &execution)
      var target = try coordinate(
        germ.atStart ? germ.span.end : germ.span.start,
        tolerance: tolerance,
        using: &execution)
      let order = try ExactOrderedRealEndpoints.compare(
        &origin, &target, maximumDepth: maximumDepth, usage: &execution)
      guard order != 0 else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      let gap =
        try order < 0
        ? target.lower.subtracting(origin.upper, usage: &execution)
        : origin.lower.subtracting(target.upper, usage: &execution)
      guard gap.isPositive else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      native.append(
        .init(
          source: source, owner: owner, origin: origin, target: target,
          direction: order < 0 ? 1 : -1,
          localUpper: try gap.divided(by: .natural(2, usage: &execution), usage: &execution)))
    }
    try admitPairs(
      native,
      partitions: partitions,
      plane: plane,
      tolerance: tolerance,
      using: &execution)
    var context = try OriginalSingularFieldContext(usage: &execution)
    var transport = OriginalSingularFieldTransport()
    try RationalAlgebraStorage.retain(
      native.count, of: OriginalSingularFieldElement.self, usage: &execution)
    var parameters: [OriginalSingularFieldElement] = []
    for source in native {
      let parameter = try transport.originalScalarValue(
        source.origin, into: context,
        maximumDepth: maximumDepth, usage: &execution)
      parameters.append(parameter)
      context = parameter.context
    }
    let normal = plane.normal
    var axes: (Int, Int)
    var orientation: Double
    if abs(normal.x) >= abs(normal.y), abs(normal.x) >= abs(normal.z) {
      axes = (1, 2)
      orientation = normal.x
    } else if abs(normal.y) >= abs(normal.z) {
      axes = (2, 0)
      orientation = normal.y
    } else {
      axes = (0, 1)
      orientation = normal.z
    }
    if orientation < 0 { axes = (axes.1, axes.0) }
    try RationalAlgebraStorage.retain(native.count, of: Prepared.self, usage: &execution)
    var prepared: [Prepared] = []
    for index in native.indices {
      let parameter = try parameters[index].embedded(
        in: context, maximumDepth: maximumDepth, usage: &execution)
      let original = try OriginalRationalCurvePolynomial(
        source: native[index].source,
        spanIndex: native[index].owner, tolerance: tolerance, usage: &execution)
      guard
        try original.planeIncidenceNumerator(
          origin: plane.origin, normal: plane.normal, usage: &execution
        ).isZero
      else {
        throw GeometryConversionError.invalidInput(
          "Outgoing germ original law is not exactly on its retained plane.")
      }
      let signed = try OriginalSingularFieldElement.constant(
        native[index].direction > 0 ? .one : .one.negated, in: context,
        maximumDepth: maximumDepth, usage: &execution)
      let local = try OriginalSingularFieldPolynomial(
        context: context, coefficients: [parameter, signed],
        maximumDepth: maximumDepth, usage: &execution)
      try RationalAlgebraStorage.retain(
        4, of: OriginalSingularFieldPolynomial.self, usage: &execution)
      var homogeneous: [OriginalSingularFieldPolynomial] = []
      for law in original.homogeneous {
        homogeneous.append(
          try compose(
            law,
            with: local,
            maximumDepth: maximumDepth,
            tolerance: tolerance,
            using: &execution))
      }
      let weight = homogeneous[3]
      guard let w0 = weight.coefficients.first,
        case .positive = try w0.sign(maximumDepth: maximumDepth, usage: &execution)
      else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &execution)
      var point: [OriginalSingularFieldElement] = []
      for axis in 0..<3 {
        let value = try coefficient(
          homogeneous[axis],
          at: 0,
          maximumDepth: maximumDepth,
          tolerance: tolerance,
          using: &execution
        )
        .divided(by: w0, maximumDepth: maximumDepth, usage: &execution)
        if let first = prepared.first {
          guard
            case .zero = try value.subtracting(
              first.point[axis], maximumDepth: maximumDepth,
              usage: &execution
            ).sign(maximumDepth: maximumDepth, usage: &execution)
          else {
            throw GeometryConversionError.invalidInput(
              "Outgoing germs do not meet at the same exact original spatial station.")
          }
        }
        point.append(value)
      }
      let dx = try homogeneous[axes.0].subtracting(
        scale(
          weight,
          by: point[axes.0],
          maximumDepth: maximumDepth,
          tolerance: tolerance,
          using: &execution), maximumDepth: maximumDepth, usage: &execution)
      let dy = try homogeneous[axes.1].subtracting(
        scale(
          weight,
          by: point[axes.1],
          maximumDepth: maximumDepth,
          tolerance: tolerance,
          using: &execution), maximumDepth: maximumDepth, usage: &execution)
      let radial = try dx.multiplied(by: dx, maximumDepth: maximumDepth, usage: &execution)
        .adding(
          dy.multiplied(by: dy, maximumDepth: maximumDepth, usage: &execution),
          maximumDepth: maximumDepth, usage: &execution)
      guard !radial.isZero else {
        throw GeometryConversionError.invalidInput(
          "A constant original curve has no outgoing planar sector.")
      }
      let twiceRadial = try scale(
        radial,
        by: .constant(
          .natural(2, usage: &execution), in: context,
          maximumDepth: maximumDepth, usage: &execution),
        maximumDepth: maximumDepth,
        tolerance: tolerance,
        using: &execution)
      let derivative = try radial.differentiated(maximumDepth: maximumDepth, usage: &execution)
        .multiplied(by: weight, maximumDepth: maximumDepth, usage: &execution)
        .subtracting(
          twiceRadial.multiplied(
            by: weight.differentiated(maximumDepth: maximumDepth, usage: &execution),
            maximumDepth: maximumDepth, usage: &execution), maximumDepth: maximumDepth,
          usage: &execution)
      var leading = 0
      while leading < derivative.coefficients.count {
        if case .zero = try derivative.coefficients[leading].sign(
          maximumDepth: maximumDepth, usage: &execution)
        {
          leading += 1
        } else {
          break
        }
      }
      guard leading < derivative.coefficients.count,
        case .positive = try derivative.coefficients[leading].sign(
          maximumDepth: maximumDepth, usage: &execution)
      else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      try RationalAlgebraStorage.retain(
        derivative.coefficients.count - leading,
        of: OriginalSingularFieldElement.self, usage: &execution)
      let regularDerivative = try OriginalSingularFieldPolynomial(
        context: context,
        coefficients: Array(derivative.coefficients[leading...]), maximumDepth: maximumDepth,
        usage: &execution)
      let sturm = try OriginalSingularFieldSturm(
        regularDerivative, maximumDepth: maximumDepth, usage: &execution)
      var upper = native[index].localUpper
      var depth = max(native[index].origin.depth, context.depth)
      while try sturm.count(
        lower: .zero, upper: upper, excludesLower: false, excludesUpper: false,
        maximumDepth: maximumDepth, usage: &execution) != 0
      {
        guard depth < maximumDepth else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        depth += 1
        try execution.visitCell(axis: .value, depth: depth)
        upper = try upper.divided(by: .natural(2, usage: &execution), usage: &execution)
      }
      prepared.append(
        .init(
          homogeneous: homogeneous, point: point, radial: radial, localUpper: upper, depth: depth))
    }
    var radius = ExactRationalCoefficient.one
    var radiusDepth = 0
    for source in prepared {
      try execution.consumeWork(1)
      radiusDepth = max(radiusDepth, source.depth)
      let upper = try OriginalSingularFieldElement.constant(
        source.localUpper, in: context,
        maximumDepth: maximumDepth, usage: &execution)
      let weight = try source.homogeneous[3].evaluated(
        at: upper, maximumDepth: maximumDepth, usage: &execution)
      let squaredDistance = try source.radial.evaluated(
        at: upper, maximumDepth: maximumDepth, usage: &execution
      )
      .divided(
        by: weight.multiplied(by: weight, maximumDepth: maximumDepth, usage: &execution),
        maximumDepth: maximumDepth, usage: &execution)
      if let exact = try squaredDistance.rationalValue(usage: &execution) {
        guard exact.isPositive else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        let candidate = try exact.divided(by: .natural(2, usage: &execution), usage: &execution)
        if try radius.subtracting(candidate, usage: &execution).isPositive { radius = candidate }
      }
    }
    while true {
      var fits = true
      for source in prepared {
        let upper = try OriginalSingularFieldElement.constant(
          source.localUpper, in: context,
          maximumDepth: maximumDepth, usage: &execution)
        let numerator = try source.radial.evaluated(
          at: upper, maximumDepth: maximumDepth, usage: &execution)
        let weight = try source.homogeneous[3].evaluated(
          at: upper, maximumDepth: maximumDepth, usage: &execution)
        let squaredDistance = try numerator.divided(
          by: weight.multiplied(
            by: weight,
            maximumDepth: maximumDepth, usage: &execution), maximumDepth: maximumDepth,
          usage: &execution)
        let candidate = try OriginalSingularFieldElement.constant(
          radius, in: context,
          maximumDepth: maximumDepth, usage: &execution)
        if case .positive = try squaredDistance.subtracting(
          candidate, maximumDepth: maximumDepth,
          usage: &execution
        ).sign(maximumDepth: maximumDepth, usage: &execution) {
        } else {
          fits = false
          break
        }
      }
      if fits { break }
      guard radiusDepth < maximumDepth else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      radiusDepth += 1
      try execution.visitCell(axis: .value, depth: radiusDepth)
      radius = try radius.divided(by: .natural(2, usage: &execution), usage: &execution)
    }
    let radiusValue = try OriginalSingularFieldElement.constant(
      radius, in: context,
      maximumDepth: maximumDepth, usage: &execution)
    try RationalAlgebraStorage.retain(prepared.count, of: CirclePoint.self, usage: &execution)
    var points: [CirclePoint] = []
    var pointContext = context
    for (index, source) in prepared.enumerated() {
      let weightSquared = try source.homogeneous[3].multiplied(
        by: source.homogeneous[3], maximumDepth: maximumDepth, usage: &execution)
      let circle = try source.radial.subtracting(
        scale(
          weightSquared,
          by: radiusValue,
          maximumDepth: maximumDepth,
          tolerance: tolerance,
          using: &execution), maximumDepth: maximumDepth, usage: &execution)
      let sturm = try OriginalSingularFieldSturm(
        circle, maximumDepth: maximumDepth, usage: &execution)
      guard
        try sturm.count(
          lower: .zero, upper: source.localUpper, excludesLower: true, excludesUpper: true,
          maximumDepth: maximumDepth, usage: &execution) == 1
      else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      let root = OriginalSingularFieldRoot(
        polynomial: circle,
        isolation: .init(
          lower: .zero,
          upper: source.localUpper, excludesLower: true, excludesUpper: true,
          depth: max(source.depth, radiusDepth)))
      let parameter = try root.value(maximumDepth: maximumDepth, usage: &execution)
      let weight = try source.homogeneous[3].evaluated(
        at: parameter, maximumDepth: maximumDepth, usage: &execution)
      let x = try source.homogeneous[axes.0].evaluated(
        at: parameter, maximumDepth: maximumDepth, usage: &execution
      )
      .divided(by: weight, maximumDepth: maximumDepth, usage: &execution)
      .subtracting(source.point[axes.0], maximumDepth: maximumDepth, usage: &execution)
      let y = try source.homogeneous[axes.1].evaluated(
        at: parameter, maximumDepth: maximumDepth, usage: &execution
      )
      .divided(by: weight, maximumDepth: maximumDepth, usage: &execution)
      .subtracting(source.point[axes.1], maximumDepth: maximumDepth, usage: &execution)
      pointContext = try transport.importing(
        parameter.context, into: pointContext,
        maximumDepth: maximumDepth, usage: &execution)
      points.append(.init(index: index, x: x, y: y))
    }
    for index in points.indices {
      points[index] = try .init(
        index: index,
        x: transport.applying(
          to: points[index].x, in: pointContext, maximumDepth: maximumDepth, usage: &execution),
        y: transport.applying(
          to: points[index].y, in: pointContext, maximumDepth: maximumDepth, usage: &execution))
    }
    try RationalAlgebraStorage.retain(points.count, of: CirclePoint.self, usage: &execution)
    var ordered: [CirclePoint] = []
    for point in points {
      var insertion = ordered.count
      for index in ordered.indices {
        if try angularOrder(
          point,
          ordered[index],
          maximumDepth: maximumDepth,
          tolerance: tolerance,
          using: &execution) < 0
        {
          insertion = index
          break
        }
      }
      ordered.insert(point, at: insertion)
    }
    try RationalAlgebraStorage.retain(ordered.count, of: [Int].self, usage: &execution)
    var sectors: [[Int]] = []
    for index in ordered.indices {
      try RationalAlgebraStorage.retain(1, of: Int.self, usage: &execution)
      if index > 0,
        try angularOrder(
          ordered[index - 1],
          ordered[index],
          maximumDepth: maximumDepth,
          tolerance: tolerance,
          using: &execution) == 0
      {
        sectors[sectors.count - 1].append(ordered[index].index)
      } else {
        sectors.append([ordered[index].index])
      }
    }
    return .init(plane: plane, germs: germs, sectors: sectors)
  }

  private func coordinate(
    _ endpoint: OriginalCurveRootEndpoint,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> ExactMonotoneGraphEndpoint {
    switch endpoint {
    case .authored(let value): return try .authored(.originalDouble(value, usage: &execution))
    case .algebraic(let root): return root.retainedRootEndpoint
    }
  }

  private func compose(
    _ law: ExactBivariatePolynomial,
    with parameter: OriginalSingularFieldPolynomial,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalSingularFieldPolynomial {
    guard law.vDegree <= 0 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    let terms = try law.orderedTerms(usage: &execution)
    var result = try OriginalSingularFieldPolynomial(
      context: parameter.context, coefficients: [], maximumDepth: maximumDepth, usage: &execution)
    for power in stride(from: max(0, law.uDegree), through: 0, by: -1) {
      try execution.consumeWork(terms.count)
      let rational = terms.first(where: { $0.0.u == power })?.1 ?? .zero
      let value = try OriginalSingularFieldElement.constant(
        rational, in: parameter.context, maximumDepth: maximumDepth, usage: &execution)
      let constant = try OriginalSingularFieldPolynomial(
        context: parameter.context, coefficients: [value], maximumDepth: maximumDepth,
        usage: &execution)
      result = try result.multiplied(by: parameter, maximumDepth: maximumDepth, usage: &execution)
        .adding(constant, maximumDepth: maximumDepth, usage: &execution)
    }
    return result
  }

  private func coefficient(
    _ law: OriginalSingularFieldPolynomial,
    at index: Int,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalSingularFieldElement {
    if index < law.coefficients.count { return law.coefficients[index] }
    return try .constant(.zero, in: law.context, maximumDepth: maximumDepth, usage: &execution)
  }

  private func scale(
    _ law: OriginalSingularFieldPolynomial,
    by value: OriginalSingularFieldElement,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalSingularFieldPolynomial {
    try RationalAlgebraStorage.retain(
      law.coefficients.count, of: OriginalSingularFieldElement.self, usage: &execution)
    let values = try law.coefficients.map {
      try $0.multiplied(by: value, maximumDepth: maximumDepth, usage: &execution)
    }
    return try .init(
      context: law.context, coefficients: values, maximumDepth: maximumDepth, usage: &execution)
  }

  private func angularOrder(
    _ first: CirclePoint,
    _ second: CirclePoint,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Int {
    func upper(
      _ point: CirclePoint,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      switch try point.y.sign(maximumDepth: maximumDepth, usage: &execution) {
      case .positive: return true
      case .negative: return false
      case .zero:
        if case .positive = try point.x.sign(maximumDepth: maximumDepth, usage: &execution) {
          return true
        }
        return false
      }
    }
    let a = try upper(
      first,
      tolerance: tolerance,
      using: &execution)
    let b = try upper(
      second,
      tolerance: tolerance,
      using: &execution)
    if a != b { return a ? -1 : 1 }
    let cross = try first.x.multiplied(by: second.y, maximumDepth: maximumDepth, usage: &execution)
      .subtracting(
        first.y.multiplied(by: second.x, maximumDepth: maximumDepth, usage: &execution),
        maximumDepth: maximumDepth, usage: &execution)
    switch try cross.sign(maximumDepth: maximumDepth, usage: &execution) {
    case .positive: return -1
    case .negative: return 1
    case .zero: return 0
    }
  }

  private func admitPairs(
    _ native: [Native],
    partitions: [OriginalPlanarCurveContactPartition],
    plane: Plane3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    func same(
      _ first: BSplineCurve3D,
      _ second: BSplineCurve3D,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      try GeometryStructuralComparisonWork.charge(curve: .bSpline(first), using: &execution)
      try GeometryStructuralComparisonWork.charge(curve: .bSpline(second), using: &execution)
      return first == second
    }
    func within(
      _ source: Native,
      trim: ScalarInterval,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      var lower = ExactMonotoneGraphEndpoint.authored(
        try .originalDouble(trim.lower, usage: &execution))
      var upper = ExactMonotoneGraphEndpoint.authored(
        try .originalDouble(trim.upper, usage: &execution))
      var a = source.direction > 0 ? source.origin : source.target
      var b = source.direction > 0 ? source.target : source.origin
      return try ExactOrderedRealEndpoints.compare(
        &lower, &a, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
        usage: &execution) <= 0
        && ExactOrderedRealEndpoints.compare(
          &b, &upper, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
          usage: &execution) <= 0
    }
    func inside(
      _ endpoint: OriginalCurveRootEndpoint,
      source: Native,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      var point = try coordinate(
        endpoint,
        tolerance: tolerance,
        using: &execution)
      var lower = source.direction > 0 ? source.origin : source.target
      var upper = source.direction > 0 ? source.target : source.origin
      return try ExactOrderedRealEndpoints.compare(
        &lower, &point, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
        usage: &execution) < 0
        && ExactOrderedRealEndpoints.compare(
          &point, &upper, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
          usage: &execution) < 0
    }
    for first in native.indices {
      for second in native.indices where first < second {
        let a = native[first]
        let b = native[second]
        var retained: (OriginalPlanarCurveContactPartition, Bool)?
        for partition in partitions {
          try execution.consumeWork(1)
          guard partition.tolerance == tolerance, partition.plane == plane else { continue }
          if try same(
            a.source,
            partition.first,
            tolerance: tolerance,
            using: &execution),
            try same(
              b.source,
              partition.second,
              tolerance: tolerance,
              using: &execution),
            try within(
              a,
              trim: partition.firstParameters,
              tolerance: tolerance,
              using: &execution),
            try within(
              b,
              trim: partition.secondParameters,
              tolerance: tolerance,
              using: &execution)
          {
            retained = (partition, false)
            break
          }
          if try same(
            a.source,
            partition.second,
            tolerance: tolerance,
            using: &execution),
            try same(
              b.source,
              partition.first,
              tolerance: tolerance,
              using: &execution),
            try within(
              a,
              trim: partition.secondParameters,
              tolerance: tolerance,
              using: &execution),
            try within(
              b,
              trim: partition.firstParameters,
              tolerance: tolerance,
              using: &execution)
          {
            retained = (partition, true)
            break
          }
        }
        guard let (partition, reversed) = retained else {
          throw GeometryConversionError.invalidInput(
            "Outgoing sector order needs complete original contact partitions covering every supplied pair."
          )
        }
        for event in partition.events {
          let firstEndpoint = reversed ? event.secondEndpoint : event.firstEndpoint
          let secondEndpoint = reversed ? event.firstEndpoint : event.secondEndpoint
          if try inside(
            firstEndpoint,
            source: a,
            tolerance: tolerance,
            using: &execution),
            try inside(
              secondEndpoint,
              source: b,
              tolerance: tolerance,
              using: &execution)
          {
            throw GeometryConversionError.invalidInput(
              "Outgoing native segments were not split at every original contact/component event.")
          }
        }
      }
    }
  }
}
