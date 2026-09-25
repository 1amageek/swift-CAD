import CADCore
import CADGeometry
import CADIR
import Testing

@Suite("Certified continuity level mapping", .timeLimit(.minutes(1)))
struct SurfaceBoundaryContinuityTests {
    @Test(arguments: SurfaceContinuityLevel.allCases)
    func certificatesUseTheRequestedLevel(level: SurfaceContinuityLevel) throws {
        let surface = BSplineSurface3D.bilinearPatch(bottomLeft: .origin,
            bottomRight: Point3D(x: 1, y: 0, z: 0), topRight: Point3D(x: 1, y: 1, z: 0),
            topLeft: Point3D(x: 0, y: 1, z: 0))
        let side = SurfaceContinuitySamplingSide(surface: .bSpline(surface),
            parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1))
        let result = try SurfaceBoundaryContinuityEvaluator(modelingTolerance: .standard).certify(
            first: side, second: side, requiredLevel: level,
            tolerances: .init(positionDistance: 1e-7, normalAngle: 1e-6, principalCurvature: 1e-5),
            maximumIntervals: 100, maximumDepth: 10)
        #expect(result.level == level)
        #expect(result.maximumPositionDistance <= 1e-7)
        #expect((result.maximumNormalAngle != nil) == (level >= .tangentPlane))
        #expect((result.maximumShapeOperatorDistance != nil) == (level >= .curvature))
        #expect(result.inspectedIntervals > 0)
    }

    @Test func aTiltedSupportPassesPositionButFailsItsAngleLimit() throws {
        func side(slope: Double) -> SurfaceContinuitySamplingSide {
            let surface = BSplineSurface3D.bilinearPatch(bottomLeft: .origin,
                bottomRight: Point3D(x: 1, y: 0, z: 0), topRight: Point3D(x: 1, y: 1, z: slope),
                topLeft: Point3D(x: 0, y: 1, z: slope))
            return .init(surface: .bSpline(surface), parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1))
        }
        let evaluator = SurfaceBoundaryContinuityEvaluator(modelingTolerance: .standard)
        let tolerance = SurfaceContinuityTolerances(positionDistance: 1e-7, normalAngle: 0.01, principalCurvature: 1e-5)
        _ = try evaluator.certify(first: side(slope: 0), second: side(slope: 0.1),
            requiredLevel: .positional, tolerances: tolerance, maximumIntervals: 100, maximumDepth: 10)
        do {
            _ = try evaluator.certify(first: side(slope: 0), second: side(slope: 0.1),
                requiredLevel: .tangentPlane, tolerances: tolerance, maximumIntervals: 100, maximumDepth: 10)
            Issue.record("Tilted surfaces cannot pass a tighter angle requirement.")
        } catch let error as KernelError { #expect(error.code == .classificationFailure) }
    }
}
