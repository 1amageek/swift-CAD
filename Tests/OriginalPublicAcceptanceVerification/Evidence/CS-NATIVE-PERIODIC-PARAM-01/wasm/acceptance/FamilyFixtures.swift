import L0
import NativeDomainAdapters
import SourceGeometryAdapters
import CADCore
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
#if !NATIVE_FAMILY_FULL_VERIFICATION
import SourceGeometryAdapters
import NativeDomainAdapters
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

public enum FamilyFixtures {
    private enum FixtureFailure: Error { case failed(line: Int), unexpectedSuccess(mode: Int) }
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    typealias Interval = ExactParameterInterval<Field.Value>
    typealias CS = NativeExactParametricRelations<BSplineCurve3D,BSplineSurface3D>
    static func require(_ value: Bool, line: Int = #line) throws {
        if !value { throw FixtureFailure.failed(line:line) }
    }
    static func ledger(work: Int = 80_000_000,bytes: Int = 1_073_741_824,depth: Int = 32) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:depth,coefficientDepth:depth))
    }
    static func limits(charts: Int = 64) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:0),maximumTransportDepth:16,maximumCharts:charts,maximumFamilies:2,maximumIdentityProofs:0)
    }
    static func cells(_ count: Int = 20000) throws -> ExactRealCellLimits {
        try .init(maximumStoredCells:count,maximumRootsPerStack:100)
    }
    static func topology(_ count: Int = 1000) throws -> ExactRealTopologyLimits {
        try .init(maximumGeneratedCells:20000,maximumRootsPerStack:100,maximumClosures:20000,maximumAttachmentPieces:100000,maximumComponents:count)
    }
    static func field(_ a: inout ExactScalarLedger) throws -> Field {
        try .base(field:.init(),maximumExtensionLevel:10,using:&a)
    }
    static func fraction(_ n: Int,_ d: Int = 1,_ f: Field,_ a: inout ExactScalarLedger) throws -> Field.Value {
        try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)
    }
    static func interval(_ lo: Int,_ hi: Int,denominator: Int = 1,_ f: Field,_ a: inout ExactScalarLedger) throws -> Interval {
        try interval(lo,hi,true,true,denominator:denominator,f,&a)
    }
    static func interval(_ lo: Int,_ hi: Int,_ il: Bool,_ iu: Bool,denominator: Int = 1,
        _ f: Field,_ a: inout ExactScalarLedger) throws -> Interval {
        try .checked(field:f,lower:.finite(fraction(lo,denominator,f,&a)),upper:.finite(fraction(hi,denominator,f,&a)),
            includesLower:il,includesUpper:iu,depth:.init(value:0,coefficient:0),using:&a)
    }
    static func curveCover(_ curve: BSplineCurve3D,_ f: Field,_ intervals: [[Interval]]?,_ a: inout ExactScalarLedger)
        throws -> OriginalBSplineDomainCover<BSplineCurve3D,Field> {
        let l = try limits(),source = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineCurveSnapshotProvider(tolerance:.standard)).bind(curve,limits:l.source,using:&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<BSplineCurve3D,Field>()
        let space = try issuer.prepare(source:source,field:f,limits:l,using:&a)
        let request = try intervals.map { try space.frame.selection(intervals:$0,limits:l,using:&a) } ?? space.frame.fullSelection(limits:l,using:&a)
        return try issuer.issue(space:space,request:request,limits:l,using:&a)
    }
    static func surfaceCover(_ surface: BSplineSurface3D,_ f: Field,_ intervals: [[Interval]]?,_ a: inout ExactScalarLedger)
        throws -> OriginalBSplineDomainCover<BSplineSurface3D,Field> {
        let l = try limits(),source = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:.standard)).bind(surface,limits:l.source,using:&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let space = try issuer.prepare(source:source,field:f,limits:l,using:&a)
        let request = try intervals.map { try space.frame.selection(intervals:$0,limits:l,using:&a) } ?? space.frame.fullSelection(limits:l,using:&a)
        return try issuer.issue(space:space,request:request,limits:l,using:&a)
    }
    static func plane(z: Double = 0,multispan: Bool = false) -> BSplineSurface3D {
        let xs: [Double] = multispan ? [0,0.5,1] : [0,1]
        return .init(uDegree:1,vDegree:1,uKnots:multispan ? [0,0,1,2,2]:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[xs.map { .init(x:$0,y:0,z:z) },xs.map { .init(x:$0,y:1,z:z) }])
    }
    static func crossing() -> BSplineCurve3D {
        .init(degree:1,knots:[0,0,1,2,2],controlPoints:[.init(x:0.25,y:0.5,z:-1),.init(x:0.25,y:0.5,z:0),.init(x:0.25,y:0.5,z:1)])
    }
    static func stationary() -> BSplineCurve3D {
        .init(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:0.25,y:0.5,z:0),.init(x:0.25,y:0.5,z:0)])
    }
    static func solve<A: ExactScalarAdmission & ~Copyable>(
        _ first: OriginalBSplineDomainCover<BSplineCurve3D,Field>,_ second: OriginalBSplineDomainCover<BSplineSurface3D,Field>,_ kind: ExactParametricRelationKind,
        cellCount: Int = 20000,componentCount: Int = 1000,maps: Int = 64,pairs: Int = 4096,_ a: inout A) throws -> CS {
        try DefaultCurveSurfaceIntersector().exactParameterRelations(curve:first,surface:second,
            domainLimits:limits(),maximumMaps:maps,maximumPairs:pairs,cellLimits:cells(cellCount),topologyLimits:topology(componentCount),using:&a)
    }
    static func solve<A: ExactScalarAdmission & ~Copyable>(
        _ first: OriginalBSplineDomainCover<BSplineSurface3D,Field>,_ second: OriginalBSplineDomainCover<BSplineSurface3D,Field>,_ kind: ExactParametricRelationKind,
        cellCount: Int = 20000,componentCount: Int = 1000,maps: Int = 64,pairs: Int = 4096,_ a: inout A) throws -> NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D> {
        try DefaultSurfaceSurfaceIntersector().exactParameterRelations(first:first,second:second,
            domainLimits:limits(),maximumMaps:maps,maximumPairs:pairs,cellLimits:cells(cellCount),topologyLimits:topology(componentCount),using:&a)
    }
    static func members<First: OriginalBSplineSourceReading,Second: OriginalBSplineSourceReading>(
        _ result: NativeExactParametricRelations<First,Second>,_ first: [Field.Value],_ second: [Field.Value],_ a: inout ExactScalarLedger) throws -> Int {
        var count = 0
        for piece in result.pieces {
            if try piece.contains(firstTuple:first,secondTuple:second,domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a) { count += 1 }
        }
        return count
    }
    public static func verifyCS() throws {
        for mode in 0..<7 {
            var a = try ledger();let f = try field(&a)
            var curve = crossing()
            let selections: [[Interval]]?
            switch mode {
            case 1: selections = [[try interval(1,1,f,&a)]]
            case 2: selections = [[try interval(0,1,true,false,f,&a),try interval(1,2,false,true,f,&a)]]
            case 3: selections = [[try interval(0,1,denominator:2,f,&a),try interval(3,4,denominator:2,f,&a)]]
            case 4: selections = [[try interval(3,4,f,&a)]]
            case 5: selections = [[]]
            default: selections = nil
            }
            let first = try curveCover(curve,f,selections,&a)
            let second = try surfaceCover(plane(z:mode == 6 ? 2:0,multispan:true),f,nil,&a)
            let result = try solve(first,second,.curveSurface,&a)
            curve.controlPoints.removeAll()
            try require(!result.first.source.original.controlPoints.isEmpty)
            let tuple = [try fraction(1,1,f,&a)],uv = [try fraction(1,2,f,&a),try fraction(1,2,f,&a)]
            try require(try members(result,tuple,uv,&a) == (mode <= 1 ? 2:0))
            try require(result.pieces.count == (mode == 4 || mode == 5 ? 0:4))
            if mode >= 2 { try require(result.pieces.allSatisfy { $0.relation.selection.cells.isEmpty }) }
            if mode == 4 { try require(!result.first.request.isEmpty && result.first.effective.isEmpty) }
            print("PASS M2 Native CS mode=\(mode) pieces=\(result.pieces.count) work=\(a.work) bytes=\(a.storageBytes)")
        }
        var a = try ledger();let f = try field(&a)
        let first = try curveCover(stationary(),f,[[interval(0,1,denominator:4,f,&a),interval(3,4,denominator:4,f,&a)]],&a)
        let second = try surfaceCover(plane(),f,nil,&a)
        let result = try solve(first,second,.curveSurface,&a)
        try require(result.pieces.count == 2)
        for (n,d,wanted) in [(0,1,1),(1,4,1),(1,2,0),(3,4,1),(1,1,1)] {
            try require(try members(result,[fraction(n,d,f,&a)],[fraction(1,4,f,&a),fraction(1,2,f,&a)],&a) == wanted)
        }
        print("PASS M2 disconnected chart-local selection")
    }
    static func periodicSurface(u: Bool = true,v: Bool = true) -> BSplineSurface3D {
        let xs: [Double] = u ? [0,1,0]:[0,1],ys: [Double] = v ? [0,1,0]:[0,1]
        return .init(uDegree:1,vDegree:1,uKnots:u ? [-1,0,1,2,3]:[0,0,1,1],vKnots:v ? [-1,0,1,2,3]:[0,0,1,1],
            controlPoints:ys.map { y in xs.map { x in .init(x:x,y:y,z:0) } },isUPeriodic:u,isVPeriodic:v)
    }
    public static func verifyPeriodic() throws {
        for axes in [(true,false),(false,true),(true,true)] {
            var a = try ledger();let f = try field(&a)
            let c = BSplineCurve3D(degree:1,knots:[-1,0,1,2,3],controlPoints:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:0,z:0)],isPeriodic:true)
            let first = try curveCover(c,f,[[interval(-2,-2,f,&a)]],&a)
            let second = try surfaceCover(periodicSurface(u:axes.0,v:axes.1),f,[[interval(0,0,f,&a)],[interval(0,0,f,&a)]],&a)
            let result = try solve(first,second,.curveSurface,&a)
            let expected = axes.0 && axes.1 ? 8:4
            try require(result.pieces.count == expected)
            try require(try members(result,[fraction(-2,1,f,&a)],[fraction(0,1,f,&a),fraction(0,1,f,&a)],&a) == expected)
            try require(result.first.integerFamilyRank == 1 && result.second.integerFamilyRank == (axes.0 && axes.1 ? 2:1))
            print("PASS M2 independent periodic axes \(axes) owners=\(expected)")
        }
        var a = try ledger();let f = try field(&a)
        let first = try surfaceCover(periodicSurface(),f,[[interval(0,0,f,&a)],[interval(0,0,f,&a)]],&a)
        let second = try surfaceCover(periodicSurface(),f,[[interval(2,2,f,&a)],[interval(-2,-2,f,&a)]],&a)
        let result = try solve(first,second,.surfaceSurface,&a)
        try require(result.pieces.count == 16)
        try require(try members(result,[fraction(0,1,f,&a),fraction(0,1,f,&a)],[fraction(2,1,f,&a),fraction(-2,1,f,&a)],&a) == 16)
        print("PASS M2 periodic SSI full UVUV seam/lift owners=16")
    }
    public static func verifySSI() throws {
        for separated in [false,true] {
            var a = try ledger();let f = try field(&a)
            let first = try surfaceCover(plane(multispan:true),f,[[interval(1,1,f,&a)],[interval(0,1,f,&a)]],&a)
            let second = try surfaceCover(plane(z:separated ? 1:0,multispan:true),f,[[interval(1,1,f,&a)],[interval(0,1,f,&a)]],&a)
            let result = try solve(first,second,.surfaceSurface,&a)
            try require(result.pieces.count == 4)
            let uv = [try fraction(1,1,f,&a),try fraction(1,2,f,&a)]
            try require(try members(result,uv,uv,&a) == (separated ? 0:4))
            if separated { try require(result.pieces.allSatisfy { $0.relation.selection.cells.isEmpty }) }
            print("PASS M2 Native SSI separation=\(separated) chart-side owners=4 work=\(a.work)")
        }
        var a = try ledger();let f = try field(&a)
        let folded = BSplineSurface3D(uDegree:2,vDegree:1,uKnots:[-1,-1,-1,1,1,1],vKnots:[-1,-1,1,1],
            controlPoints:[[.init(x:1,y:-1,z:0),.init(x:-1,y:-1,z:0),.init(x:1,y:-1,z:0)],
                [.init(x:1,y:1,z:0),.init(x:-1,y:1,z:0),.init(x:1,y:1,z:0)]])
        let cover = try surfaceCover(folded,f,nil,&a)
        let result = try solve(cover,cover,.surfaceSurface,&a)
        try require(result.pieces.count == 1 && result.pieces[0].relation.selection.cells.count == 45)
        try require(result.pieces[0].relation.components.incidence.attachments.count == 108)
        try require(try members(result,[fraction(1,1,f,&a),fraction(0,1,f,&a)],[fraction(-1,1,f,&a),fraction(0,1,f,&a)],&a) == 1)
        print("PASS M2 unchanged folded SSI limits cells=45 attachments=108")
    }
    public static func verifyFailures() throws {
        var preparation = try ledger();let f = try field(&preparation)
        let first = try curveCover(stationary(),f,nil,&preparation),second = try surfaceCover(plane(),f,nil,&preparation)
        // This law intersects at t = sqrt(1/2), so a zero value-depth budget must refuse it.
        let depthCurve = BSplineCurve3D(degree:2,knots:[0,0,0,1,1,1],
            controlPoints:[.init(x:0.25,y:0.5,z:-0.5),.init(x:0.25,y:0.5,z:-0.5),.init(x:0.25,y:0.5,z:0.5)])
        let depthFirst = try curveCover(depthCurve,f,nil,&preparation)
        for mode in 0..<8 {
            var a = try ledger(work:mode == 0 ? 0:80_000_000,bytes:mode == 1 ? 0:1_073_741_824,depth:mode == 5 ? 0:32)
            if mode == 2 { a.cancel() }
            do {
                _ = try solve(mode == 5 ? depthFirst:first,second,.curveSurface,cellCount:mode == 3 ? 0:20000,componentCount:mode == 4 ? 0:1000,maps:mode == 6 ? 0:64,pairs:mode == 7 ? 0:4096,&a)
                throw FixtureFailure.unexpectedSuccess(mode:mode)
            } catch let failure as NativeExactRelationFailure {
                try PublicationFailureFixtures.verifyBudgetFailure(failure,cancellation:mode == 2)
            }
        }
        var baseline = try ledger()
        _ = try solve(first,second,.curveSurface,&baseline)
        var injected = try ledger()
        let curveIssuer = ChargingChartIssuer<BSplineCurve3D>(),surfaceIssuer = ChargingChartIssuer<BSplineSurface3D>()
        _ = try DefaultNativeExactRelationFamilyResolver().exactParameterRelations(first:first,second:second,kind:.curveSurface,
            firstIssuer:curveIssuer,secondIssuer:surfaceIssuer,domainLimits:limits(),maximumMaps:64,maximumPairs:4096,cellLimits:cells(),topologyLimits:topology(),using:&injected)
        try require(injected.work - baseline.work == 2_000_000)
        do {
            _ = try DefaultNativeExactRelationFamilyResolver().exactParameterRelations(first:first,second:second,kind:.curveSurface,
                firstIssuer:ChargingChartIssuer<BSplineCurve3D>(refuses:true),secondIssuer:surfaceIssuer,
                domainLimits:limits(),maximumMaps:64,maximumPairs:4096,cellLimits:cells(),topologyLimits:topology(),using:&injected)
            throw FixtureFailure.failed(line:#line)
        } catch NativeExactRelationFailure.domain(.invalidIdentityProof) {}
        var a = try ledger()
        let unbounded = try surfaceCover(periodicSurface(),f,nil,&a)
        do { _ = try solve(first,unbounded,.curveSurface,&a);throw FixtureFailure.failed(line:#line) }
        catch NativeExactRelationFailure.domain(.unsupportedSourceProof) {}
        var measured = try TerminalAdmission()
        _ = try solve(first,second,.curveSurface,&measured)
        var cancelled = try TerminalAdmission(cancellingCall:measured.storageCalls)
        do { _ = try solve(first,second,.curveSurface,&cancelled);throw FixtureFailure.failed(line:#line) }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        print("PASS M2 caller work/storage/depth/cell/component/cancel and unbounded failure")
    }
}
