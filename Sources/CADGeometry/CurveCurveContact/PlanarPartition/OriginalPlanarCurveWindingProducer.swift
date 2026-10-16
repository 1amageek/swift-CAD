import CADCore

/// Localizes two original sides and counts complete directed global ray crossings.
struct OriginalPlanarCurveWindingProducer {
  private typealias Owner = OriginalPlanarWindingNativeOwner
  private struct Point {
    let x: ExactRationalCoefficient
    let y: ExactRationalCoefficient
  }

  func prepare(
    contours: [[OriginalPlanarDirectedCurve]],
    plane: Plane3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalPlanarCurveWindingSource {
    try plane.validate(tolerance: tolerance)
    guard !contours.isEmpty else {
      throw GeometryConversionError.invalidInput(
        "Original global winding requires closed contours.")
    }
    let owners = try prepare(
      contours,
      plane: plane,
      tolerance: tolerance,
      using: &execution)
    try RationalAlgebraStorage.retain(
      1, of: OriginalPlanarCurveWindingSource.self, usage: &execution)
    return .init(contours: contours, plane: plane, tolerance: tolerance, owners: owners)
  }

  func produce(
    span: OriginalCurveRootSpan3D,
    forward: Bool,
    source retained: OriginalPlanarCurveWindingSource,
    partitions: [OriginalPlanarCurveContactPartition],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalPlanarCurveSideWinding
  {
    let contours = retained.contours
    let plane = retained.plane
    guard retained.tolerance == tolerance else {
      throw GeometryConversionError.invalidInput(
        "Retained winding source has another original tolerance.")
    }
    try plane.validate(tolerance: tolerance)
    guard case .bSpline(let source) = span.source, let ownerIndex = span.nativeSpanIndex,
      span.certificationTolerance == tolerance, !contours.isEmpty,
      (1...3).contains(source.degree), !source.isPeriodic
    else {
      throw GeometryConversionError.invalidInput(
        "Original side winding needs a source-bound native planar span and closed contours.")
    }
    let axes = projectionAxes(plane.normal)
    var a = try endpoint(
      span.start,
      tolerance: tolerance,
      using: &execution)
    var b = try endpoint(
      span.end,
      tolerance: tolerance,
      using: &execution)
    let order = try ExactOrderedRealEndpoints.compare(
      &a, &b, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
    guard order != 0 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    var lower = order < 0 ? a : b
    var upper = order < 0 ? b : a
    let original = try OriginalRationalCurvePolynomial(
      source: source, spanIndex: ownerIndex,
      tolerance: tolerance, usage: &execution)
    guard
      try original.planeIncidenceNumerator(
        origin: plane.origin, normal: plane.normal, usage: &execution
      ).isZero
    else {
      throw GeometryConversionError.invalidInput(
        "Original side winding span is not exactly on its source plane.")
    }
    let owners = retained.owners
    try admit(
      span: span,
      lower: lower,
      upper: upper,
      contours: contours,
      partitions: partitions,
      plane: plane,
      tolerance: tolerance,
      using: &execution)
    var station = try ExactOrderedRealEndpoints.between(
      &lower, &upper,
      maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
    let w = original.homogeneous[3]
    let dxLaw = try derivativeNumerator(
      original.homogeneous[axes.0],
      weight: w,
      tolerance: tolerance,
      using: &execution)
    let dyLaw = try derivativeNumerator(
      original.homogeneous[axes.1],
      weight: w,
      tolerance: tolerance,
      using: &execution)
    guard !dxLaw.isZero || !dyLaw.isZero else {
      throw GeometryConversionError.invalidInput(
        "A spatially constant original owner has no adjacent physical sides.")
    }
    var dx = try dxLaw.evaluated(atU: station, v: .zero, usage: &execution)
    var dy = try dyLaw.evaluated(atU: station, v: .zero, usage: &execution)
    // A nonconstant rational owner has finitely many stationary parameters.
    // Distinct exact rational stations terminate under the caller work bound.
    while dx.isZero && dy.isZero {
      try execution.consumeWork(1)
      lower = .authored(station)
      station = try ExactOrderedRealEndpoints.between(
        &lower, &upper,
        maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
      dx = try dxLaw.evaluated(atU: station, v: .zero, usage: &execution)
      dy = try dyLaw.evaluated(atU: station, v: .zero, usage: &execution)
    }
    if (order > 0) == forward {
      dx = dx.negated
      dy = dy.negated
    }
    let origin = try point(
      original,
      at: station,
      axes: axes,
      tolerance: tolerance,
      using: &execution)
    let normal = Point(x: dy.negated, y: dx)
    let normSquared = try normal.x.multiplied(by: normal.x, usage: &execution)
      .adding(normal.y.multiplied(by: normal.y, usage: &execution), usage: &execution)
    var nearestLower = ExactMonotoneGraphEndpoint.authored(.one.negated)
    var nearestUpper = ExactMonotoneGraphEndpoint.authored(.one)
    for owner in owners {
      let x = try displacement(
        owner.original.homogeneous[axes.0],
        weight: owner.original.homogeneous[3],
        origin: origin.x,
        tolerance: tolerance,
        using: &execution)
      let y = try displacement(
        owner.original.homogeneous[axes.1],
        weight: owner.original.homogeneous[3],
        origin: origin.y,
        tolerance: tolerance,
        using: &execution)
      let transverse = try x.scaled(by: dx, usage: &execution)
        .adding(y.scaled(by: dy, usage: &execution), usage: &execution)
      let along = try x.scaled(by: normal.x, usage: &execution)
        .adding(y.scaled(by: normal.y, usage: &execution), usage: &execution)
      let denominator = try owner.original.homogeneous[3].scaled(by: normSquared, usage: &execution)
      let coordinates: [ExactMonotoneGraphEndpoint]
      if transverse.isZero {
        // A complete collinear owner's extrema, not finite point probes,
        // establish that its full image stays away from the seed origin.
        let critical = try derivativeNumerator(
          along,
          weight: denominator,
          tolerance: tolerance,
          using: &execution)
        try RationalAlgebraStorage.retain(2, of: ExactMonotoneGraphEndpoint.self, usage: &execution)
        var parameters: [ExactMonotoneGraphEndpoint] = [
          .authored(owner.lower), .authored(owner.upper),
        ]
        if !critical.isZero {
          let isolated = try roots(
            critical,
            owner: owner,
            tolerance: tolerance,
            using: &execution)
          try RationalAlgebraStorage.retain(
            isolated.count, of: ExactMonotoneGraphEndpoint.self, usage: &execution)
          parameters.append(contentsOf: isolated)
        }
        try RationalAlgebraStorage.retain(
          parameters.count, of: ExactMonotoneGraphEndpoint.self, usage: &execution)
        var values: [ExactMonotoneGraphEndpoint] = []
        var previousSign: Int?
        for parameter in parameters {
          let coordinate = try OriginalRationalCoordinateRoot.coordinate(
            numerator: along,
            denominator: denominator, at: parameter,
            maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
          let sign = try scalarSign(
            coordinate,
            tolerance: tolerance,
            using: &execution)
          guard sign != 0, previousSign == nil || previousSign == sign else {
            throw GeometryConversionError.invalidInput(
              "The purported event-free source span meets an original transverse collinear owner.")
          }
          previousSign = sign
          values.append(coordinate)
        }
        coordinates = values
      } else {
        let parameters = try roots(
          transverse,
          owner: owner,
          tolerance: tolerance,
          using: &execution)
        try RationalAlgebraStorage.retain(
          parameters.count, of: ExactMonotoneGraphEndpoint.self, usage: &execution)
        coordinates = try parameters.map {
          try OriginalRationalCoordinateRoot.coordinate(
            numerator: along, denominator: denominator,
            at: $0, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
            usage: &execution)
        }
      }
      for coordinate in coordinates {
        var value = coordinate
        switch try scalarSign(
          value,
          tolerance: tolerance,
          using: &execution)
        {
        case 1:
          if try ExactOrderedRealEndpoints.compare(
            &value, &nearestUpper,
            maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
            < 0
          {
            nearestUpper = value
          }
        case -1:
          if try ExactOrderedRealEndpoints.compare(
            &nearestLower, &value,
            maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
            < 0
          {
            nearestLower = value
          }
        default: break  // Exact incidence at the original boundary station.
        }
      }
    }
    var zero = ExactMonotoneGraphEndpoint.authored(.zero)
    let leftStation = try ExactOrderedRealEndpoints.between(
      &zero, &nearestUpper,
      maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
    zero = .authored(.zero)
    let rightStation = try ExactOrderedRealEndpoints.between(
      &nearestLower, &zero,
      maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
    let left = try offset(
      origin,
      along: normal,
      by: leftStation,
      tolerance: tolerance,
      using: &execution)
    let right = try offset(
      origin,
      along: normal,
      by: rightStation,
      tolerance: tolerance,
      using: &execution)
    let leftWinding = try winding(
      at: left,
      owners: owners,
      axes: axes,
      tolerance: tolerance,
      using: &execution)
    let rightWinding = try winding(
      at: right,
      owners: owners,
      axes: axes,
      tolerance: tolerance,
      using: &execution)
    try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveSideWinding.self, usage: &execution)
    return .init(
      span: span, plane: plane, contours: contours, forward: forward, axes: axes,
      left: .init(firstCoordinate: left.x, secondCoordinate: left.y, winding: leftWinding),
      right: .init(firstCoordinate: right.x, secondCoordinate: right.y, winding: rightWinding))
  }

  private func prepare(
    _ contours: [[OriginalPlanarDirectedCurve]],
    plane: Plane3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [Owner] {
    var owners: [Owner] = []
    for contour in contours {
      guard !contour.isEmpty else {
        throw GeometryConversionError.invalidInput("Original winding contours cannot be empty.")
      }
      var first: [ExactRationalCoefficient]?
      var previous: [ExactRationalCoefficient]?
      for directed in contour {
        let curve = directed.curve
        let trim = directed.parameters

        try Curve3D.bSpline(curve).validateOriginalSource(
          tolerance: tolerance,
          remainingSourceDepth: 0,
          maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumValueDepth),
          using: &execution)

        guard (1...3).contains(curve.degree), !curve.isPeriodic, trim.width > 0,
          trim.lower >= curve.knots[curve.degree],
          trim.upper <= curve.knots[curve.controlPointCount]
        else {
          throw GeometryConversionError.invalidInput(
            "Global winding requires contained original native degree-one/two/three trims.")
        }
        var start: [ExactRationalCoefficient]?
        var end: [ExactRationalCoefficient]?
        var precedingOwnerEnd: [ExactRationalCoefficient]?
        for index in curve.degree..<curve.controlPointCount {
          try execution.consumeWork(1)
          let lower = max(trim.lower, curve.knots[index])
          let upper = min(trim.upper, curve.knots[index + 1])
          guard lower < upper else { continue }
          let original = try OriginalRationalCurvePolynomial(
            source: curve, spanIndex: index,
            tolerance: tolerance, usage: &execution)
          guard
            try original.planeIncidenceNumerator(
              origin: plane.origin, normal: plane.normal, usage: &execution
            ).isZero
          else {
            throw GeometryConversionError.invalidInput(
              "Every complete winding owner must lie exactly on its original plane.")
          }
          let a = try ExactRationalCoefficient.originalDouble(lower, usage: &execution)
          let b = try ExactRationalCoefficient.originalDouble(upper, usage: &execution)
          let firstPoint = try spatialPoint(
            original,
            at: a,
            tolerance: tolerance,
            using: &execution)
          let lastPoint = try spatialPoint(
            original,
            at: b,
            tolerance: tolerance,
            using: &execution)
          if let precedingOwnerEnd, precedingOwnerEnd != firstPoint {
            throw GeometryConversionError.invalidInput(
              "An original winding curve has a discontinuous selected-native join.")
          }
          precedingOwnerEnd = lastPoint
          if start == nil { start = firstPoint }
          end = lastPoint
          try RationalAlgebraStorage.retain(1, of: Owner.self, usage: &execution)
          owners.append(
            .init(original: original, lower: a, upper: b, reversed: directed.isReversed))
        }
        guard let start, let end else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        let directedStart = directed.isReversed ? end : start
        let directedEnd = directed.isReversed ? start : end
        if let previous, previous != directedStart {
          throw GeometryConversionError.invalidInput(
            "The original directed winding contour is not exactly connected.")
        }
        if first == nil { first = directedStart }
        previous = directedEnd
      }
      guard first == previous else {
        throw GeometryConversionError.invalidInput(
          "The original directed winding contour is not exactly closed.")
      }
    }
    return owners
  }

  private func winding(
    at seed: Point,
    owners: [Owner],
    axes: (Int, Int),
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Int {
    var slopeIndex = 0
    while true {
      try execution.consumeWork(1)
      let slope = try ExactRationalCoefficient.natural(slopeIndex, usage: &execution)
      try RationalAlgebraStorage.retain(
        owners.count, of: ExactBivariatePolynomial.self, usage: &execution)
      var rays: [ExactBivariatePolynomial] = []
      var admissible = true
      for owner in owners {
        let x = try displacement(
          owner.original.homogeneous[axes.0],
          weight: owner.original.homogeneous[3],
          origin: seed.x,
          tolerance: tolerance,
          using: &execution)
        let y = try displacement(
          owner.original.homogeneous[axes.1],
          weight: owner.original.homogeneous[3],
          origin: seed.y,
          tolerance: tolerance,
          using: &execution)
        let ray = try y.subtracting(x.scaled(by: slope, usage: &execution), usage: &execution)
        if try ray.isZero
          || (try ray.evaluated(atU: owner.lower, v: .zero, usage: &execution).isZero)
          || (try ray.evaluated(atU: owner.upper, v: .zero, usage: &execution).isZero)
        {
          admissible = false
          break
        }
        rays.append(ray)
      }
      if !admissible {
        let next = slopeIndex.addingReportingOverflow(1)
        guard !next.overflow else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        slopeIndex = next.partialValue
        continue
      }
      var count = 0
      for index in owners.indices {
        let owner = owners[index]
        let ray = rays[index]
        let positiveRay = try displacement(
          owner.original.homogeneous[axes.0],
          weight: owner.original.homogeneous[3],
          origin: seed.x,
          tolerance: tolerance,
          using: &execution)
        for root in try roots(
          ray,
          owner: owner,
          tolerance: tolerance,
          using: &execution)
        {
          switch try root.sign(
            of: positiveRay, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
            usage: &execution)
          {
          case .negative: continue
          case .zero:
            throw GeometryConversionError.invalidInput(
              "An exact global winding seed lies on an original contour.")
          case .positive: break
          }
          var derivative = ray
          var multiplicity = 0
          var crossing = 0
          while multiplicity <= ray.uDegree {
            derivative = try derivative.differentiated(alongU: true, usage: &execution)
            multiplicity += 1
            switch try root.sign(
              of: derivative, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
              usage: &execution)
            {
            case .zero: continue
            case .positive: crossing = 1
            case .negative: crossing = -1
            }
            break
          }
          guard crossing != 0 else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original curve contact exhausted its local source or proof ceiling.")
          }
          if multiplicity & 1 == 0 { continue }
          let increment = owner.reversed ? -crossing : crossing
          let next = count.addingReportingOverflow(increment)
          guard !next.overflow else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original curve contact exhausted its local source or proof ceiling.")
          }
          count = next.partialValue
        }
      }
      return count
    }
  }

  private func admit(
    span: OriginalCurveRootSpan3D,
    lower: ExactMonotoneGraphEndpoint,
    upper: ExactMonotoneGraphEndpoint,
    contours: [[OriginalPlanarDirectedCurve]],
    partitions: [OriginalPlanarCurveContactPartition],
    plane: Plane3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    guard case .bSpline(let source) = span.source else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    for contour in contours {
      for directed in contour {
        var selected: (OriginalPlanarCurveContactPartition, Bool)?
        for partition in partitions {
          try execution.consumeWork(1)
          guard partition.plane == plane, partition.tolerance == tolerance else { continue }
          try GeometryStructuralComparisonWork.charge(curve: .bSpline(source), using: &execution)
          try GeometryStructuralComparisonWork.charge(
            curve: .bSpline(directed.curve), using: &execution)
          try GeometryStructuralComparisonWork.charge(
            curve: .bSpline(partition.first), using: &execution)
          try GeometryStructuralComparisonWork.charge(
            curve: .bSpline(partition.second), using: &execution)
          let reversed: Bool
          let trim: ScalarInterval
          if source == partition.first, directed.curve == partition.second,
            directed.parameters == partition.secondParameters
          {
            reversed = false
            trim = partition.firstParameters
          } else if source == partition.second, directed.curve == partition.first,
            directed.parameters == partition.firstParameters
          {
            reversed = true
            trim = partition.secondParameters
          } else {
            continue
          }
          var a = ExactMonotoneGraphEndpoint.authored(
            try .originalDouble(trim.lower, usage: &execution))
          var b = ExactMonotoneGraphEndpoint.authored(
            try .originalDouble(trim.upper, usage: &execution))
          var l = lower
          var u = upper
          if try ExactOrderedRealEndpoints.compare(
            &a, &l, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
            usage: &execution) <= 0,
            try ExactOrderedRealEndpoints.compare(
              &u, &b, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
              usage: &execution) <= 0
          {
            selected = (partition, reversed)
            break
          }
        }
        guard let (partition, reversed) = selected else {
          throw GeometryConversionError.invalidInput(
            "Side localization requires complete original pair receipts against every directed contour source."
          )
        }
        for event in partition.events {
          var point = try endpoint(
            reversed ? event.secondEndpoint : event.firstEndpoint,
            tolerance: tolerance,
            using: &execution)
          var l = lower
          var u = upper
          if try ExactOrderedRealEndpoints.compare(
            &l, &point, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
            usage: &execution) < 0,
            try ExactOrderedRealEndpoints.compare(
              &point, &u, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
              usage: &execution) < 0
          {
            throw GeometryConversionError.invalidInput(
              "Side winding span retains an unsplit original contact or component event.")
          }
        }
      }
    }
  }

  private func roots(
    _ polynomial: ExactBivariatePolynomial,
    owner: Owner,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ExactMonotoneGraphEndpoint] {
    let isolated = try ExactUnivariateRootIsolator().isolate(
      polynomial, lower: owner.lower,
      upper: owner.upper, maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth),
      usage: &execution)
    try RationalAlgebraStorage.retain(
      isolated.count, of: ExactMonotoneGraphEndpoint.self, usage: &execution)
    return try isolated.map {
      if $0.isRationalStation { return .authored($0.lower) }
      return .algebraic(
        try ExactAlgebraicRealRoot(polynomial: polynomial, isolation: $0, usage: &execution))
    }
  }
  private func endpoint(
    _ endpoint: OriginalCurveRootEndpoint,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> ExactMonotoneGraphEndpoint {
    switch endpoint {
    case .authored(let value): return try .authored(.originalDouble(value, usage: &execution))
    case .algebraic(let root): return root.retainedRootEndpoint
    }
  }
  private func scalarSign(
    _ value: ExactMonotoneGraphEndpoint,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Int {
    switch try value.sign(
      of: .coordinate(alongU: true, usage: &execution),
      maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
    {
    case .positive: 1
    case .negative: -1
    case .zero: 0
    }
  }
  private func derivativeNumerator(
    _ numerator: ExactBivariatePolynomial,
    weight: ExactBivariatePolynomial,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> ExactBivariatePolynomial {
    try numerator.differentiated(alongU: true, usage: &execution).multiplied(
      by: weight, usage: &execution
    )
    .subtracting(
      numerator.multiplied(
        by: weight.differentiated(alongU: true, usage: &execution), usage: &execution),
      usage: &execution)
  }
  private func displacement(
    _ numerator: ExactBivariatePolynomial,
    weight: ExactBivariatePolynomial,
    origin: ExactRationalCoefficient,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> ExactBivariatePolynomial {
    try numerator.subtracting(weight.scaled(by: origin, usage: &execution), usage: &execution)
  }
  private func spatialPoint(
    _ original: OriginalRationalCurvePolynomial,
    at station: ExactRationalCoefficient,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ExactRationalCoefficient] {
    let weight = try original.homogeneous[3].evaluated(atU: station, v: .zero, usage: &execution)
    guard weight.isPositive else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    try RationalAlgebraStorage.retain(3, of: ExactRationalCoefficient.self, usage: &execution)
    return try original.homogeneous.prefix(3).map {
      try $0.evaluated(atU: station, v: .zero, usage: &execution).divided(
        by: weight, usage: &execution)
    }
  }
  private func point(
    _ original: OriginalRationalCurvePolynomial,
    at station: ExactRationalCoefficient,
    axes: (Int, Int),
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Point {
    let value = try spatialPoint(
      original,
      at: station,
      tolerance: tolerance,
      using: &execution)
    return .init(x: value[axes.0], y: value[axes.1])
  }
  private func offset(
    _ source: Point,
    along direction: Point,
    by amount: ExactRationalCoefficient,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Point {
    try .init(
      x: source.x.adding(direction.x.multiplied(by: amount, usage: &execution), usage: &execution),
      y: source.y.adding(direction.y.multiplied(by: amount, usage: &execution), usage: &execution))
  }
  private func projectionAxes(_ normal: Vector3D) -> (Int, Int) {
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
    return orientation < 0 ? (axes.1, axes.0) : axes
  }
}
