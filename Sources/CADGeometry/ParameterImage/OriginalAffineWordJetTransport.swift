import CADCore

/// Transports original closed jets through the retained exact spatial word.
package enum OriginalAffineWordJetTransport {
  private struct BorrowedUsage: RationalAlgebraAdmitting {
    let work: () throws -> Void
    let storage: (Int) throws -> Void
    mutating func consumeExactWork(_ count: Int) throws {
      guard count >= 0 else { throw GeometryConversionError.invalidInput("Original word work count is negative.") }
      for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation(); try work() }
    }
    mutating func retainExactStorage(_ count: Int) throws {
      let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
      guard count >= 0, !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original word storage overflows.") }
      try storage(bytes.partialValue)
    }
    mutating func visitExactCell(depth: Int) throws { try work() }
  }

  package static func position(_ word: PreparedOriginalAffineOperationWord,
    bounds: IntervalVector3DBounds, consumeWork: () throws -> Void) throws -> IntervalVector3DBounds {
    try withoutActuallyEscaping(consumeWork) { work in
      var usage = BorrowedUsage(work: work, storage: { _ in try work() })
      let input = try CoordinateEnclosure3D(x: .init(lower: bounds.x.lower, upper: bounds.x.upper),
        y: .init(lower: bounds.y.lower, upper: bounds.y.upper), z: .init(lower: bounds.z.lower, upper: bounds.z.upper))
      let output = try word.enclosure(of: input, isPosition: true, usage: &usage)
      return .init(x: .init(lower: output.x.lower, upper: output.x.upper),
        y: .init(lower: output.y.lower, upper: output.y.upper), z: .init(lower: output.z.lower, upper: output.z.upper))
    }
  }

  package static func linearNormUpper(_ word: PreparedOriginalAffineOperationWord,
    consumeWork: () throws -> Void, consumeStorage: (Int) throws -> Void) throws -> Double {
    try withoutActuallyEscaping(consumeWork) { work in
      try withoutActuallyEscaping(consumeStorage) { storage in
        var usage = BorrowedUsage(work: work, storage: storage)
        return try word.conditionBounds(usage: &usage).linearNormUpper
      }
    }
  }

  package static func applying(_ word: PreparedOriginalAffineOperationWord,
    to jet: SurfaceIntervalVectorJet, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceIntervalVectorJet {
    try withoutActuallyEscaping(consumeWork) { work in
      var usage = BorrowedUsage(work: work, storage: consumeStorage ?? { _ in try CurrentTaskCancellationChecker().checkCancellation() })
      return try applying(word, to: jet, usage: &usage)
    }
  }

  package static func applying(_ word: PreparedOriginalAffineOperationWord,
    to jet: SurfaceAreaIntervalTaylorVectorJet, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil)
    throws -> SurfaceAreaIntervalTaylorVectorJet {
    try withoutActuallyEscaping(consumeWork) { work in
      var usage = BorrowedUsage(work: work, storage: consumeStorage ?? { _ in try work() })
      return try applying(word, to: jet, usage: &usage)
    }
  }

  package static func applying<B: RationalAlgebraAdmitting>(
    _ word: PreparedOriginalAffineOperationWord, to jet: SurfaceIntervalVectorJet,
    usage: inout B) throws -> SurfaceIntervalVectorJet {
    func mapped(_ x: OutwardScalarInterval, _ y: OutwardScalarInterval,
      _ z: OutwardScalarInterval, position: Bool = false) throws -> IntervalVector3DBounds {
      let input = try CoordinateEnclosure3D(x: .init(lower: x.lower, upper: x.upper),
        y: .init(lower: y.lower, upper: y.upper), z: .init(lower: z.lower, upper: z.upper))
      let result = try word.enclosure(of: input, isPosition: position, usage: &usage)
      return .init(x: .init(lower: result.x.lower, upper: result.x.upper),
        y: .init(lower: result.y.lower, upper: result.y.upper),
        z: .init(lower: result.z.lower, upper: result.z.upper))
    }
    let value = try mapped(jet.x.value, jet.y.value, jet.z.value, position: true)
    let u = try mapped(jet.x.derivativeU, jet.y.derivativeU, jet.z.derivativeU)
    let v = try mapped(jet.x.derivativeV, jet.y.derivativeV, jet.z.derivativeV)
    let uu = try mapped(jet.x.secondDerivativeUU, jet.y.secondDerivativeUU, jet.z.secondDerivativeUU)
    let uv = try mapped(jet.x.secondDerivativeUV, jet.y.secondDerivativeUV, jet.z.secondDerivativeUV)
    let vv = try mapped(jet.x.secondDerivativeVV, jet.y.secondDerivativeVV, jet.z.secondDerivativeVV)
    let uuu = try mapped(jet.x.thirdDerivativeUUU, jet.y.thirdDerivativeUUU, jet.z.thirdDerivativeUUU)
    let uuv = try mapped(jet.x.thirdDerivativeUUV, jet.y.thirdDerivativeUUV, jet.z.thirdDerivativeUUV)
    let uvv = try mapped(jet.x.thirdDerivativeUVV, jet.y.thirdDerivativeUVV, jet.z.thirdDerivativeUVV)
    let vvv = try mapped(jet.x.thirdDerivativeVVV, jet.y.thirdDerivativeVVV, jet.z.thirdDerivativeVVV)
    func axis(_ a: IntervalVector3DBounds, _ index: Int) -> OutwardScalarInterval {
      index == 0 ? a.x : index == 1 ? a.y : a.z
    }
    func coordinate(_ index: Int) -> SurfaceIntervalJet {
      .init(value: axis(value, index), derivativeU: axis(u, index), derivativeV: axis(v, index),
        secondDerivativeUU: axis(uu, index), secondDerivativeUV: axis(uv, index),
        secondDerivativeVV: axis(vv, index), thirdDerivativeUUU: axis(uuu, index),
        thirdDerivativeUUV: axis(uuv, index), thirdDerivativeUVV: axis(uvv, index),
        thirdDerivativeVVV: axis(vvv, index))
    }
    return .init(x: coordinate(0), y: coordinate(1), z: coordinate(2))
  }

  package static func applying<B: RationalAlgebraAdmitting>(
    _ word: PreparedOriginalAffineOperationWord, to jet: SurfaceAreaIntervalTaylorVectorJet,
    usage: inout B) throws -> SurfaceAreaIntervalTaylorVectorJet {
    let order = jet.x.order
    guard jet.y.order == order, jet.z.order == order else {
      throw GeometryConversionError.invalidInput("Original affine word requires equal spatial Taylor orders.")
    }
    func reserve(_ bytes: Int) throws {
      let words = bytes.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
      guard bytes >= 0, !words.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original affine Taylor storage overflows.") }
      try usage.retainExactStorage(words.partialValue / MemoryLayout<UInt32>.stride)
    }
    return try withoutActuallyEscaping(reserve) { storage in
      var x = try SurfaceAreaIntervalTaylorScalarJet(order: order, tolerance: jet.x.tolerance,
        consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: storage)
      var y = try SurfaceAreaIntervalTaylorScalarJet(order: order, tolerance: jet.y.tolerance,
        consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: storage)
      var z = try SurfaceAreaIntervalTaylorScalarJet(order: order, tolerance: jet.z.tolerance,
        consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: storage)
      for total in 0...order { for uOrder in 0...total {
        try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeExactWork(1)
        let vOrder = total - uOrder
        let a = try jet.x.coefficient(uOrder, vOrder), b = try jet.y.coefficient(uOrder, vOrder)
        let c = try jet.z.coefficient(uOrder, vOrder)
        let input = try CoordinateEnclosure3D(x: .init(lower: a.lower, upper: a.upper),
          y: .init(lower: b.lower, upper: b.upper), z: .init(lower: c.lower, upper: c.upper))
        let field = try word.enclosure(of: input, isPosition: total == 0, usage: &usage)
        try x.set(.init(lower: field.x.lower, upper: field.x.upper), uOrder, vOrder)
        try y.set(.init(lower: field.y.lower, upper: field.y.upper), uOrder, vOrder)
        try z.set(.init(lower: field.z.lower, upper: field.z.upper), uOrder, vOrder)
      } }
      return .init(x: x, y: y, z: z)
    }
  }
}
