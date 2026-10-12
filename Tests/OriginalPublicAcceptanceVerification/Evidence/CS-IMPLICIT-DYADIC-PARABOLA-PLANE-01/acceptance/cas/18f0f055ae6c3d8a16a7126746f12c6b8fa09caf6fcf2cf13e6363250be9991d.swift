#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
import Synchronization
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
  final class Counter: Sendable {
    struct State: Sendable { var work = 0; var bytes = 0 }
    private let state = Mutex(State())
    let maximumWork: Int, maximumBytes: Int
    let cancelAt: Int?, cancelStorageAt: Int?
    init(work: Int = 8_388_609, bytes: Int = 738_197_504,
      cancelAt: Int? = nil, cancelStorageAt: Int? = nil) {
      maximumWork=work; maximumBytes=bytes; self.cancelAt=cancelAt; self.cancelStorageAt=cancelStorageAt
    }
    func consume(_ depth: Int) throws {
      let count = try state.withLock { value in
        guard value.work < maximumWork else { throw ExactScalarFailure.resourceLimit(.work) }
        value.work += 1; return value.work
      }
      if count == cancelAt { throw CancellationError() }
    }
    func retain(_ bytes: Int) throws {
      let count = try state.withLock { value in
        let next=value.bytes.addingReportingOverflow(bytes)
        guard bytes >= 0, !next.overflow, next.partialValue <= maximumBytes else {
          throw ExactScalarFailure.resourceLimit(.storage)
        }
        value.bytes=next.partialValue; return value.bytes
      }
      if count == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
    }
    var totals: State { state.withLock { $0 } }
  }
  static func query(_ curve: Curve3D, _ surface: Surface3D, _ options: CurveSurfaceIntersectionOptions,
    counter: Counter = Counter(), sourceDepth: Int = 8, algebraicDepth: Int = 32,
    spans: Int = 262_144) throws -> CurveSurfaceIntersectionResult {
    try DefaultCurveSurfaceIntersector().intersectionResult(curve:curve,surface:surface,
      options:options,tolerance:.standard,maximumSpanCount:spans,maximumSubdivisionDepth:8,
      remainingSourceDepth:sourceDepth,consumeWork:{try counter.consume($0)},
      consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:algebraicDepth)
  }
  static func numeric(_ points: [CurveSurfaceIntersection], empty: Bool) throws {
    try require(points.count == (empty ? 0:1))
    if !empty {
      let point=points[0]
      try require(point.curveParameter == 0.5 && point.surfaceU == 0.25
        && point.surfaceV == 0.5 && point.point.x == 1.0/128
        && point.point.y == 1.0/128 && point.point.z == 0)
    }
  }
  static func resourceFailure(_ body: () throws -> Void) throws {
    do { try body(); throw Failure(line:#line) }
    catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
  }
  static func sourceControls() throws {
    let (curve,surface,options)=try input(empty:false)
    for other in [try Self().dyadicPlaneParabolaCurve(direction:.reversed),
      try Self().dyadicPlaneParabolaCurve(split:true)] {
      try require(!OriginalImplicitCurveSnapshotProvider.supports(.implicit(other)))
      try require(OriginalImplicitCurvePublicProducer().resolve(curve:.implicit(other),surface:surface,
        options:options,tolerance:.standard) == nil)
    }
    var a=try ledger()
    let field=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
    let zero=try field.integer(0,using:&a), one=try field.integer(1,using:&a)
    let minus=try field.integer(-1,using:&a)
    let unknown=OriginalSourceParameterInterval(lower:minus,upper:one)
    for relation in [OriginalParametricGraphCondition<OriginalExactScalarDomain>.Relation.equal,
      .notEqual,.positive,.nonnegative] {
      try require(!OriginalImplicitCurveGraphReduction.rangeProves(relation,range:unknown,
        field:field,zero:zero,using:&a))
    }
    let limits=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),
      maximumTransportDepth:32,maximumCharts:1,maximumFamilies:2,maximumIdentityProofs:0)
    let issuer=DefaultOriginalSourceBindingIssuer(provider:OriginalImplicitCurveSnapshotProvider(tolerance:.standard))
    let first=try issuer.bind(curve,limits:limits.source,using:&a)
    let foreign=try issuer.bind(curve,limits:limits.source,using:&a)
    let family=try DefaultOriginalFiniteImplicitCurveGraphPreparer().prepare(source:first,field:field,
      maximumCharts:1,limits:limits.source,using:&a)
    let interval=try ExactParameterInterval.checked(field:field,lower:.finite(zero),upper:.finite(one),
      depth:.init(value:0,coefficient:0),using:&a)
    let frame=try DefaultOriginalParameterTransporter<OriginalImplicitCurveSnapshot,OriginalExactScalarDomain>()
      .frame(source:foreign,field:field,support:[[interval]],semantics:[.authoredScalar],limits:limits,using:&a)
    let request=try frame.fullSelection(limits:limits,using:&a)
    let algebraic=try ExactAlgebraicScalarDomain.base(field:field,maximumExtensionLevel:Int.max,using:&a)
    do {
      _ = try DefaultOriginalCompleteCurveGraphFamilyPreparer<OriginalImplicitCurveSnapshot,
        OriginalImplicitCurveGraphEvidence,OriginalImplicitCurveGraphReduction>().prepare(family:family,
        request:request,field:algebraic,maximumGraphs:1,limits:limits,using:&a)
      throw Failure(line:#line)
    } catch NativeExactRelationFailure.domain(.foreignOwner) { }
  }
  static func run(_ selected: String) async throws {
    let (curve,surface,opt)=try input(empty:false)
    if selected == "ordinary" {
      for empty in [false,true] {
        let (c,s,o)=try input(empty:empty), port=DefaultCurveSurfaceIntersector(), counter=Counter()
        try numeric(port.intersections(curve:c,surface:s,options:o,tolerance:.standard),empty:empty)
        try verify(port.intersectionResult(curve:c,surface:s,options:o,tolerance:.standard),empty:empty)
        try numeric(port.intersections(curve:c,surface:s,options:o,tolerance:.standard,
          maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:8,
          consumeWork:{try counter.consume($0)},consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:32),empty:empty)
        try verify(query(c,s,o),empty:empty)
        log("ordinary-work",counter.totals.work); log("ordinary-bytes",counter.totals.bytes)
      }
    } else if selected == "selections" {
      var root=opt;root.curveRange=try .init(lower:0.5,upper:0.5)
      root.surfaceURange=try .init(lower:0.25,upper:0.25);root.surfaceVRange=try .init(lower:0.5,upper:0.5)
      try verify(query(curve,surface,root),empty:false)
      for axis in 0..<3 {
        var outside=opt
        if axis == 0 { outside.curveRange=try .init(lower:2,upper:3) }
        if axis == 1 { outside.surfaceURange=try .init(lower:2,upper:3) }
        if axis == 2 { outside.surfaceVRange=try .init(lower:2,upper:3) }
        try verify(query(curve,surface,outside),empty:true)
      }
    } else if selected == "source" { try sourceControls()
    } else if selected == "limits" {
      try verify(query(curve,surface,opt,sourceDepth:1,spans:1),empty:false)
      try resourceFailure { _ = try query(curve,surface,opt,sourceDepth:0) }
      try resourceFailure { _ = try query(curve,surface,opt,algebraicDepth:0) }
      try resourceFailure { _ = try query(curve,surface,opt,spans:0) }
      var degree=opt;degree.maximumPolynomialDegree=2
      try verify(query(curve,surface,degree),empty:false)
      degree.maximumPolynomialDegree=1
      try resourceFailure { _ = try query(curve,surface,degree) }
      var count=opt;count.maximumCandidateCount=1
      try verify(query(curve,surface,count),empty:false)
      count.maximumCandidateCount=0
      try resourceFailure { _ = try query(curve,surface,count) }
    } else if selected == "budgets" {
      for empty in [false,true] {
        let (c,s,o)=try input(empty:empty), baseline=Counter()
        try verify(query(c,s,o,counter:baseline),empty:empty)
        let n=baseline.totals
        try verify(query(c,s,o,counter:Counter(work:n.work,bytes:n.bytes)),empty:empty)
        try resourceFailure { _ = try query(c,s,o,counter:Counter(work:n.work-1,bytes:n.bytes)) }
        try resourceFailure { _ = try query(c,s,o,counter:Counter(work:n.work,bytes:n.bytes-1)) }
        log("exact-work",n.work);log("exact-bytes",n.bytes)
      }
    } else if selected == "continuous" {
      guard case .implicit(let original)=curve else { throw Failure(line:#line) }
      var o=opt;o.surfaceURange=try .init(lower:-0.5,upper:1.5)
      let result=try query(curve,original.firstSurface,o)
      guard let reader=result.originalImplicitCurveRelation,let geometry=result.originalIssuedGeometricRelation else { throw Failure(line:#line) }
      try require(!reader.isEmpty && reader.hasPositiveDimensionalSolutions && reader.hasPositiveDimensionalImage)
      try require(geometry.hasPositiveDimensionalSolutions && geometry.hasPositiveDimensionalImage)
      var sawCurve=false
      for pair in geometry.pairs { for stratum in pair.geometry.strata {
        try require(stratum.parameterDimension == stratum.imageDimension && stratum.fiberDimension == 0)
        if stratum.parameterDimension == 1 { sawCurve=true }
      } }
      try require(sawCurve)
      print("continuous-exact-representation",result.representation == .exactRelation,
        "numeric-empty",result.points.isEmpty,"dimensions-1-1-0",sawCurve);fflush(nil)
      try require(result.points.isEmpty && result.representation == .exactRelation)
      do { _ = try DefaultCurveSurfaceIntersector().intersections(curve:curve,surface:original.firstSurface,
        options:o,tolerance:.standard);throw Failure(line:#line) }
      catch let error as KernelError { try require(error.code == .nonDiscreteIntersection) }
    } else if selected == "cancel-entry" {
      withUnsafeCurrentTask { $0?.cancel() }
      let counter=Counter()
      do { _ = try query(curve,surface,opt,counter:counter);throw Failure(line:#line) }
      catch is CancellationError { }
      try require(counter.totals.work == 0 && counter.totals.bytes == 0)
    } else if selected == "cancel-mid" {
      for tick in [1,1000] {
        let counter=Counter(cancelAt:tick)
        do { _ = try query(curve,surface,opt,counter:counter);throw Failure(line:#line) }
        catch is CancellationError { }
        try require(counter.totals.work == tick)
      }
    } else if selected == "cancel-final" || selected == "cancel-empty" {
      let empty=selected == "cancel-empty",(c,s,o)=try input(empty:empty), baseline=Counter()
      try verify(query(c,s,o,counter:baseline),empty:empty)
      let count=Counter(cancelStorageAt:baseline.totals.bytes)
      do { _ = try query(c,s,o,counter:count);throw Failure(line:#line) }
      catch is CancellationError { }
      try require(count.totals.bytes == baseline.totals.bytes)
    } else if selected == "lifetime" {
      let result:CurveSurfaceIntersectionResult
      do {
        let (c,s,o)=try input(empty:false)
        result=try query(c,s,o)
        guard case .implicit(let original)=c,case .bSpline(let native)=original.firstSurface else { throw Failure(line:#line) }
        var changed=native;changed.controlPoints[0][0].x=7
        try require(native.controlPoints[0][0].x == -1.0/64 && changed.controlPoints[0][0].x == 7)
      }
      try verify(result,empty:false)
      try await withThrowingTaskGroup(of:Void.self) { readers in
        for _ in 0..<2 { readers.addTask { try verify(result,empty:false) } }
        try await readers.waitForAll()
      }
    } else { throw Failure(line:#line) }
    print("PASS implicit finite acceptance",selected);fflush(nil)
  }
  static func log(_ label: String, _ value: Int) {
#if hasFeature(Embedded)
    print(label,terminator:": ")
    var divisor=1
    while divisor <= value/10 { divisor *= 10 }
    repeat { putchar(Int32(48+value/divisor%10));divisor /= 10 } while divisor > 0
    putchar(10)
#else
    print(label,value)
#endif
    fflush(nil)
  }
  static func group() -> String {
#if hasFeature(Embedded)
    if let value=getenv("CAD_PROOF_GROUP") { return String(cString:value) }
    return "ordinary"
#else
    return CommandLine.arguments.dropFirst().first ?? "ordinary"
#endif
  }
  static func main() async {
    do { try await run(group()) }
    catch {
#if !hasFeature(Embedded)
      print("actual-stop:",String(reflecting:error))
#else
      print("actual-stop: implicit acceptance failure")
#endif
      fflush(nil);exit(1)
    }
  }
}
