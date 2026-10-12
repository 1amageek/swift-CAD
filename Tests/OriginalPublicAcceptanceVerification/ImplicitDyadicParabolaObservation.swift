import Foundation
import Darwin
import CADCore
@testable import CADGeometry

@main struct ImplicitDyadicParabolaObservation {
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
    }
    try emit(record)
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
  static func run() throws {
    try emit(["stage": "before-constructor", "constructorCalls": 1,
      "direction": "forward", "split": false,
      "oracle": ["tau": "1/4+T/2", "tuple": [0.5, 0.25, 0.5],
        "firstHostUV": [0.25, 0.5], "secondHostUV": [0.5, 0.5],
        "xyz": [1.0/128, 1.0/128, 0.0], "dimensions": [0, 0, 0],
        "incidents": [1, 1, 1, 1]]])
    let original = try Self().dyadicPlaneParabolaCurve(direction: .forward, split: false)
    let cells: [[String: Any]] = original.cells.map { cell in
      ["freeParameter": String(describing: cell.freeParameter), "direction": String(describing: cell.direction),
       "box": [[cell.parameterBox.firstU.lower, cell.parameterBox.firstU.upper],
               [cell.parameterBox.firstV.lower, cell.parameterBox.firstV.upper],
               [cell.parameterBox.secondU.lower, cell.parameterBox.secondU.upper],
               [cell.parameterBox.secondV.lower, cell.parameterBox.secondV.upper]],
       "anchors": [cell.lowerAnchor, cell.midpointAnchor, cell.upperAnchor].map {
         [$0.first.u, $0.first.v, $0.second.u, $0.second.v]
       }]
    }
    try emit(["stage": "constructor-result", "cellCount": original.cells.count,
      "isClosed": original.isClosed, "cells": cells])
    let target = BSplineSurface3D(uDegree: 1, vDegree: 1,
      uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
      controlPoints: [-1.0/64, 1.0/64].map { z in
        [Point3D(x: 0, y: 1.0/128, z: z), Point3D(x: 1.0/32, y: 1.0/128, z: z)]
      })
    var options = CurveSurfaceIntersectionOptions()
    options.curveRange = try .init(lower: 0, upper: 1)
    options.surfaceURange = try .init(lower: 0, upper: 1)
    options.surfaceVRange = try .init(lower: 0, upper: 1)
    try emit(["stage": "before-public-entry", "ordinaryCSCalls": 1,
      "entry": "DefaultCurveSurfaceIntersector.intersectionResult(curve:surface:options:tolerance:)",
      "curveRange": [0,1], "surfaceURange": [0,1], "surfaceVRange": [0,1],
      "maximumSubdivisionDepth": options.maximumSubdivisionDepth,
      "maximumSubdivisionCells": options.maximumSubdivisionCells,
      "maximumIterations": options.maximumIterations, "maximumCandidateCount": options.maximumCandidateCount,
      "maximumPolynomialDegree": options.maximumPolynomialDegree,
      "maximumPeriodicSeamAttempts": options.maximumPeriodicSeamAttempts])
    do {
      let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .implicit(original),
        surface: .bSpline(target), options: options, tolerance: .standard)
      let points: [[String: Any]] = result.points.map { point in
        ["t": point.curveParameter, "u": point.surfaceU, "v": point.surfaceV,
         "xyz": [point.point.x, point.point.y, point.point.z], "kind": String(describing: point.kind),
         "residual": point.residual, "iterations": point.iterations,
         "originalCurveBoundary": point.originalCurveBoundary != nil]
      }
      let exactNumericalTuple = result.points.count == 1 && result.overlaps.isEmpty && result.points.allSatisfy {
        $0.curveParameter == 0.5 && $0.surfaceU == 0.25 && $0.surfaceV == 0.5 &&
        $0.point.x == 1.0/128 && $0.point.y == 1.0/128 && $0.point.z == 0
      }
      try emit(["stage": "public-result", "pointCount": result.points.count,
        "overlapCount": result.overlaps.count, "points": points,
        "overlaps": result.overlaps.map { ["range": [$0.curveRange.lower, $0.curveRange.upper],
          "maximumSpatialDeviation": $0.maximumSpatialDeviation] as [String: Any] },
        "representation": String(describing: result.representation),
        "hasPositiveDimensionalSolutions": result.hasPositiveDimensionalSolutions,
        "exactNumericalTupleMatchesIndependentOracle": exactNumericalTuple,
        "receiptPresence": ["originalNativePoints": result.originalNativePoints != nil,
          "originalNativeRelations": result.originalNativeRelations != nil,
          "originalPolynomialPoints": result.originalPolynomialPoints != nil,
          "originalAffinePoints": result.originalAffinePoints != nil,
          "originalCoonsPoints": result.originalCoonsPoints != nil,
          "originalExactGeometricRelation": result.originalExactGeometricRelation != nil,
          "originalIssuedGeometricRelation": result.originalIssuedGeometricRelation != nil,
          "originalIssuedNumericalPoints": result.originalIssuedNumericalPoints != nil,
          "originalContainedLiftPlaneFamily": result.originalContainedLiftPlaneFamily != nil,
          "originalRevolutionAxisRelation": result.originalRevolutionAxisRelation != nil,
          "originalAngularPlaneRelation": result.originalAngularPlaneRelation != nil,
          "originalCertifiedApexPlaneExclusion": result.originalCertifiedApexPlaneExclusion != nil],
        "cellComplete": false])
    } catch { try failure(error, stage: "public-failure") }
  }
  static func main() {
    do { try run() }
    catch {
      do { try failure(error, stage: "constructor-or-setup-failure") }
      catch { print("OBSERVATION_RECORD_FAILURE", error) }
      exit(2)
    }
  }
}
