import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

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

  public func validate(_ surface: Surface3D, over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance) throws {
    var execution = try OriginalQueryExecution.independentGeometry()
    try validate(surface, over: parameters, tolerance: tolerance, using: &execution)
  }

  public func validate(
    _ surface: Surface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try tolerance.validate()
    try surface.validate(tolerance: tolerance, using: &execution)
    try parameters.validateAssumingSurfaceValidated(for: surface, tolerance: tolerance)
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
      tolerance: tolerance, using: &execution
    )
    try validate(parameters: parameters, tolerance: tolerance,
      intervalJet: { box, execution in try encloser.intervalJet(overClosedBox: box, tolerance: tolerance, using: &execution) },
      differential: { u, v, execution in try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution) }, using: &execution)
  }

  func validate(_ blend: RollingBallBlendSurface3D, over parameters: SurfaceParameterBox) throws {
    var execution = try OriginalQueryExecution.independentGeometry()
    try validate(blend, over: parameters, using: &execution)
  }

  func validate(_ blend: RollingBallBlendSurface3D, over parameters: SurfaceParameterBox,
    using execution: inout OriginalQueryExecution) throws {
    try blend.tolerance.validate()
    guard parameters.u.width > 0, parameters.v.width > 0,
      parameters.u.lower >= 0, parameters.u.upper <= 1,
      parameters.v.lower >= 0, parameters.v.upper <= 1,
      maximumSubdivisionDepth > 0, maximumCellCount > 0 else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: blend.tolerance,
        message: "Blend regularity requires a positive normalized box and positive proof budgets.")
    }
    try validate(parameters: parameters, tolerance: blend.tolerance,
      intervalJet: { box, execution in try blend.intervalJet(over: box, using: &execution) },
      differential: { u, v, execution in try blend.parameterDerivatives(u: u, v: v, using: &execution) }, using: &execution)
  }

  private func validate(
    parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance,
    intervalJet: (SurfaceParameterBox, inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet,
    differential: (Double, Double, inout OriginalQueryExecution) throws -> SurfaceParameterDerivatives,
    using execution: inout OriginalQueryExecution
  ) throws {
    var remainingCells = maximumCellCount
    try OriginalCoefficientAllocation.reserve(count: 1, of: Cell.self, using: &execution)
    var stack = [Cell(parameters: parameters, depth: 0)]
    var stackCapacity = 1
    while let cell = stack.popLast() {
      guard remainingCells > 0 else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Surface regularity exhausted its certified cell budget."
        )
      }
      try execution.visitGeometricCell(depth: cell.depth)
      remainingCells -= 1

      do {
        let jet = try intervalJet(cell.parameters, &execution)
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
      let differential = try differential(midpointU, midpointV, &execution)
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
      let children = try subdivided(cell, domain: parameters, using: &execution)
      for child in children.reversed() {
        try OriginalCoefficientAllocation.reserveAppend(to: &stack, capacity: &stackCapacity, using: &execution)
        stack.append(child)
      }
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

  private func subdivided(_ cell: Cell, domain: SurfaceParameterBox, using execution: inout OriginalQueryExecution) throws -> [Cell] {
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
    try OriginalCoefficientAllocation.reserve(count: 2, of: Cell.self, using: &execution)
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
