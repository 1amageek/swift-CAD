import CADCore

extension SurfaceParameterBox {
  public func validate(
    for surface: Surface3D,
    tolerance: ModelingTolerance
  ) throws {
    var execution = try OriginalQueryExecution.independentGeometry()
    try validate(for: surface, tolerance: tolerance, using: &execution)
  }

  public func validate(for surface: Surface3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
    try execution.consumeWork(1)
    try tolerance.validate()
    try surface.validate(tolerance: tolerance, using: &execution)
    try validateAssumingSurfaceValidated(for: surface, tolerance: tolerance)
  }

  func validateAssumingSurfaceValidated(
    for surface: Surface3D,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    guard u.width > 0.0, v.width > 0.0 else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A surface parameter box requires positive U and V spans."
      )
    }
    try validate(u, in: surface.uDomain, direction: "U", tolerance: tolerance)
    try validate(v, in: surface.vDomain, direction: "V", tolerance: tolerance)
  }

  private func validate(
    _ interval: ScalarInterval,
    in domain: ParameterDomain,
    direction: String,
    tolerance: ModelingTolerance
  ) throws {
    switch domain {
    case .unbounded, .periodic:
      return
    case .closed(let lower, let upper):
      guard interval.lower >= lower, interval.upper <= upper else {
        throw KernelError(
          phase: .geometry,
          code: .invalidInput,
          tolerance: tolerance,
          message: "The surface parameter box extends beyond the \(direction) domain."
        )
      }
    }
  }
}
