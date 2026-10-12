import Foundation
import Darwin
import CADCore
@testable import CADGeometry

@main struct ImplicitClosedPlaneEmptyConnectionAcceptance {
  private let tolerance = ModelingTolerance.standard
  static func emit(_ value: [String: Any]) throws {
    let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: bytes, as: UTF8.self)); fflush(nil)
  }
  static func failure(_ error: any Error, stage: String) throws {
    var record: [String: Any] = ["stage": stage, "error": String(reflecting: error), "cellComplete": false]
    if let kernel = error as? KernelError {
      record["phase"] = String(describing: kernel.phase)
      record["code"] = String(describing: kernel.code)
      record["message"] = kernel.message
      record["category"] = String(describing: kernel.category)
      if let residual = kernel.residual { record["residual"] = residual }
    }
    try emit(record)
  }
  enum ConstructorFailure: Error { case missingExactGraph }
    private func closedPlanePcurve() throws -> (
        intersection: CertifiedImplicitIntersectionCurve,
        surface: BSplineSurface3D
    ) {
        let plane = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -1.5, y: -1.5, z: 0.0),
                    Point3D(x: 1.5, y: -1.5, z: 0.0),
                ],
                [
                    Point3D(x: -1.5, y: 1.5, z: 0.0),
                    Point3D(x: 1.5, y: 1.5, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.25], [0.8, 1.0]]
        )
        let sphere = try AnalyticSurfaceBSplineBuilder().surface(
            for: CanonicalAnalyticSurface(.analytic(.sphere(
                center: .origin,
                radius: 1.0
            ))),
            boundedBy: plane,
            periodicSeamOffset: Double.pi * 0.125,
            tolerance: tolerance
        )
        guard let exact = try ExactIsoparametricPlanarIntersectionGraph
            .certified(
                first: sphere,
                second: plane,
                tolerance: tolerance
            ) else { throw ConstructorFailure.missingExactGraph }
        let domains = [
            sphere.uDomain,
            sphere.vDomain,
            plane.uDomain,
            plane.vDomain,
        ]
        let cells = try exact.cells.map { source in
            let bounds = try zip(source.normalizedBounds, domains).map {
                normalized, domain in
                try ScalarInterval(
                    lower: actual(normalized.lower, in: domain),
                    upper: actual(normalized.upper, in: domain)
                )
            }
            return try CertifiedImplicitIntersectionGraphCell(
                parameterBox: SurfaceIntersectionParameterBox(
                    firstU: bounds[0],
                    firstV: bounds[1],
                    secondU: bounds[2],
                    secondV: bounds[3]
                ),
                freeParameter: source.freeParameter,
                direction: .forward,
                lowerAnchor: exact.actualParameterPair(
                    in: source,
                    at: 0.0,
                    first: sphere,
                    second: plane,
                    tolerance: tolerance
                ),
                midpointAnchor: exact.actualParameterPair(
                    in: source,
                    at: 0.5,
                    first: sphere,
                    second: plane,
                    tolerance: tolerance
                ),
                upperAnchor: exact.actualParameterPair(
                    in: source,
                    at: 1.0,
                    first: sphere,
                    second: plane,
                    tolerance: tolerance
                ),
                firstSurface: sphere,
                secondSurface: plane,
                tolerance: tolerance
            )
        }
        let intersection = try CertifiedImplicitIntersectionCurve(
            firstSurface: sphere,
            secondSurface: plane,
            cells: cells,
            isClosed: true,
            tolerance: tolerance
        )
        return (intersection, plane)
    }
    private func actual(
        _ normalized: Double,
        in domain: ParameterDomain
    ) -> Double {
        guard case let .closed(lower, upper) = domain else { return .nan }
        return lower + (upper - lower) * normalized
    }
  enum ControlFailure: Error { case unexpectedControlLayout, unexpectedNearDomainSuccess }
  static func clonedCells(_ original: CertifiedImplicitIntersectionCurve,
      reversed: Bool = false, swapped: Bool = false, nearDomain: Bool = false)
      throws -> [CertifiedImplicitIntersectionGraphCell] {
    let ordered = reversed ? Array(original.cells.reversed()) : original.cells
    return try ordered.map { cell in
      let box = cell.parameterBox
      let firstV = nearDomain ? try ScalarInterval(lower: box.firstV.lower,
        upper: box.firstV.upper.nextDown) : box.firstV
      func anchor(_ value: SurfaceIntersectionParameterPair) throws -> SurfaceIntersectionParameterPair {
        let first = SurfaceParameter(u: value.first.u,
          v: nearDomain ? box.firstV.upper.nextDown : value.first.v)
        return try SurfaceIntersectionParameterPair(first: swapped ? value.second : first,
          second: swapped ? first : value.second)
      }
      return try CertifiedImplicitIntersectionGraphCell(
        parameterBox: SurfaceIntersectionParameterBox(
          firstU: swapped ? box.secondU : box.firstU,
          firstV: swapped ? box.secondV : firstV,
          secondU: swapped ? box.firstU : box.secondU,
          secondV: swapped ? firstV : box.secondV),
        freeParameter: swapped ? .secondU : cell.freeParameter,
        direction: reversed ? .reversed : cell.direction,
        lowerAnchor: anchor(cell.lowerAnchor), midpointAnchor: anchor(cell.midpointAnchor),
        upperAnchor: anchor(cell.upperAnchor),
        firstSurface: swapped ? original.secondSurface : original.firstSurface,
        secondSurface: swapped ? original.firstSurface : original.secondSurface,
        tolerance: .standard)
    }
  }
  static func controls(_ original: CertifiedImplicitIntersectionCurve) throws {
    guard original.cells.count == 4, original.isClosed,
      original.cells.allSatisfy({ $0.freeParameter == .firstU && $0.direction == .forward }),
      original.cells[0].startAnchor.first.u == 0,
      original.cells[3].endAnchor.first.u == 4 else { throw ControlFailure.unexpectedControlLayout }
    let reverseCells = try clonedCells(original, reversed: true)
    let reverse = try CertifiedImplicitIntersectionCurve(firstSurface: original.firstSurface,
      secondSurface: original.secondSurface, cells: reverseCells, isClosed: true, tolerance: .standard)
    guard reverse.cells.count == 4, reverse.isClosed,
      reverse.cells.allSatisfy({ $0.direction == .reversed }),
      reverse.cells[0].startAnchor.first.u == 4,
      reverse.cells[3].endAnchor.first.u == 0 else { throw ControlFailure.unexpectedControlLayout }
    try emit(["stage":"constructor-control","control":"reversed-four-cells",
      "returned":true,"cellCount":reverse.cells.count,"isClosed":reverse.isClosed,
      "directions":reverse.cells.map { String(describing:$0.direction) },
      "startFirstU":reverse.cells[0].startAnchor.first.u,
      "endFirstU":reverse.cells[reverse.cells.count-1].endAnchor.first.u])
    let swappedCells = try clonedCells(original, swapped: true)
    let swapped = try CertifiedImplicitIntersectionCurve(firstSurface: original.secondSurface,
      secondSurface: original.firstSurface, cells: swappedCells, isClosed: true, tolerance: .standard)
    guard swapped.cells.count == 4, swapped.isClosed,
      swapped.cells.allSatisfy({ $0.freeParameter == .secondU && $0.direction == .forward }),
      swapped.cells[0].startAnchor.second.u == 0,
      swapped.cells[3].endAnchor.second.u == 4 else { throw ControlFailure.unexpectedControlLayout }
    try emit(["stage":"constructor-control","control":"swapped-hosts-four-cells",
      "returned":true,"cellCount":swapped.cells.count,"isClosed":swapped.isClosed,
      "freeParameters":swapped.cells.map { String(describing:$0.freeParameter) },
      "startSecondU":swapped.cells[0].startAnchor.second.u,
      "endSecondU":swapped.cells[swapped.cells.count-1].endAnchor.second.u])
    var negativeStage = "graph-cell-construction"
    do {
      let nearCells = try clonedCells(original, nearDomain: true)
      negativeStage = "closed-curve-construction"
      _ = try CertifiedImplicitIntersectionCurve(firstSurface: original.firstSurface,
        secondSurface: original.secondSurface, cells: nearCells, isClosed: true, tolerance: .standard)
    } catch {
      try emit(["stage":"constructor-control","control":"near-domain-upperV-nextDown",
        "returned":false,"failureStage":negativeStage,
        "upperV":original.cells[0].parameterBox.firstV.upper.nextDown,
        "upperVBits":String(original.cells[0].parameterBox.firstV.upper.nextDown.bitPattern,radix:16),
        "anchorFirstV":"all lower/mid/upper anchors shifted to the same nextDown value",
        "predicateDirectlyObserved":false])
      try failure(error,stage:"negative-constructor-typed-failure")
      return
    }
    throw ControlFailure.unexpectedNearDomainSuccess
  }
  static func run() throws {
    try emit(["stage":"before-constructor","constructorCalls":1,
      "recipe":"actual closedPlanePcurve; original positive before indirect public constructor controls","oracle":["wholeClosedT":[0,1],
        "secondHostHomogeneousZ":"0","secondHostWeightsPositive":true,
        "target":"analytic plane Z=2","completeTupleImageFiber":"empty","cellComplete":false]])
    let fixture=try Self().closedPlanePcurve()
    let original=fixture.intersection
    let target=Surface3D.analytic(.plane(origin:Point3D(x:0,y:0,z:2),normal:.unitZ))
    let cells:[[String:Any]]=original.cells.map { cell in
      ["freeParameter":String(describing:cell.freeParameter),"direction":String(describing:cell.direction),
       "box":[[cell.parameterBox.firstU.lower,cell.parameterBox.firstU.upper],
         [cell.parameterBox.firstV.lower,cell.parameterBox.firstV.upper],
         [cell.parameterBox.secondU.lower,cell.parameterBox.secondU.upper],
         [cell.parameterBox.secondV.lower,cell.parameterBox.secondV.upper]],
       "anchors":[cell.lowerAnchor,cell.midpointAnchor,cell.upperAnchor].map {
         [$0.first.u,$0.first.v,$0.second.u,$0.second.v] }]
    }
    try emit(["stage":"constructor-result","cellCount":original.cells.count,
      "isClosed":original.isClosed,"cells":cells,"target":"analytic plane Z=2",
      "firstUSeamParameters":original.cells.prefix(1).map { $0.lowerAnchor.first.u } + original.cells.suffix(1).map { $0.upperAnchor.first.u },
      "secondHostWeights":fixture.surface.weights,
      "secondHostWeightBinary64Bits":fixture.surface.weights.map { $0.map { String($0.bitPattern,radix:16) } },
      "secondHostControlXYZ":fixture.surface.controlPoints.map { row in row.map { [$0.x,$0.y,$0.z] } }])
    try controls(original)
    var options=CurveSurfaceIntersectionOptions()
    options.curveRange=try .init(lower:0,upper:1)
    options.surfaceURange=try .init(lower:-2,upper:2)
    options.surfaceVRange=try .init(lower:-2,upper:2)
    try emit(["stage":"before-public-entry","ordinaryCSCalls":1,
      "entry":"DefaultCurveSurfaceIntersector.intersectionResult(curve:surface:options:tolerance:)",
      "curveRange":[0,1],"surfaceURange":[-2,2],"surfaceVRange":[-2,2],
      "maximumSubdivisionDepth":options.maximumSubdivisionDepth,
      "maximumSubdivisionCells":options.maximumSubdivisionCells,
      "maximumIterations":options.maximumIterations,"maximumCandidateCount":options.maximumCandidateCount,
      "maximumPolynomialDegree":options.maximumPolynomialDegree,
      "maximumPeriodicSeamAttempts":options.maximumPeriodicSeamAttempts])
    do {
      let result=try DefaultCurveSurfaceIntersector().intersectionResult(curve:.implicit(original),
        surface:target,options:options,tolerance:.standard)
      let points:[[String:Any]]=result.points.map { point in
        ["t":point.curveParameter,"u":point.surfaceU,"v":point.surfaceV,
         "xyz":[point.point.x,point.point.y,point.point.z],"kind":String(describing:point.kind),
         "residual":point.residual,"iterations":point.iterations,
         "originalCurveBoundary":point.originalCurveBoundary != nil]
      }
      try emit(["stage":"public-result","pointCount":result.points.count,
        "overlapCount":result.overlaps.count,"points":points,
        "overlaps":result.overlaps.map { ["range":[$0.curveRange.lower,$0.curveRange.upper],
          "maximumSpatialDeviation":$0.maximumSpatialDeviation] as [String:Any] },
        "representation":String(describing:result.representation),
        "hasPositiveDimensionalSolutions":result.hasPositiveDimensionalSolutions,
        "receiptPresence":["originalImplicitCurveRelation":result.originalImplicitCurveRelation != nil,
          "originalNativePoints":result.originalNativePoints != nil,
          "originalNativeRelations":result.originalNativeRelations != nil,
          "originalPolynomialPoints":result.originalPolynomialPoints != nil,
          "originalAffinePoints":result.originalAffinePoints != nil,
          "originalCoonsPoints":result.originalCoonsPoints != nil,
          "originalExactGeometricRelation":result.originalExactGeometricRelation != nil,
          "originalIssuedGeometricRelation":result.originalIssuedGeometricRelation != nil,
          "originalIssuedNumericalPoints":result.originalIssuedNumericalPoints != nil,
          "originalContainedLiftPlaneFamily":result.originalContainedLiftPlaneFamily != nil,
          "originalRevolutionAxisRelation":result.originalRevolutionAxisRelation != nil,
          "originalAngularPlaneRelation":result.originalAngularPlaneRelation != nil,
          "originalCertifiedApexPlaneExclusion":result.originalCertifiedApexPlaneExclusion != nil],
        "cellComplete":false])
      if let geometry=result.originalIssuedGeometricRelation {
        try emit(["stage":"available-exact-receipts","pairCount":geometry.pairs.count,
          "exactPointCount":geometry.exactPoints.count,
          "strataDimensions":geometry.pairs.flatMap { pair in pair.geometry.strata.map {
            [$0.parameterDimension,$0.imageDimension,$0.fiberDimension] } },
          "incidenceOrdinals":result.originalIssuedNumericalPoints?.incidenceOrdinals ?? [],
          "incidenceRanges":result.originalIssuedNumericalPoints?.incidenceRanges.map {
            [$0.lowerBound,$0.upperBound] } ?? [],"cellComplete":false])
      }
    } catch { try failure(error,stage:"public-failure") }
  }
  static func main() {
    do { try run() }
    catch {
      do { try failure(error,stage:"constructor-or-setup-failure") }
      catch { print("OBSERVATION_RECORD_FAILURE",error) }
      exit(2)
    }
  }
}
