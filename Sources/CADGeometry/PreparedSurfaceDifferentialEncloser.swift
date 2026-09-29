import CADCore

/// Owns immutable representation work that is shared by every interval box
/// inspected during one surface operation. Requested boxes remain independent;
/// only validated source decomposition is retained.
package struct PreparedSurfaceDifferentialEncloser: Sendable {
  private indirect enum Storage: Sendable {
    case direct(Surface3D)
    case bSpline(PreparedBSplineSurfaceDifferentialEncloser)
    case offset(
      OffsetSurface3D,
      source: PreparedSurfaceDifferentialEncloser
    )
    case ruled(PreparedRuledSurfaceDifferentialEncloser)
    case rollingBall(RollingBallBlendSurface3D,
      center: PreparedCurveDifferentialEncloser,
      first: PreparedCurveDifferentialEncloser,
      second: PreparedCurveDifferentialEncloser)
  }

  package let surface: Surface3D
  private let storage: Storage

  /// Local coordinates that can resolve a recoverable enclosure failure.
  /// Rolling-ball radials and circular weights depend only on the spine (U).
  var enclosureRefinementCoordinates: Range<Int> {
    switch storage {
    case .rollingBall: 0..<1
    case .direct, .bSpline, .offset, .ruled: 0..<2
    }
  }

  package init(
    surface: Surface3D,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    try surface.validate(tolerance: tolerance)
    self.surface = surface
    storage = try Self.storage(
      for: surface,
      tolerance: tolerance
    )
  }

  package func enclosure(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceDifferentialEnclosure {
    try DefaultSurfaceDifferentialEncloser().publicEnclosure(
      intervalJet(over: parameters, tolerance: tolerance),
      tolerance: tolerance
    )
  }

  func boundingBox(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> BoundingBox3D {
    let position = try enclosure(
      over: parameters,
      tolerance: tolerance
    ).position
    return try BoundingBox3D(
      minimum: Point3D(
        x: position.x.lower,
        y: position.y.lower,
        z: position.z.lower
      ),
      maximum: Point3D(
        x: position.x.upper,
        y: position.y.upper,
        z: position.z.upper
      )
    ).expanded(by: tolerance.distance)
  }

  func intervalJet(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try parameters.validateAssumingSurfaceValidated(
      for: surface,
      tolerance: tolerance
    )
    switch storage {
    case .direct(let preparedSurface):
      return try DefaultSurfaceDifferentialEncloser()
        .intervalJetAssumingSurfaceValidated(
          of: preparedSurface,
          over: parameters,
          tolerance: tolerance
        )
    case .bSpline(let prepared):
      return try prepared.intervalJetAssumingPrepared(
        over: parameters,
        tolerance: tolerance
      )
    case .offset(let offset, let source):
      return try offset.intervalJet(
        fromValidatedSourceJet: source.intervalJet(
          over: parameters,
          tolerance: tolerance
        ),
        tolerance: tolerance
      )
    case .ruled(let prepared):
      return try prepared.intervalJet(
        over: parameters,
        tolerance: tolerance
      )
    case .rollingBall(let blend, let center, let first, let second):
      return try blend.intervalJet(over: parameters, center: center, first: first, second: second)
    }
  }

  private static func storage(
    for surface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> Storage {
    switch surface {
    case .bSpline(let surface):
      return .bSpline(
        try PreparedBSplineSurfaceDifferentialEncloser(
          surface: surface,
          tolerance: tolerance
        ))
    case .procedural(.offset(let offset)):
      if let equivalent = try offset.exactChartPreservingSurface(
        tolerance: tolerance
      ) {
        return try storage(for: equivalent, tolerance: tolerance)
      }
      return .offset(
        offset,
        source: try PreparedSurfaceDifferentialEncloser(
          surface: offset.source,
          tolerance: tolerance
        )
      )
    case .procedural(.ruled(let ruled)):
      return .ruled(
        try PreparedRuledSurfaceDifferentialEncloser(
          surface: ruled,
          tolerance: tolerance
        ))
    case .procedural(.rollingBall(let blend)):
      return .rollingBall(blend,
        center: try PreparedCurveDifferentialEncloser(curve: blend.centerSpine, tolerance: blend.tolerance),
        first: try PreparedCurveDifferentialEncloser(curve: blend.firstContact, tolerance: blend.tolerance),
        second: try PreparedCurveDifferentialEncloser(curve: blend.secondContact, tolerance: blend.tolerance))
    case .plane, .cylinder, .analytic:
      return .direct(surface)
    }
  }
}
