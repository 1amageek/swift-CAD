import Darwin
import CADCore
@testable import CADGeometry
@testable import PublicLiftPlanePort

/// Observes exact-entry selection separately from the verification assembly fallback.
@main struct DerivativeLiftPlaneStop {
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        init() throws {
            ledger = .init(limits: try .init(work: 8_388_608, storageBytes: 400_000_000,
                valueDepth: 32, coefficientDepth: 32))
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) { try ledger.consumeWork(count) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes: bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try ledger.visitCell(axis: axis, depth: depth)
        }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            try ledger.admitDepth(value: value, coefficient: coefficient)
        }
    }

    static func marker(_ text: String) { print(text); fflush(nil) }

    static func describe(_ result: PublicLiftPlanePort.CurveSurfaceIntersectionResult, label: String) {
        marker("\(label) points=\(result.points.count)")
        for point in result.points {
            marker("POINT t=\(point.curveParameter) xyz=(\(point.point.x),\(point.point.y),\(point.point.z)) planeUV=(\(point.surfaceU),\(point.surfaceV))")
        }
        if let geometry = result.originalIssuedGeometricRelation,
            let mapping = result.originalIssuedNumericalPoints {
            marker("RICH pairs=\(geometry.pairs.count) exactPoints=\(geometry.exactPoints.count) mappings=\(mapping.count) positiveDimensions=\(geometry.hasPositiveDimensionalSolutions)")
            for range in mapping.incidenceRanges { marker("INCIDENT_COUNT \(range.count)") }
        }
    }

    static func main() throws {
        var admission = try Admission()
        let host = try DerivativeHostShape.shape(weighted: true, projected: true, using: &admission)
        // This is mode 0 from the admitted OriginalDerivativeLiftHostVerification fixture.
        let pcurve = SurfaceParameterCurve.bSpline(.init(degree: 1, knots: [0,0,0.5,1,1],
            controlPoints: [.init(x:0,y:0), .init(x:0.5,y:0.5), .init(x:1,y:1)]))
        let curve = Curve3D.surfaceLift(.init(surface: .procedural(.originalPlaneDerivative(host)),
            parameterCurve: pcurve))
        let plane = Surface3D.plane(.init(origin: .init(x: 0.5, y: 0, z: 0), normal: .unitX))
        marker("INPUT existing weighted/projected derivative host; native mode0 diagonal; full T=[0,1]; whole plane x=.5")
        marker("ORACLE one T=.5; hostUV=(.5,.5); XYZ=(.5,.5,65/512); planeUV=(65/512,-.5); 8 closed incidents; image/fiber dimensions0")
        let selected = try PublicLiftPlanePort.OriginalRetainedLiftPlanePublicProducer().resolve(
            curve: curve, surface: plane, options: .init(), tolerance: .standard, retainingRelations: true)
        if let selected {
            describe(selected, label: "SELECTED_PRODUCER_ACCEPTED")
        } else {
            marker("SELECTED_PRODUCER_DECLINED result=nil retainingRelations=true")
        }
        do {
            let rich = try PublicLiftPlanePort.DefaultCurveSurfaceIntersector().intersectionResult(
                curve: curve, surface: plane, options: .init(), tolerance: .standard)
            describe(rich, label: "ORDINARY_RICH_RETURNED")
        } catch PublicLiftPlanePort.CurveSurfaceOverlapResolver.Failure.unselectedLegacyRoute {
            marker("ASSEMBLY_STOP ordinary rich reached verification-only unselectedLegacyRoute tripwire; production fallback behavior unobserved")
        } catch {
            marker("ORDINARY_RICH_THROWN \(error)")
        }
    }
}
