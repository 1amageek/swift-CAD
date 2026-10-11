import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import PublicLiftPlanePort

/// Exercises the pre-existing prepared public entry after shared publication extraction.
enum PreparedGraphPublicationRegression {
    typealias F = OriginalExactScalarDomain
    static func cover<S:OriginalBSplineSourceReading>(_ charts:OriginalFiniteBSplineCharts<S>,
        field:F,limits:OriginalDomainIdentityLimits,excluding:Bool,using a:inout PolylineLiftProof.Admission)
        throws -> OriginalIssuedDomainCover<S,OriginalBSplineChartSelection,F> {
        var support:[[ExactParameterInterval<OriginalExactScalar>]] = []
        for bound in charts.support {
            support.append([try .checked(field:field,lower:.finite(bound.lower),upper:.finite(bound.upper),
                depth:.zero,using:&a)])
        }
        let frame = try DefaultOriginalParameterTransporter<S,F>().frame(source:charts.source,field:field,
            support:support,semantics:[OriginalCoordinateSemantics](repeating:.authoredScalar,count:support.count),limits:limits,using:&a)
        let request:OriginalParameterSelection<S,F>
        if excluding {
            support[0] = [try .checked(field:field,lower:.finite(field.integer(0,using:&a)),
                upper:.finite(field.binary64(exactly:0.25,using:&a)),depth:.zero,using:&a)]
            request = try frame.selection(intervals:support,limits:limits,using:&a)
        } else { request = try frame.fullSelection(limits:limits,using:&a) }
        return try DefaultOriginalIssuedDomainBinder().bind(laws:charts.laws,request:request,limits:limits,using:&a)
    }
    nonisolated static func run() throws {
        var a = try PolylineLiftProof.Admission(work:8_388_608)
        let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let field = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:32,using:&a)
        let limits = try PolylineLiftProof.limits()
        let curve = BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:0.5,y:0.5,z:-0.25),.init(x:0.5,y:0.5,z:0.75)])
        let surface = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.origin,.init(x:1,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
        let firstSource = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineCurveSnapshotProvider(tolerance:.standard))
            .bind(curve,limits:limits.source,using:&a)
        let secondSource = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:.standard))
            .bind(surface,limits:limits.source,using:&a)
        let firstCharts = try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve3D>().prepare(source:firstSource,field:f,maximumCharts:8,limits:limits.source,using:&a)
        let secondCharts = try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:secondSource,field:f,maximumCharts:8,limits:limits.source,using:&a)
        let first = try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(firstCharts,field:f,limits:limits,excluding:false,using:&a),
            field:field,maximumGraphs:8,limits:limits,using:&a)
        let geometryLimits = try PublicLiftPlane.ExactGeometricRelationLimits(cells:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topology:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:1000,maximumAttachmentPieces:20_000,maximumComponents:1000),
            maximumStrata:1000,maximumProjectionSpans:1000)
        for excluding in [false,true] {
            let second = try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(secondCharts,field:f,limits:limits,excluding:excluding,using:&a),
                field:field,maximumGraphs:8,limits:limits,using:&a)
            let relation = try PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.curveSurface,first:first,second:second,
                maximumPairs:8,limits:limits,cellLimits:geometryLimits.cells,topologyLimits:geometryLimits.topology,using:&a)
            let result = try PublicLiftPlanePort.DefaultCurveSurfaceIntersector().intersectionResult(exactRelations:relation,limits:limits,
                geometryLimits:geometryLimits,maximumPoints:excluding ? 0:8,using:&a)
            guard let retained = result.originalIssuedGeometricRelation else { throw ExactScalarFailure.invalidEvidence }
            try PolylineLiftProof.require(result.representation == .exactRelation && retained.isEmpty == excluding && retained.pairs.count == 1)
            try PolylineLiftProof.require(retained.exactPoints.count == (excluding ? 0:1))
            if !excluding {
                let point = retained.exactPoints[0],q = point.local.witness.field
                let quarter = try q.binary64(exactly:0.25,using:&a),half = try q.binary64(exactly:0.5,using:&a),zero = try q.integer(0,using:&a)
                try PolylineLiftProof.require(point.originalFirstCoordinates == nil)
                try PolylineLiftProof.require(q.compare(point.firstParameters[0],quarter,using:&a) == .equal)
                try PolylineLiftProof.require(q.compare(point.secondParameters[0],half,using:&a) == .equal && q.compare(point.secondParameters[1],half,using:&a) == .equal)
                try PolylineLiftProof.require(q.compare(point.position.z,zero,using:&a) == .equal)
                do {
                    _ = try PublicLiftPlanePort.DefaultCurveSurfaceIntersector().intersectionResult(exactRelations:relation,limits:limits,
                        geometryLimits:geometryLimits,maximumPoints:0,using:&a)
                    throw ExactScalarFailure.invalidEvidence
                } catch PublicLiftPlane.NativeExactGeometricRelationFailure.geometric(.resultLimit) {}
            }
        }
        print("PASS existing prepared GP public regression: exact TUV/XYZ, unchanged exact representation, full exclusion and point limit")
    }
}
