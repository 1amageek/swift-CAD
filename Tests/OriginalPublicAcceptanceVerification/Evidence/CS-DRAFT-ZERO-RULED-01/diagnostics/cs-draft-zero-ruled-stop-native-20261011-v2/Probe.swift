import Darwin
import CADCore
@testable import CADGeometry

/// One exact-zero drafted wall observation through the actual ordinary rich fallback.
@main struct DraftZeroRuledStop {
    static func marker(_ value: String) { print(value); fflush(nil) }
    static func main() {
        do {
            var admission = ExactScalarLedger(limits: try .init(work: 8_388_608,
                storageBytes: 8_388_608, valueDepth: 32, coefficientDepth: 32))
            let surface = try ExactScalarNumericAccess.withAdmission(&admission) { usage in
                let raw = BSplineCurve3D(degree: 1, knots: [0,0,1,1],
                    controlPoints: [.origin, .init(x:1,y:0,z:0)], weights: [1,2])
                let generator = try OriginalCurveRootSpan3D(source: .bSpline(raw),
                    start: .authored(0), end: .authored(1), nativeSpanIndex: 1,
                    maximumParameterWidth: ModelingTolerance.standard.relative, maximumSubdivisionDepth: 0,
                    tolerance: .standard, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                    maximumSpanCount: 2, remainingSourceDepth: 0, maximumAlgebraicDepth: 0).reversed()
                let draft = try OriginalDraftedCurve3D(generator: generator, normal: .init(x:0,y:0,z:2),
                    axis: .init(x:0,y:0,z:4), pull: .init(x:0,y:0,z:4), height: 1,
                    angle: +0.0, remainingSourceDepth: 1, tolerance: .standard, usage: &usage)
                return try OriginalDraftedRuledSurface3D(start: draft, endHeight: 3,
                    remainingSourceDepth: 2, tolerance: .standard, usage: &usage)
            }.value
            marker("CONSTRUCTOR_SUCCESS original reversed weighted generator; raw normal2/axis4/pull4; angle+0.0; heights1/3; sourceDepth2")
            marker("ORACLE sole(T,U,V)=(0,2/3,1/2); originalGenerator=1/3; XYZ=(1/2,0,2); one incident; image/fiber dimensions0")
            let curve = Curve3D.line(.init(origin: .init(x:0.5,y:0,z:2), direction: .unitY))
            let host = Surface3D.procedural(.originalDrafted(surface))
            var options = CurveSurfaceIntersectionOptions()
            options.curveRange = try .init(lower: -1, upper: 1)
            options.surfaceURange = try .init(lower: 0, upper: 1)
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
                marker("NUMERICAL_RESULT_ONLY newest issued source/DI/UV/image-fiber fields are outside this cached DTO ABI; no complete-cell acceptance")
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
