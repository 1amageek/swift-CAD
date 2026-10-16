import CADCore

/// Persistent four-boundary source law, independent of a rounded tensor image.
public struct OriginalCoonsSurface3D: Hashable, Sendable {
  public let vMinimumBoundary: OriginalCurveRootSpan3D
  public let vMaximumBoundary: OriginalCurveRootSpan3D
  public let uMinimumBoundary: OriginalCurveRootSpan3D
  public let uMaximumBoundary: OriginalCurveRootSpan3D
  private let corners: [SurfaceIntervalVectorJet]
  private let hasPiecewiseFirstOrderAuthority: Bool

  let preparationReceipt: OriginalGeometryPreparationReceipt

  public init(
    vMinimumBoundary: OriginalCurveRootSpan3D, vMaximumBoundary: OriginalCurveRootSpan3D,
    uMinimumBoundary: OriginalCurveRootSpan3D, uMaximumBoundary: OriginalCurveRootSpan3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    let preparationToken = try execution.openPreparationScope()
    var preparationClosed = false
    do {

      try execution.withSourceDepthOffset(1) { execution in
        try vMinimumBoundary.admitPreparation(using: &execution)
        try vMaximumBoundary.admitPreparation(using: &execution)
        try uMinimumBoundary.admitPreparation(using: &execution)
        try uMaximumBoundary.admitPreparation(using: &execution)
      }

      try CurrentTaskCancellationChecker().checkCancellation()
      try tolerance.validate()
      try Self.retainElements(4, of: OriginalCurveRootSpan3D.self, using: &execution)
      let boundaries = [vMinimumBoundary, vMaximumBoundary, uMinimumBoundary, uMaximumBoundary]
      guard boundaries.allSatisfy({ $0.certificationTolerance == tolerance }) else {
        throw GeometryConversionError.invalidInput(
          "Original Coons boundaries must retain one preparation tolerance.")
      }
      let incidence = OriginalCoonsCornerIncidence()
      func admit(
        _ a: OriginalCurveRootSpan3D, _ ae: Bool,
        _ b: OriginalCurveRootSpan3D, _ be: Bool
      ) throws {
        guard
          try incidence.proves(
            first: a, firstAtEnd: ae, second: b, secondAtEnd: be, usage: &execution)
        else {
          throw GeometryConversionError.invalidInput(
            "Original Coons boundaries have unequal original corner positions.")
        }
      }
      try admit(vMinimumBoundary, false, uMinimumBoundary, false)
      try admit(vMinimumBoundary, true, uMaximumBoundary, false)
      try admit(vMaximumBoundary, false, uMinimumBoundary, true)
      try admit(vMaximumBoundary, true, uMaximumBoundary, true)
      var continuous = true
      for boundary in boundaries {
        if try !OriginalCurveTraversalContinuityAdmission().proves(boundary, usage: &execution) {
          continuous = false
        }
      }
      try Self.retainElements(
        4, of: SurfaceIntervalVectorJet.self, using: &execution)
      var originalCorners: [SurfaceIntervalVectorJet] = []
      originalCorners.reserveCapacity(4)
      for boundaryIndex in 0..<2 {
        let boundary = boundaryIndex == 0 ? vMinimumBoundary : vMaximumBoundary
        for stationIndex in 0..<2 {
          let station = Double(stationIndex)
          let q = try boundary.intervalTaylorJet(
            over: .init(lower: station, upper: station), throughOrder: 0, tolerance: tolerance,
            remainingSourceDepth: boundary.remainingSourceDepth, using: &execution)
          originalCorners.append(
            try .init(
              x: Self.constant(q.x.coefficient(0, 0)),
              y: Self.constant(q.y.coefficient(0, 0)), z: Self.constant(q.z.coefficient(0, 0))))
        }
      }
      self.vMinimumBoundary = vMinimumBoundary
      self.vMaximumBoundary = vMaximumBoundary
      self.uMinimumBoundary = uMinimumBoundary
      self.uMaximumBoundary = uMaximumBoundary
      corners = originalCorners
      hasPiecewiseFirstOrderAuthority = continuous

      let preparationDepth = try execution.closePreparationScope(preparationToken)
      preparationClosed = true
      preparationReceipt = try OriginalGeometryPreparationReceipt(
        tolerance: tolerance, depth: preparationDepth, using: &execution)
    } catch {
      if !preparationClosed {
        do { _ = try execution.closePreparationScope(preparationToken) } catch {}
      }
      throw error
    }
  }

