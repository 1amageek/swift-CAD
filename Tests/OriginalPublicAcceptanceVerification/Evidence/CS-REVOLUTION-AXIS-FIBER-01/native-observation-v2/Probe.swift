import Darwin
import CADCore
@testable import CADGeometry

/// One fixed original revolution request through the real ordinary rich fallback.
@main struct RevolutionAxisFiberObservation {
    static func marker(_ value: String) { print(value); fflush(nil) }
    static func main() {
        do {
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
            marker("CONSTRUCTOR_SUCCESS reversed weighted generator; raw axis(0,0,2); U[-B,B]; V[0,1]; B=stored2*Double.pi")
            marker("ORACLE T=0,V=1,allU[-B,B]; generatorLocal=0; XYZ=origin; parameter1/image0/fiber1; both seam incidents at -B,0,B")
            let curve = Curve3D.line(.init(origin: .origin, direction: .unitZ))
            let host = Surface3D.procedural(.originalRevolution(surface))
            var options = CurveSurfaceIntersectionOptions()
            options.curveRange = try .init(lower: -1, upper: 1)
            options.surfaceURange = try .init(lower: -angularBound, upper: angularBound)
            options.surfaceVRange = try .init(lower: 0, upper: 1)
            marker("ORDINARY_RICH_BEGIN unchanged standard ceilings")
            do {
                let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve,
                    surface: host, options: options, tolerance: .standard)
                marker("ORDINARY_RICH_RETURNED points=\(result.points.count) overlaps=\(result.overlaps.count)")
                for point in result.points {
                    marker("POINT T=\(point.curveParameter) U=\(point.surfaceU) V=\(point.surfaceV) XYZ=(\(point.point.x),\(point.point.y),\(point.point.z)) kind=\(point.kind)")
                }
                marker("CACHED_DTO_PROOFS nativePoints=\(result.originalNativePoints != nil) nativeRelations=\(result.originalNativeRelations != nil) polynomial=\(result.originalPolynomialPoints != nil) affine=\(result.originalAffinePoints != nil) coons=\(result.originalCoonsPoints != nil) exactGeometry=\(result.originalExactGeometricRelation != nil)")
                marker("DIAGNOSTIC_ONLY newest issued fields are outside this cached DTO ABI; no complete-cell acceptance")
            } catch let error as KernelError {
                marker("OBSERVED_TYPED_PUBLIC_FAILURE code=\(error.code) message=\(error.message)")
            } catch {
                marker("OBSERVED_OTHER_PUBLIC_FAILURE \(error)")
            }
        } catch {
            marker("OBSERVED_CONSTRUCTOR_OR_ASSEMBLY_FAILURE \(error)")
        }
    }
}
