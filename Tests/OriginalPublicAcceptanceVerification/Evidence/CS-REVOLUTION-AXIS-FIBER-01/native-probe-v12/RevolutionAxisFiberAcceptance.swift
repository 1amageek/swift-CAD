import Darwin
import CADCore
@testable import CADGeometry
@main struct RevolutionAxisFiberAcceptance {
 struct Failure:Error { let line:Int }
 static func require(_ value:Bool,line:Int = #line) throws { if !value { throw Failure(line:line) } }
 static func main() throws {
            var admission = ExactScalarLedger(limits: try .init(work: 8_388_608,
                storageBytes: 8_388_608, valueDepth: 32, coefficientDepth: 32))
            let angularBound = 2 * Double.pi
            let surface = try ExactScalarNumericAccess.withAdmission(&admission) { usage in
                let raw = BSplineCurve3D(degree: 1, knots: [0,0,1,1],
                    controlPoints: [.origin, .init(x:1,y:0,z:0)], weights: [1,2])
                let generator = try OriginalCurveRootSpan3D(source: .bSpline(raw),
                    start: .authored(0), end: .authored(1), nativeSpanIndex: 1,
                    maximumParameterWidth: ModelingTolerance.standard.relative, maximumSubdivisionDepth: 0,
                    tolerance: .standard, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                    maximumSpanCount: 2, remainingSourceDepth: 0, maximumAlgebraicDepth: 0).reversed()
                return try OriginalRevolutionSurface3D(generator: generator, axisOrigin: .origin,
                    axisDirection: .init(x:0,y:0,z:2), uDomain: .closed(-angularBound,angularBound),
                    tolerance: .standard, usage: &usage)
            }.value
            
            
            let curve = Curve3D.line(.init(origin: .origin, direction: .unitZ))
            let host = Surface3D.procedural(.originalRevolution(surface))
            var options = CurveSurfaceIntersectionOptions()
            options.curveRange = try .init(lower: -1, upper: 1)
            options.surfaceURange = try .init(lower: -angularBound, upper: angularBound)
            options.surfaceVRange = try .init(lower: 0, upper: 1)

 let group=CommandLine.arguments[1]
 if group == "empty" { options.surfaceVRange=try .init(lower:0,upper:0.5) }
 let result=try DefaultCurveSurfaceIntersector().intersectionResult(curve:curve,surface:host,options:options,tolerance:.standard)
 guard let geometry=result.originalRevolutionAxisRelation else { throw Failure(line:#line) }
 try require(result.representation == .exactRelation && result.points.isEmpty && result.overlaps.isEmpty)
 if group == "empty" { try require(geometry.isEmpty);print("PASS empty public relation") }
 else { try require(!geometry.isEmpty && geometry.hasPositiveDimensionalSolutions && !geometry.hasPositiveDimensionalImage);print("PUBLIC_NONEMPTY_READY_FOR_COMPLETE_ORACLE") }
 }
}