  private static func retainElements<T>(
    _ count: Int, of type: T.Type, using execution: inout OriginalQueryExecution
  ) throws {
    try RationalAlgebraStorage.retain(count, of: type, usage: &execution)
  }

  public var uDomain: ParameterDomain { .closed(0, 1) }
  public var vDomain: ParameterDomain { .closed(0, 1) }
  public var certificationTolerance: ModelingTolerance { vMinimumBoundary.certificationTolerance }
  var hasOriginalPositionContinuity: Bool { hasPiecewiseFirstOrderAuthority }

  private static func constant(_ value: OutwardScalarInterval) -> SurfaceIntervalJet {
    let z = OutwardScalarInterval.exact(0)
    return .init(
      value: value, derivativeU: z, derivativeV: z,
      secondDerivativeUU: z, secondDerivativeUV: z, secondDerivativeVV: z,
      thirdDerivativeUUU: z, thirdDerivativeUUV: z, thirdDerivativeUVV: z, thirdDerivativeVVV: z)
  }

  package func admitPreparation(using execution: inout OriginalQueryExecution) throws {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in

      try preparationReceipt.admit(tolerance: certificationTolerance, using: &execution)

    }
  }

  package func admitScalarPreparation<A: ExactScalarAdmission & ~Copyable>(using execution: inout A)
    throws
  {
    try execution.admitDepth(
      value: preparationReceipt.depth.scalar.value,
      coefficient: preparationReceipt.depth.scalar.coefficient)
    try execution.checkpoint()
  }

  public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in

      try validatePreparationBinding(tolerance: tolerance)
      try preparationReceipt.admit(tolerance: tolerance, using: &execution)

    }
  }

  public func validate(tolerance: ModelingTolerance) throws {
    var execution = try preparationReceipt.makeExecution()
    try validate(tolerance: tolerance, using: &execution)
  }

  package func validatePreparationBinding(tolerance: ModelingTolerance) throws {
    try tolerance.validate()
    guard tolerance == certificationTolerance, corners.count == 4 else {
      throw GeometryConversionError.invalidInput(
        "Original Coons queries require the immutable source tolerance.")
    }
  }

  public static func == (a: Self, b: Self) -> Bool {
    a.vMinimumBoundary == b.vMinimumBoundary && a.vMaximumBoundary == b.vMaximumBoundary
      && a.uMinimumBoundary == b.uMinimumBoundary && a.uMaximumBoundary == b.uMaximumBoundary
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(vMinimumBoundary)
    hasher.combine(vMaximumBoundary)
    hasher.combine(uMinimumBoundary)
    hasher.combine(uMaximumBoundary)
  }

  package func intervalJet(
    over box: SurfaceParameterBox, tolerance: ModelingTolerance, maximumSpanCount: Int = Int.max,
    remainingSourceDepth: Int = Int.max, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntervalVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let t = try intervalTaylorJet(
        over: box, throughOrder: 3, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      for _ in 0..<30 {
        try CurrentTaskCancellationChecker().checkCancellation()
        try execution.consumeWork(1)
      }
      return try t.intervalJet()

    }
  }

  package func intervalTaylorJet(
    over box: SurfaceParameterBox, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int = Int.max, remainingSourceDepth: Int = Int.max,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try execution.consumeWork(1)
      try validate(tolerance: tolerance, using: &execution)
      guard order >= 0, maximumSpanCount > 0, remainingSourceDepth >= 0, box.u.lower >= 0,
        box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1
      else {
        throw GeometryConversionError.invalidInput(
          "Original Coons Taylor query exceeds its normalized source square.")
      }
      let bottom = try vMinimumBoundary.intervalTaylorJet(
        over: box.u, throughOrder: order, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      let top = try vMaximumBoundary.intervalTaylorJet(
        over: box.u, throughOrder: order, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      let left = try uMinimumBoundary.intervalTaylorJet(
        over: box.v, throughOrder: order, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      let right = try uMaximumBoundary.intervalTaylorJet(
        over: box.v, throughOrder: order, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      func alongV(_ q: SurfaceAreaIntervalTaylorScalarJet) throws
        -> SurfaceAreaIntervalTaylorScalarJet
      {
        var r = try SurfaceAreaIntervalTaylorScalarJet(
          order: order, axis: .v, tolerance: tolerance, using: &execution)
        for k in 0...order {
          try execution.consumeWork(1)
          try r.set(q.coefficient(k, 0), 0, k)
        }
        return r
      }
      let l = try SurfaceAreaIntervalTaylorVectorJet(
        x: alongV(left.x), y: alongV(left.y), z: alongV(left.z))
      let r = try SurfaceAreaIntervalTaylorVectorJet(
        x: alongV(right.x), y: alongV(right.y), z: alongV(right.z))
      func scalar(_ value: OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
        try .constant(value, order: order, tolerance: tolerance, using: &execution)
      }
      func parameter(_ range: ScalarInterval, alongU: Bool) throws
        -> SurfaceAreaIntervalTaylorScalarJet
      {
        var q = try SurfaceAreaIntervalTaylorScalarJet.constant(
          .init(lower: range.lower, upper: range.upper), order: order, axis: alongU ? .u : .v,
          tolerance: tolerance, using: &execution)
        if order > 0 {
          try execution.consumeWork(1)
          try q.set(.exact(1), alongU ? 1 : 0, alongU ? 0 : 1)
        }
        return q
      }
      let u = try parameter(box.u, alongU: true)
      let v = try parameter(box.v, alongU: false)
      let one = try scalar(.exact(1))
      let um = try one.subtracting(u, using: &execution)
      let vm = try one.subtracting(v, using: &execution)
      func corner(_ index: Int) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try .init(
          x: scalar(corners[index].x.value), y: scalar(corners[index].y.value),
          z: scalar(corners[index].z.value))
      }
      func multiply(
        _ q: SurfaceAreaIntervalTaylorVectorJet,
        _ scalar: SurfaceAreaIntervalTaylorScalarJet
      ) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try .init(
          x: q.x.multiplied(by: scalar, using: &execution),
          y: q.y.multiplied(by: scalar, using: &execution),
          z: q.z.multiplied(by: scalar, using: &execution))
      }
      func add(
        _ a: SurfaceAreaIntervalTaylorVectorJet,
        _ b: SurfaceAreaIntervalTaylorVectorJet
      ) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try .init(
          x: a.x.adding(b.x, using: &execution),
          y: a.y.adding(b.y, using: &execution),
          z: a.z.adding(b.z, using: &execution))
      }
      let b00 = try multiply(multiply(corner(0), um), vm)
      let b10 = try multiply(multiply(corner(1), u), vm)
      let b01 = try multiply(multiply(corner(2), um), v)
      let b11 = try multiply(multiply(corner(3), u), v)
      let bilinear = try add(add(add(b00, b10), b01), b11)
      let negative = try SurfaceAreaIntervalTaylorVectorJet(
        x: bilinear.x.scaled(by: .exact(-1), using: &execution),
        y: bilinear.y.scaled(by: .exact(-1), using: &execution),
        z: bilinear.z.scaled(by: .exact(-1), using: &execution))
      var result = try add(
        add(
          add(
            add(multiply(bottom, vm), multiply(top, v)),
            multiply(l, um)), multiply(r, u)), negative)
      let boundary: SurfaceAreaIntervalTaylorVectorJet?
      if box.v.width == 0, box.v.lower == 0 {
        boundary = bottom
      } else if box.v.width == 0, box.v.lower == 1 {
        boundary = top
      } else if box.u.width == 0, box.u.lower == 0 {
        boundary = l
      } else if box.u.width == 0, box.u.lower == 1 {
        boundary = r
      } else {
        boundary = nil
      }
      if let boundary {
        func originalValue(
          _ q: SurfaceAreaIntervalTaylorScalarJet,
          _ original: SurfaceAreaIntervalTaylorScalarJet
        ) throws -> SurfaceAreaIntervalTaylorScalarJet {
          var out = try SurfaceAreaIntervalTaylorScalarJet(
            order: order, tolerance: tolerance, using: &execution)
          for total in 0...order {
            for a in 0...total {
              try execution.consumeWork(1)
              try out.set(q.coefficient(a, total - a), a, total - a)
            }
          }
          try execution.consumeWork(1)
          try out.set(original.coefficient(0, 0), 0, 0)
          return out
        }
        result = try .init(
          x: originalValue(result.x, boundary.x), y: originalValue(result.y, boundary.y),
          z: originalValue(result.z, boundary.z))
      }
      return result

    }
  }

  func preparedFirstOrder(
    over box: SurfaceParameterBox, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> OriginalSurfaceFirstOrderEnclosure
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try validate(tolerance: tolerance, using: &execution)
      guard box.u.lower >= 0, box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1 else {
        throw GeometryConversionError.invalidInput(
          "Original Coons first-order box exceeds its original square.")
      }
      if !hasPiecewiseFirstOrderAuthority {
        return try .init(
          intervalTaylorJet(
            over: box, throughOrder: 1, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: remainingSourceDepth, using: &execution))
      }
      func boundary(_ source: OriginalCurveRootSpan3D, _ range: ScalarInterval) throws
        -> OriginalCurveFirstOrderJet
      {
        try source.preparedFirstOrder(
          over: range, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, using: &execution)
      }
      let bottom = try boundary(vMinimumBoundary, box.u)
      let top = try boundary(vMaximumBoundary, box.u)
      let left = try boundary(uMinimumBoundary, box.v)
      let right = try boundary(uMaximumBoundary, box.v)
      for _ in 0..<180 {
        try CurrentTaskCancellationChecker().checkCancellation()
        try execution.consumeWork(1)
      }
      let u = OutwardScalarInterval(lower: box.u.lower, upper: box.u.upper)
      let v = OutwardScalarInterval(lower: box.v.lower, upper: box.v.upper)
      let um = OutwardScalarInterval.exact(1) - u
      let vm = OutwardScalarInterval.exact(1) - v
      func axis(
        _ field: (IntervalVector3DBounds) -> OutwardScalarInterval,
        cornerField: (SurfaceIntervalVectorJet) -> OutwardScalarInterval
      ) -> OriginalSurfaceFirstOrderEnclosure.Axis {
        let b = field(bottom.position)
        let t = field(top.position)
        let l = field(left.position)
        let r = field(right.position)
        let p00 = cornerField(corners[0])
        let p10 = cornerField(corners[1])
        let p01 = cornerField(corners[2])
        let p11 = cornerField(corners[3])
        var value =
          b * vm + t * v + l * um + r * u
          - (p00 * um * vm + p10 * u * vm + p01 * um * v + p11 * u * v)
        if box.v.width == 0, box.v.lower == 0 {
          value = b
        } else if box.v.width == 0, box.v.lower == 1 {
          value = t
        } else if box.u.width == 0, box.u.lower == 0 {
          value = l
        } else if box.u.width == 0, box.u.lower == 1 {
          value = r
        }
        return .init(
          value: value,
          derivativeU: field(bottom.firstDerivative) * vm + field(top.firstDerivative) * v - l + r
            - ((p10 - p00) * vm + (p11 - p01) * v),
          derivativeV: -b + t + field(left.firstDerivative) * um + field(right.firstDerivative) * u
            - ((p01 - p00) * um + (p11 - p10) * u))
      }
      return .init(
        x: axis({ $0.x }, cornerField: { $0.x.value }),
        y: axis({ $0.y }, cornerField: { $0.y.value }),
        z: axis({ $0.z }, cornerField: { $0.z.value })
      )

    }
  }

  public func parameterDerivativesThroughThirdOrder(
    u: Double, v: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameterThirdOrderDerivatives {
    var execution = try preparationReceipt.makeExecution()
    return try parameterDerivativesThroughThirdOrder(
      u: u, v: v, tolerance: tolerance, using: &execution)
  }


  public func parameterDerivativesThroughThirdOrder(
    u: Double, v: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterThirdOrderDerivatives {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let q = try intervalJet(
        over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        tolerance: tolerance,
        using: &execution)
      func vector(_ field: (SurfaceIntervalJet) -> OutwardScalarInterval) -> Vector3D {
        .init(x: field(q.x).midpoint, y: field(q.y).midpoint, z: field(q.z).midpoint)
      }
      let p = vector { $0.value }
      let radius = IntervalVector3DBounds(
        x: q.x.value - .exact(p.x), y: q.y.value - .exact(p.y),
        z: q.z.value - .exact(p.z)
      ).lengthUpperBound
      guard radius.isFinite, radius <= tolerance.distance else {
        throw GeometryConversionError.toleranceRejected
      }
      return .init(
        position: .init(x: p.x, y: p.y, z: p.z), tangentU: vector { $0.derivativeU },
        tangentV: vector { $0.derivativeV }, secondDerivativeUU: vector { $0.secondDerivativeUU },
        secondDerivativeUV: vector { $0.secondDerivativeUV },
        secondDerivativeVV: vector { $0.secondDerivativeVV },
        thirdDerivativeUUU: vector { $0.thirdDerivativeUUU },
        thirdDerivativeUUV: vector { $0.thirdDerivativeUUV },
        thirdDerivativeUVV: vector { $0.thirdDerivativeUVV },
        thirdDerivativeVVV: vector { $0.thirdDerivativeVVV })

    }
  }
  public func parameterDerivatives(u: Double, v: Double, tolerance: ModelingTolerance) throws
    -> SurfaceParameterDerivatives
  {
    var execution = try preparationReceipt.makeExecution()
    return try parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
  }

  public func parameterDerivatives(
    u: Double, v: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws
    -> SurfaceParameterDerivatives
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      return try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        .secondOrder

    }
  }
  public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
    var execution = try preparationReceipt.makeExecution()
    return try point(u: u, v: v, tolerance: tolerance, using: &execution)
  }


  public func point(
    u: Double, v: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      return try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        .position

    }
  }

  public func boundarySource(_ boundary: SurfaceParameterBoundary) -> OriginalCurveRootSpan3D {
    switch boundary {
    case .uLower: uMinimumBoundary
    case .uUpper: uMaximumBoundary
    case .vLower: vMinimumBoundary
    case .vUpper: vMaximumBoundary
    }
  }

  func taylorJet(
    u: Double, v: Double, throughOrder order: Int,
    tolerance: ModelingTolerance
  ) throws -> SurfaceTaylorVectorJet {
    var execution = try preparationReceipt.makeExecution()
    return try taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
  }

  func taylorJet(
    u: Double, v: Double, throughOrder order: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      guard order >= 0, order <= 16 else {
        throw GeometryConversionError.invalidInput(
          "Original Coons numeric Taylor order must remain within the surface facade policy.")
      }
      let original = try intervalTaylorJet(
        over: .init(
          u: .init(lower: u, upper: u),
          v: .init(lower: v, upper: v)), throughOrder: order, tolerance: tolerance,
        using: &execution)
      func scalar(_ q: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceTaylorScalarJet {
        var numeric = try SurfaceTaylorScalarJet(order: order)
        for total in 0...order {
          for a in 0...total {
            try CurrentTaskCancellationChecker().checkCancellation()
            try numeric.setCoefficient(
              q.coefficient(a, total - a).midpoint, uOrder: a, vOrder: total - a)
          }
        }
        return numeric
      }
      return try .init(x: scalar(original.x), y: scalar(original.y), z: scalar(original.z))

    }
  }
}
