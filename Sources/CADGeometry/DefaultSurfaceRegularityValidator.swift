import CADCore
import Foundation

/// Certifies surface regularity with outward-rounded differential enclosures.
public struct DefaultSurfaceRegularityValidator: SurfaceRegularityValidating, Sendable {
  private struct Cell: Sendable {
    let parameters: SurfaceParameterBox
    let depth: Int
  }

  public let maximumSubdivisionDepth: Int
  public let maximumCellCount: Int

  public init(
    maximumSubdivisionDepth: Int = 32,
    maximumCellCount: Int = 1_048_576
  ) {
    self.maximumSubdivisionDepth = maximumSubdivisionDepth
    self.maximumCellCount = maximumCellCount
  }

  public func validate(
    _ surface: Surface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    try parameters.validate(for: surface, tolerance: tolerance)
    guard maximumSubdivisionDepth > 0, maximumCellCount > 0 else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Surface regularity limits must be positive."
      )
    }
    let encloser = try PreparedSurfaceDifferentialEncloser(
      surface: surface,
      tolerance: tolerance
    )
    try validate(parameters: parameters, tolerance: tolerance,
      intervalJet: { try encloser.intervalJet(over: $0, tolerance: tolerance) },
      differential: { try surface.parameterDerivatives(atU: $0, v: $1, tolerance: tolerance) })
  }

  func validate(_ blend: RollingBallBlendSurface3D, over parameters: SurfaceParameterBox) throws {
    try blend.tolerance.validate()
    guard parameters.u.width > 0, parameters.v.width > 0,
      parameters.u.lower >= 0, parameters.u.upper <= 1,
      parameters.v.lower >= 0, parameters.v.upper <= 1,
      maximumSubdivisionDepth > 0, maximumCellCount > 0 else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: blend.tolerance,
        message: "Blend regularity requires a positive normalized box and positive proof budgets.")
    }
    try validate(parameters: parameters, tolerance: blend.tolerance,
      intervalJet: { try blend.intervalJet(over: $0) },
      differential: { try blend.parameterDerivatives(atU: $0, v: $1) })
  }

  private func validate(
    parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance,
    intervalJet: (SurfaceParameterBox) throws -> SurfaceIntervalVectorJet,
    differential: (Double, Double) throws -> SurfaceParameterDerivatives
  ) throws {
    var remainingCells = maximumCellCount
    var stack = [Cell(parameters: parameters, depth: 0)]
    while let cell = stack.popLast() {
      guard remainingCells > 0 else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Surface regularity exhausted its certified cell budget."
        )
      }
      remainingCells -= 1

      do {
        let jet = try intervalJet(cell.parameters)
        if certifiesRegularity(jet, tolerance: tolerance) {
          continue
        }
      } catch let error as KernelError where error.code == .singularSystem {
        // A wide interval may include zero through dependency even
        // when each smaller cell is regular. Subdivision preserves
        // the proof contract instead of accepting a midpoint sample.
      }

      let midpointU = cell.parameters.u.midpoint
      let midpointV = cell.parameters.v.midpoint
      let differential = try differential(midpointU, midpointV)
      if isSingular(differential, tolerance: tolerance) {
        throw KernelError(
          phase: .geometry,
          code: .singularGeometry,
          tolerance: tolerance,
          message: "The surface parameterization contains a singular tangent frame."
        )
      }
      guard cell.depth < maximumSubdivisionDepth else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Surface regularity could not certify a cell within the subdivision limit."
        )
      }
      stack.append(contentsOf: try subdivided(cell, domain: parameters).reversed())
    }
  }

  private func certifiesRegularity(
    _ jet: SurfaceIntervalVectorJet,
    tolerance: ModelingTolerance
  ) -> Bool {
    let tangentU = IntervalVector3DBounds(
      x: jet.x.derivativeU, y: jet.y.derivativeU, z: jet.z.derivativeU)
    let tangentV = IntervalVector3DBounds(
      x: jet.x.derivativeV, y: jet.y.derivativeV, z: jet.z.derivativeV)
    guard tangentU.lengthLowerBound > tolerance.distance,
      tangentV.lengthLowerBound > tolerance.distance
    else {
      return false
    }
    let sineTolerance = max(
      sin(min(tolerance.angle, Double.pi * 0.5)),
      tolerance.relative,
      Double.ulpOfOne * 256.0
    )
    let maximumMetricProduct = (tangentU.lengthUpperBound * tangentV.lengthUpperBound).nextUp
    let minimumNormal = (sineTolerance * maximumMetricProduct).nextUp
    return tangentU.cross(tangentV).lengthLowerBound > minimumNormal
  }

  private func isSingular(
    _ differential: SurfaceParameterDerivatives,
    tolerance: ModelingTolerance
  ) -> Bool {
    let tangentULength = differential.tangentU.length
    let tangentVLength = differential.tangentV.length
    guard tangentULength > tolerance.distance,
      tangentVLength > tolerance.distance
    else {
      return true
    }
    let sine =
      differential.tangentU.cross(differential.tangentV).length
      / (tangentULength * tangentVLength)
    let sineTolerance = max(
      sin(min(tolerance.angle, Double.pi * 0.5)),
      tolerance.relative,
      Double.ulpOfOne * 256.0
    )
    return sine.isFinite == false || sine <= sineTolerance
  }

  private func subdivided(_ cell: Cell, domain: SurfaceParameterBox) throws -> [Cell] {
    let u = cell.parameters.u
    let v = cell.parameters.v
    let middleU = u.midpoint
    let middleV = v.midpoint
    let canSplitU = middleU > u.lower && middleU < u.upper
    let canSplitV = middleV > v.lower && middleV < v.upper
    guard canSplitU || canSplitV else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        tolerance: nil,
        message: "Surface regularity reached the representable parameter resolution."
      )
    }
    let depth = cell.depth + 1
    // Normalize to the original domain so parameter units cannot starve an axis.
    if canSplitU && (!canSplitV || u.width / domain.u.width >= v.width / domain.v.width) {
      return [
        Cell(parameters: SurfaceParameterBox(u: try ScalarInterval(lower: u.lower, upper: middleU), v: v), depth: depth),
        Cell(parameters: SurfaceParameterBox(u: try ScalarInterval(lower: middleU, upper: u.upper), v: v), depth: depth),
      ]
    }
    return [
      Cell(parameters: SurfaceParameterBox(u: u, v: try ScalarInterval(lower: v.lower, upper: middleV)), depth: depth),
      Cell(parameters: SurfaceParameterBox(u: u, v: try ScalarInterval(lower: middleV, upper: v.upper)), depth: depth),
    ]
  }
}
