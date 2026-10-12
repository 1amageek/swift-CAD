import Foundation
import Synchronization
import Darwin
import CADCore
@testable import CADGeometry

/// Checks one original implicit source cell through the actual ordinary rich CS entry.
@main struct ImplicitDyadicParabolaAcceptance {
  struct Failure: Error { let line: Int }
  private let tolerance = ModelingTolerance.standard
  static func require(_ value: Bool, line: Int = #line) throws {
    if !value { throw Failure(line: line) }
  }
  static func ledger() throws -> ExactScalarLedger {
    .init(limits: try .init(work: 8_388_608, storageBytes: 268_435_456,
      valueDepth: 32, coefficientDepth: 32))
  }
  private func dyadicPlaneParabolaCurve(
    direction: CertifiedImplicitIntersectionDirection = .forward, split: Bool = false
  ) throws -> CertifiedImplicitIntersectionCurve {
    // Exact original controls: S1(u,v)=(u/32,v/64,0),
    // S2(s,r)=(s^2/32,s/64,(2r-1)/64). No fitted chart or sampled certificate.
    let first = BSplineSurface3D(uDegree:1,vDegree:1,
      uKnots:[-0.5,-0.5,1.5,1.5],vKnots:[0,0,1,1],
      controlPoints:[0.0,1.0/64].map { y in
        [Point3D(x:-1.0/64,y:y,z:0),Point3D(x:3.0/64,y:y,z:0)]
      })
    let second = BSplineSurface3D(uDegree:2,vDegree:1,
      uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],
      controlPoints:[-1.0/64,1.0/64].map { z in
        [Point3D(x:0,y:0,z:z),Point3D(x:0,y:1.0/128,z:z),Point3D(x:1.0/32,y:1.0/64,z:z)]
      })
    func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
      try SurfaceIntersectionParameterPair(first:SurfaceParameter(u:t*t,v:t),
        second:SurfaceParameter(u:t,v:0.5))
    }
    let ranges: [(Double,Double)] = split ? [(0.25,0.5),(0.5,0.75)] : [(0.25,0.75)]
    let ordered = direction == .forward ? ranges : Array(ranges.reversed())
    let cells = try ordered.map { lower,upper in
      try CertifiedImplicitIntersectionGraphCell(parameterBox:SurfaceIntersectionParameterBox(
        firstU:ScalarInterval(lower:-0.25,upper:0.875),firstV:ScalarInterval(lower:lower,upper:upper),
        secondU:ScalarInterval(lower:0.2,upper:0.8),secondV:ScalarInterval(lower:0,upper:1)),
        freeParameter:.firstV,direction:direction,
        lowerAnchor:anchor(lower),midpointAnchor:anchor((lower+upper)/2),upperAnchor:anchor(upper),
        firstSurface:first,secondSurface:second,tolerance:tolerance)
    }
    return try CertifiedImplicitIntersectionCurve(firstSurface:first,secondSurface:second,
      cells:cells,isClosed:false,tolerance:tolerance)
  }
  static func input(empty: Bool) throws -> (Curve3D, Surface3D, CurveSurfaceIntersectionOptions) {
    let original = try Self().dyadicPlaneParabolaCurve(direction: .forward, split: false)
    try require(original.cells.count == 1 && !original.isClosed)
    let target = BSplineSurface3D(uDegree: 1, vDegree: 1,
      uKnots: [0,0,1,1], vKnots: [0,0,1,1],
      controlPoints: [-1.0/64,1.0/64].map { z in
        [Point3D(x:0,y:1.0/128,z:z), Point3D(x:1.0/32,y:1.0/128,z:z)] })
    var options = CurveSurfaceIntersectionOptions()
    options.curveRange = try .init(lower:0,upper:empty ? 0.25 : 1)
    options.surfaceURange = try .init(lower:0,upper:1)
    options.surfaceVRange = try .init(lower:0,upper:1)
    return (.implicit(original),.bSpline(target),options)
  }
  static func verify(_ result: CurveSurfaceIntersectionResult, empty: Bool) throws {
    guard let source = result.originalImplicitCurveRelation,
      let geometry = result.originalIssuedGeometricRelation,
      let mapping = result.originalIssuedNumericalPoints else { throw Failure(line:#line) }
    var a = try ledger()
    try source.evidence.admitProof(limits: .init(remainingSourceDepth:1),using:&a)
    try source.reduction.admitProof(limits: .init(remainingSourceDepth:1),using:&a)
    try require(source.reduction.original.layout.variableCount == 5
      && source.reduction.original.layout.parameters.count == 1
      && source.reduction.original.layout.auxiliaries.count == 4)
    try require(source.reduction.graph.layout.variableCount == 1
      && source.reduction.graph.layout.parameters.count == 1
      && source.reduction.graph.layout.auxiliaries.isEmpty)
    try require(source.reduction.original.conditions.count == 27
      && source.reduction.substitutedConditions.count == 27
      && source.reduction.conditionRanges.count == 27
      && source.reduction.originalCoordinates.count == 5)
    let reduction = source.reduction
    let kept = reduction.retainedConditionOrdinals
    let removed = reduction.eliminatedConditionOrdinals
    try require(kept == kept.sorted() && removed == removed.sorted())
    try require(Set(kept).isDisjoint(with:Set(removed))
      && (kept + removed).sorted() == Array(0..<27)
      && reduction.graph.conditions.count == kept.count)
    let guardField = reduction.graph.field
    let zero = try guardField.integer(0,using:&a)
    // The independent fixture has every original guard valid over its entire closed T interval.
    for ordinal in 0..<27 {
      let range = reduction.conditionRanges[ordinal]
      let lower = try guardField.compare(range.lower,zero,using:&a)
      let upper = try guardField.compare(range.upper,zero,using:&a)
      try require(guardField.compare(range.lower,range.upper,using:&a) != .greater)
      switch reduction.substitutedConditions[ordinal].relation {
      case .equal: try require(lower == .equal && upper == .equal)
      case .notEqual: try require(lower == .greater || upper == .less)
      case .positive: try require(lower == .greater)
      case .nonnegative: try require(lower != .less)
      }
    }
    try require(removed.count == 27 && kept.isEmpty)
    try require(source.original.original.cells.count == 1 && source.evidence.source.sourceDepth == 1)
    try require(source.isEmpty == empty && geometry.isEmpty == empty)
    try require(!source.hasPositiveDimensionalSolutions && !source.hasPositiveDimensionalImage)
    try require(!geometry.hasPositiveDimensionalSolutions && !geometry.hasPositiveDimensionalImage)
    try require(result.overlaps.isEmpty && !result.hasPositiveDimensionalSolutions)
    for pair in geometry.pairs {
      try pair.original.relation.admitProof(using:&a)
      let projection = pair.original.relation.projection
      try require(projection.original.partition.source.variableCount == 3)
      if empty {
        try require(projection.selection.cells.isEmpty && projection.original.cells.isEmpty)
      } else {
        try require(projection.selection.cells.count == 1 && projection.original.cells.count == 1)
        guard let lifts = projection.liftedCells(forProjectedOrdinal:0) else { throw Failure(line:#line) }
        try require(lifts.count == 1 && lifts.original.cells.count == 1)
        for cell in lifts { try require(cell.dimension == 0 && cell.source.variableCount == 3) }
        for stratum in pair.geometry.strata {
          try require(stratum.parameterDimension == 0 && stratum.imageDimension == 0 && stratum.fiberDimension == 0)
        }
      }
    }
    if empty {
      // Whole T <= 1/4 implies tau <= 3/8 and Y <= 3/512 < 1/128.
      try require(result.points.isEmpty && geometry.exactPoints.isEmpty && mapping.count == 0)
      try require(mapping.incidenceOrdinals.isEmpty && mapping.incidenceRanges.isEmpty)
      return
    }
    try require(geometry.pairs.count == 1 && geometry.exactPoints.count == 1 && result.points.count == 1)
    try require(mapping.count == 1 && mapping.incidenceOrdinals == [0] && mapping.incidenceRanges == [0..<1])
    let point = geometry.exactPoints[0], field = point.local.witness.field
    try require(point.firstParameters.count == 1 && point.secondParameters.count == 2)
    try require(point.local.witness.coordinates.count == 3)
    guard let restored = point.originalFirstCoordinates else { throw Failure(line:#line) }
    try require(restored.count == 5)
    // Independent sole complete reduced tuple [T,U,V], retaining every original source coordinate.
    let denominators = [2,4,2]
    for (index,denominator) in denominators.enumerated() {
      let expected = try field.dividing(field.integer(1,using:&a),field.integer(denominator,using:&a),using:&a)
      try require(field.compare(point.local.witness.coordinates[index],expected,using:&a) == .equal)
    }
    // The source-owned unique forward lift preserves original [T,firstU,firstV,secondU,secondV].
    for (index,denominator) in [2,4,2,2,2].enumerated() {
      let expected = try field.dividing(field.integer(1,using:&a),field.integer(denominator,using:&a),using:&a)
      try require(field.compare(restored[index],expected,using:&a) == .equal)
    }
    let xyz = [point.position.x,point.position.y,point.position.z]
    for index in 0..<3 {
      let expected = index == 2 ? try field.integer(0,using:&a) : try field.dividing(field.integer(1,using:&a),field.integer(128,using:&a),using:&a)
      try require(field.compare(xyz[index],expected,using:&a) == .equal)
    }
    let numeric = mapping.coordinates.field
    for (index,denominator) in [2,4,2,128,128,0].enumerated() {
      let expected = denominator == 0 ? try numeric.integer(0,using:&a) : try numeric.dividing(numeric.integer(1,using:&a),numeric.integer(denominator,using:&a),using:&a)
      try require(numeric.compare(mapping.coordinates.values[index],expected,using:&a) == .equal)
    }
  }
  final class TraceCounter: Sendable {
    struct State: Sendable { var entryTicks = 0; var work = 0; var bytes = 0; var traced = false }
    private let state = Mutex(State())
    let maximumWork: Int
    let maximumBytes: Int
    init(options: CurveSurfaceIntersectionOptions) {
      maximumWork = options.maximumSubdivisionCells * options.maximumIterations
      maximumBytes = maximumWork * MemoryLayout<OriginalRationalIntersectionCells.Cell>.stride
    }
    func consume(_ depth: Int) throws {
      let decision = state.withLock { value -> (rejected: Bool, trace: Bool) in
        // The callback-only producer entry admission is separate from scalar work.
        if value.entryTicks == 0 { value.entryTicks = 1; return (false,false) }
        if value.work == maximumWork {
          if !value.traced { value.traced = true; return (true,true) }
          return (true,false)
        }
        value.work += 1
        return (false,false)
      }
      if decision.rejected {
        if decision.trace {
        print("failed-scalar-work: admitted=\(maximumWork) rejected-attempt=\(maximumWork+1) entry-ticks=1")
        for frame in Thread.callStackSymbols { print(frame) }
        fflush(nil)
        }
        throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:nil,
          message:"Native point work allowance exhausted.")
      }
    }
    func retain(_ bytes: Int) throws {
      let accepted = state.withLock { value -> Bool in
        let next = value.bytes.addingReportingOverflow(bytes)
        guard bytes >= 0, !next.overflow, next.partialValue <= maximumBytes else { return false }
        value.bytes = next.partialValue; return true
      }
      if !accepted { throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:nil,
        message:"Native point storage allowance exhausted.") }
    }
    var totals: State { state.withLock { $0 } }
  }
  static func trace() throws {
    let (curve,surface,options) = try input(empty:false)
    let counter = TraceCounter(options:options)
    print("before-public-callback: work=\(counter.maximumWork) bytes=\(counter.maximumBytes) entry-separate=1"); fflush(nil)
    do {
      _ = try DefaultCurveSurfaceIntersector().intersectionResult(curve:curve,surface:surface,
        options:options,tolerance:.standard,maximumSpanCount:options.maximumSubdivisionCells,
        maximumSubdivisionDepth:options.maximumSubdivisionDepth,
        remainingSourceDepth:options.maximumSubdivisionDepth,
        consumeWork:{ try counter.consume($0) },consumeStorage:{ try counter.retain($0) },
        maximumAlgebraicDepth:32)
      print("unexpected-public-return")
    } catch {
      let value = counter.totals
      print("trace-totals: entry=\(value.entryTicks) work=\(value.work) bytes=\(value.bytes) traced=\(value.traced)")
      throw error
    }
  }
  static func main() {
    let mode = CommandLine.arguments.dropFirst().first
    let empty = mode == "empty"
    do {
      if mode == "trace" { try trace(); return }
      let (curve,surface,options) = try input(empty:empty)
      print("before-public-call: \(empty ? "empty" : "complete")"); fflush(nil)
      let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve:curve,surface:surface,
        options:options,tolerance:.standard)
      print("public-return: points=\(result.points.count) implicit=\(result.originalImplicitCurveRelation != nil) geometric=\(result.originalIssuedGeometricRelation != nil) numerical=\(result.originalIssuedNumericalPoints != nil)"); fflush(nil)
      try verify(result,empty:empty)
      print("accepted: \(empty ? "empty" : "complete")"); fflush(nil)
    } catch {
      print("actual-stop: \(String(reflecting:error))"); fflush(nil); exit(1)
    }
  }
}
