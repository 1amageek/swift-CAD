#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif
import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import PublicLiftPlanePort

@main struct PreparedRetainedLiftPlanePortProbe {
    nonisolated static func run() throws {
        var a = try PolylineLiftProof.Admission(work:8_388_608)
        let host = try PolylineAtlasLiftProof.shape(multi:true,using:&a).0
        let input = SurfaceLiftCurve3D(surface:.procedural(.originalCoons(host)),parameterCurve:.polyline(PolylineLiftProof.points()))
        let limits = try PolylineLiftProof.limits()
        let pcurve = try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(maximumValueDepth:32,maximumCoefficientDepth:32))
            .bind(input.parameterCurve,limits:limits.source,using:&a)
        let f = pcurve.original.originalField
        let family = try PolylineAtlasLiftProof.prepared(OriginalCoonsAtlasSnapshotProvider(field:f,tolerance:.standard),input:input,pcurve:pcurve,using:&a)
        typealias Source = OriginalPolylineRetainedAtlasLiftSnapshot<OriginalCoonsAtlasSnapshot>
        let issuer = DefaultOriginalRetainedSurfaceLiftDomainIssuer<Source>()
        let frame = try issuer.frame(family:family,limits:limits,using:&a)
        let lift = try issuer.issue(request:frame.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a)
        let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalPlaneSnapshotProvider(tolerance:.standard))
            .bind(Surface3D.plane(.init(origin:.init(x:0.5,y:0,z:0),normal:.unitX)),limits:limits.source,using:&a)
        let one = try f.integer(1,using:&a)
        let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>()
            .issue(source:source,field:f,firstLength:one,normalLength:one,limits:limits.source,using:&a)
        let domain = DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>()
        let planeFrame = try domain.frame(basis:basis,limits:limits,using:&a)
        let cover = try domain.issue(request:planeFrame.fullSelection(limits:limits,using:&a),basis:basis,limits:limits,using:&a)
        let field = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:32,using:&a)
        let plane = try PublicLiftPlane.DefaultOriginalPlaneGraphCompiler<OriginalPlaneSnapshot>().compile(cover:cover,field:field,limits:limits,using:&a)
        let geometry = try PublicLiftPlane.ExactGeometricRelationLimits(cells:.init(maximumStoredCells:Int.max,maximumRootsPerStack:Int.max),topology:.init(maximumGeneratedCells:Int.max,maximumRootsPerStack:Int.max,maximumClosures:Int.max,maximumAttachmentPieces:Int.max,maximumComponents:Int.max),maximumStrata:Int.max,maximumProjectionSpans:Int.max)
        func query(_ maximum:Int,_ a:inout PolylineLiftProof.Admission) throws -> PublicLiftPlanePort.CurveSurfaceIntersectionResult {
            try PublicLiftPlanePort.DefaultCurveSurfaceIntersector().intersectionResult(lift:lift,plane:plane,maximumPairs:32,
                limits:limits,geometryLimits:geometry,maximumPoints:maximum,using:&a)
        }
        var success = try PolylineLiftProof.Admission(work:8_388_608)
        let result = try query(12,&success)
        try PolylineLiftProof.require(result.representation == .exactRelation && result.points.isEmpty && result.originalIssuedNumericalPoints == nil)
        guard let retained = result.originalIssuedGeometricRelation else { throw ExactScalarFailure.invalidEvidence }
        try PolylineLiftProof.require(retained.exactPoints.count == 12 && !retained.isEmpty && !retained.hasPositiveDimensionalSolutions)
        var later = try PolylineLiftProof.Admission(work:8_388_608)
        for point in retained.exactPoints {
            guard let coordinates = point.originalFirstCoordinates else { throw ExactScalarFailure.invalidEvidence }
            try PolylineLiftProof.require(coordinates.count == 3)
            let q = point.local.witness.field
            let half = try q.dividing(q.integer(1,using:&later),q.integer(2,using:&later),using:&later)
            try PolylineLiftProof.require(q.compare(coordinates[1],half,using:&later) == .equal && q.compare(coordinates[2],half,using:&later) == .equal)
        }
        var limited = try PolylineLiftProof.Admission(work:8_388_608)
        do { _ = try query(11,&limited);throw ExactScalarFailure.invalidEvidence }
        catch PublicLiftPlane.NativeExactGeometricRelationFailure.geometric(.resultLimit) {}
        var cancelled = try PolylineLiftProof.Admission(work:8_388_608,cancelAt:1)
        do { _ = try query(12,&cancelled);throw ExactScalarFailure.invalidEvidence }
        catch PublicLiftPlane.NativeExactGeometricRelationFailure.parameter(.scalar(.cancelled)) {}
        print("PASS prepared lift/whole-plane public entry: exact twelve incidents and original UV; numerical mapping absent; point cap and cancellation preserve failures")
    }
    static func main() {
        do { try run() }
        catch {
            print("FAIL prepared lift/whole-plane public entry")
            #if !hasFeature(Embedded)
            print(error)
            #endif
            exit(1)
        }
    }
}
