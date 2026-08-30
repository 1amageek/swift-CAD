import CADCore
import CADGeometry

public struct BooleanClosedFaceIntersection: Codable, Hashable, Sendable {
  public let intersection: SurfaceSurfaceIntersectionCurve
  public let samples: [BooleanCurveUVSample]

  public init(
    intersection: SurfaceSurfaceIntersectionCurve,
    samples: [BooleanCurveUVSample],
    tolerance: ModelingTolerance
  ) throws {
    try Self.validateStructure(
      intersection: intersection,
      samples: samples,
      tolerance: tolerance
    )
    for sample in samples {
      let curvePoint = try intersection.curve.pointAssumingValid(
        at: sample.curveParameter,
        tolerance: tolerance
      )
      let residual = (curvePoint - sample.uvPoint.point).length
      guard residual <= tolerance.distance else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          residual: residual,
          tolerance: tolerance,
          message: "Closed face intersection sample disagrees with its curve parameter."
        )
      }
    }
    self.intersection = intersection
    self.samples = samples
  }

  /// Constructs a closed intersection from samples produced directly by
  /// the same intersection's coherent Geometry evaluation. Structural and
  /// closure invariants remain checked here; curve correspondence is not
  /// recomputed after the producer already certified every sample.
  package init(
    intersection: SurfaceSurfaceIntersectionCurve,
    correspondenceVerifiedSamples samples: [BooleanCurveUVSample],
    tolerance: ModelingTolerance
  ) throws {
    try Self.validateStructure(
      intersection: intersection,
      samples: samples,
      tolerance: tolerance
    )
    self.intersection = intersection
    self.samples = samples
  }

  private static func validateStructure(
    intersection: SurfaceSurfaceIntersectionCurve,
    samples: [BooleanCurveUVSample],
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    guard samples.count >= 8,
      samples.allSatisfy({ $0.uvPoint.residual <= tolerance.distance })
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: samples.map(\.uvPoint.residual).max(),
        tolerance: tolerance,
        message: "Closed face intersection requires verified UV samples."
      )
    }
    let parameterThreshold = max(tolerance.angle, tolerance.distance)
    for (index, sample) in samples.enumerated() {
      guard
        try intersection.curve.parameterDomain.contains(
          sample.curveParameter,
          tolerance: tolerance
        )
      else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          tolerance: tolerance,
          message: "Closed face intersection sample lies outside the curve parameter domain."
        )
      }
      if index > 0 {
        guard
          sample.curveParameter - samples[index - 1].curveParameter
            > parameterThreshold
        else {
          throw KernelError(
            phase: .topology,
            code: .invalidInput,
            tolerance: tolerance,
            message: "Closed face intersection samples must have strictly increasing parameters."
          )
        }
      }
    }
    let isClosed: Bool
    if let certifiedClosure = intersection.truth.certifiedComponentClosure {
      isClosed = certifiedClosure
    } else {
      switch intersection.curve.parameterDomain {
      case .periodic:
        isClosed = true
      case .closed(let lower, let upper):
        let start = try intersection.curve.pointAssumingValid(
          at: lower,
          tolerance: tolerance
        )
        let end = try intersection.curve.pointAssumingValid(
          at: upper,
          tolerance: tolerance
        )
        isClosed = start.isApproximatelyEqual(
          to: end,
          tolerance: tolerance.distance
        )
      case .unbounded:
        isClosed = false
      }
    }
    guard isClosed else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message:
          "Closed face intersection requires certified component closure or a closed exact curve domain."
      )
    }
  }

  private enum CodingKeys: String, CodingKey {
    case intersection
    case samples
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try container.validateOnlyExpectedKeys(
      [.intersection, .samples],
      in: decoder
    )
    let intersection = try container.decode(
      SurfaceSurfaceIntersectionCurve.self,
      forKey: .intersection
    )
    try self.init(
      intersection: intersection,
      samples: container.decode(
        [BooleanCurveUVSample].self,
        forKey: .samples
      ),
      tolerance: intersection.certificationTolerance
    )
  }

  public func encode(to encoder: Encoder) throws {
    _ = try BooleanClosedFaceIntersection(
      intersection: intersection,
      samples: samples,
      tolerance: intersection.certificationTolerance
    )
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(intersection, forKey: .intersection)
    try container.encode(samples, forKey: .samples)
  }
}
