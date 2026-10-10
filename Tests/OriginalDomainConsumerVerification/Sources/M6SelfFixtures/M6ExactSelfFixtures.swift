import CADCore
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import SourceGeometryAdapters
@testable import NativeDomainAdapters
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
#else
import CADGeometry
#endif

public enum M6ExactSelfFixtures {
    private enum Failure: Error { case check(Int),unexpectedSuccess(String) }
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    typealias Interval = ExactParameterInterval<Field.Value>
    typealias Cover = OriginalBSplineDomainCover<BSplineSurface3D,Field>
    typealias Raw = NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>
    typealias Identity = OriginalParameterIdentity<BSplineSurface3D,Field>
    static func require(_ value: Bool,_ line: Int = #line) throws { if !value { print("FAIL M6 self assertion \(line)");throw Failure.check(line) } }
    static func ledger(work: Int = 80_000_000,bytes: Int = 1_073_741_824,depth: Int = 32) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:depth,coefficientDepth:depth))
    }
    static func limits(depth: Int = 16) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:0),maximumTransportDepth:depth,maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:64)
    }
    static func cells() throws -> ExactRealCellLimits { try .init(maximumStoredCells:20000,maximumRootsPerStack:100) }
    static func topology() throws -> ExactRealTopologyLimits {
        try .init(maximumGeneratedCells:20000,maximumRootsPerStack:100,maximumClosures:20000,maximumAttachmentPieces:100000,maximumComponents:1000)
    }
    static func value(_ numerator: Int,_ denominator: Int = 1,_ f: Field,_ a: inout ExactScalarLedger) throws -> Field.Value {
        try f.dividing(f.integer(numerator,using:&a),f.integer(denominator,using:&a),using:&a)
    }
    static func interval(_ lo: Int,_ hi: Int,_ f: Field,_ a: inout ExactScalarLedger,denominator: Int = 1,upper: Bool = true) throws -> Interval {
        try .checked(field:f,lower:.finite(value(lo,denominator,f,&a)),upper:.finite(value(hi,denominator,f,&a)),includesLower:true,
            includesUpper:upper,depth:.init(value:0,coefficient:0),using:&a)
    }
    static func cover(_ surface: BSplineSurface3D,_ f: Field,_ selection: [[Interval]]?,_ a: inout ExactScalarLedger) throws -> Cover {
        let l = try limits()
        let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:.standard)).bind(surface,limits:l.source,using:&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let space = try issuer.prepare(source:source,field:f,limits:l,using:&a)
        let request = try selection.map { try space.frame.selection(intervals:$0,limits:l,using:&a) } ?? space.frame.fullSelection(limits:l,using:&a)
        return try issuer.issue(space:space,request:request,limits:l,using:&a)
    }
    static func raw(_ cover: Cover,_ a: inout ExactScalarLedger) throws -> Raw {
        try DefaultSurfaceSurfaceIntersector().exactParameterRelations(first:cover,second:cover,domainLimits:limits(),
            maximumMaps:64,maximumPairs:4096,cellLimits:cells(),topologyLimits:topology(),using:&a)
    }
    static func contacts<A: ExactScalarAdmission & ~Copyable>(_ raw: Raw,_ identities: [Identity] = [],depth: Int = 16,_ a: inout A) throws -> OriginalExactNativeSelfContacts {
        try DefaultOriginalExactNativeSelfContactQuery().contacts(in:raw,excluding:identities,domainLimits:limits(depth:depth),
            cellLimits:cells(),topologyLimits:topology(),using:&a)
    }
    static func contains(_ result: OriginalExactNativeSelfContacts,_ lhs: [Field.Value],_ rhs: [Field.Value],_ a: inout ExactScalarLedger) throws -> Bool {
        try result.contains(firstTuple:lhs,secondTuple:rhs,domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a)
    }
    static func tuple(_ u: Int,_ v: Int,_ f: Field,_ a: inout ExactScalarLedger,denominator: Int = 1) throws -> [Field.Value] {
        [try value(u,denominator,f,&a),try value(v,denominator,f,&a)]
    }
    static func plane() -> BSplineSurface3D {
        .init(uDegree:1,vDegree:1,uKnots:[0,0,1,2,2],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:0.5,y:0,z:0),.init(x:1,y:0,z:0)],
                [.init(x:0,y:1,z:0),.init(x:0.5,y:1,z:0),.init(x:1,y:1,z:0)]])
    }
    static func verifyDiagonalAndFailures() throws {
        var a = try ledger();let f = try Field.base(field:.init(),maximumExtensionLevel:10,using:&a)
        let prepared = try cover(plane(),f,[[interval(1,1,f,&a)],[interval(0,1,f,&a)]],&a)
        let original = try raw(prepared,&a),result = try contacts(original,[],&a)
        try require(original.pieces.count == 4 && result.refinements.count == 4)
        let uv = try tuple(2,1,f,&a,denominator:2)
        try require(try !contains(result,uv,uv,&a))
        try require(result.identities.count == 1 && result.identities[0].kind == .authoredCoordinate)
        for refined in result.refinements {
            try require(refined.pullback.region.included.allSatisfy { !$0 })
            try require(refined.pullback.sourceCellOrdinals.count == refined.pullback.region.cells.count)
        }
        for mode in [0,1,3,4] {
            var refusal = try ledger(work:mode == 0 ? 0:80_000_000,bytes:mode == 1 ? 0:1_073_741_824)
            if mode == 3 { refusal.cancel() }
            do { _ = try contacts(original,[],depth:mode == 4 ? 0:16,&refusal);throw Failure.unexpectedSuccess("budget-\(mode)") }
            catch let failure as NativeExactRelationFailure {
                switch (mode,failure) {
                case (0,.scalar(.resourceLimit(.work))),(0,.domain(.scalar(.resourceLimit(.work)))),
                    (1,.scalar(.resourceLimit(.storage))),(1,.domain(.scalar(.resourceLimit(.storage)))),
                    (3,.scalar(.cancelled)),(4,.domain(.transportDepthLimit)):break
                default:throw failure
                }
            }
        }
        var rationalDepth = try ledger(depth:0)
        let rationalResult = try contacts(original,[],&rationalDepth)
        try require(rationalResult.refinements.count == 4)
        try verifyRetainedScalarDepth()
        var publication = try SelfPublicationAdmission()
        _ = try contacts(original,[],&publication)
        var terminal = try SelfPublicationAdmission(cancellingCall:publication.storageCalls)
        do { _ = try contacts(original,[],&terminal);throw Failure.unexpectedSuccess("terminal-publication") }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        let foreign = try cover(plane(),f,nil,&a)
        let independentlyBound = try DefaultSurfaceSurfaceIntersector().exactParameterRelations(first:prepared,second:foreign,
            domainLimits:limits(),maximumMaps:64,maximumPairs:4096,cellLimits:cells(),topologyLimits:topology(),using:&a)
        do { _ = try contacts(independentlyBound,[],&a);throw Failure.unexpectedSuccess("independent-raw-owner") }
        catch NativeExactRelationFailure.domain(.foreignOwner) {}
        let transporter = DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
        let one = try value(1,1,f,&a),zero = try value(0,1,f,&a)
        let map = try transporter.affine(from:foreign.effective,to:foreign.space.frame,permutation:[0,1],gains:[one,one],offsets:[zero,zero],limits:limits(),using:&a)
        let receipt = try DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>().authored(left:map,right:map,limits:limits(),using:&a)
        do { _ = try contacts(original,[receipt],&a);throw Failure.unexpectedSuccess("foreign-identity-owner") }
        catch NativeExactRelationFailure.domain(.foreignOwner) {}
        print("PASS M6 exact self selected diagonal all 4 chart owners, raw/refined correspondence and typed refusal")
    }
    static func verifyRetainedScalarDepth() throws {
        var preparation = try ledger()
        let base = try Field.base(field:.init(),maximumExtensionLevel:10,using:&preparation)
        let roots = try ExactRealRootDomain(field:base,using:&preparation),polynomials = roots.polynomials
        let equation = try polynomials.polynomial(terms:[.init(powers:[2],coefficient:base.integer(1,using:&preparation)),
            .init(powers:[0],coefficient:base.integer(-2,using:&preparation))],using:&preparation)
        let law = try roots.bind(equation,refinementAxis:.value,using:&preparation)
        let isolation = try roots.domain(lower:.finite(base.integer(1,using:&preparation)),upper:.finite(base.integer(2,using:&preparation)),using:&preparation)
        let root = try roots.isolate(law,in:isolation,limits:.init(maximumRoots:1),using:&preparation).roots[0]
        let refined = try roots.refine(root,maximumWidth:base.dividing(base.integer(1,using:&preparation),base.integer(16,using:&preparation),using:&preparation),using:&preparation)
        let extended = try base.adjoin(refined,using:&preparation),field = extended.domain
        let endpoint = try field.dividing(extended.generator,field.integer(2,using:&preparation),using:&preparation)
        try require(endpoint.depth.value > 0)
        let singleton = try Interval.checked(field:field,lower:.finite(endpoint),upper:.finite(endpoint),depth:endpoint.depth,using:&preparation)
        let selected = try cover(plane(),field,[[singleton],[interval(0,0,field,&preparation)]],&preparation)
        let original = try raw(selected,&preparation)
        var accepted = try ledger()
        let result = try contacts(original,[],&accepted)
        try require(try !contains(result,[endpoint,field.integer(0,using:&accepted)],[endpoint,field.integer(0,using:&accepted)],&accepted))
        var refused = try ledger(depth:0)
        do { _ = try contacts(original,[],&refused);throw Failure.unexpectedSuccess("retained-irrational-depth") }
        catch NativeExactRelationFailure.scalar(.resourceLimit(.valueDepth)) {}
        catch NativeExactRelationFailure.domain(.scalar(.resourceLimit(.valueDepth))) {}
        print("PASS M6 exact self rational depth0 accepted; retained irrational endpoint depth=\(endpoint.depth.value) refused at depth0")
    }
    static func verifyFoldedDeclaredAndLifetime() throws {
        var a = try ledger();let f = try Field.base(field:.init(),maximumExtensionLevel:10,using:&a)
        var folded = BSplineSurface3D(uDegree:2,vDegree:1,uKnots:[-1,-1,-1,1,1,1],vKnots:[-1,-1,1,1],
            controlPoints:[[.init(x:1,y:-1,z:0),.init(x:-1,y:-1,z:0),.init(x:1,y:-1,z:0)],
                [.init(x:1,y:1,z:0),.init(x:-1,y:1,z:0),.init(x:1,y:1,z:0)]])
        let prepared = try cover(folded,f,nil,&a),original = try raw(prepared,&a)
        let law = original.pieces[0].first.law
        let scope = try prepared.space.frame.selection(intervals:[[interval(-1,-1,f,&a)],[interval(0,0,f,&a)]],limits:limits(),using:&a)
        let declaration = OriginalSourceBoundaryDeclaration(left:law.chart,right:law.chart,leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let receipt = try DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>().declaredBoundary(declaration:declaration,left:law,right:law,
            scope:scope,rightFrame:prepared.space.frame,permutation:[0,1],gains:[value(1,1,f,&a),value(1,1,f,&a)],
            offsets:[value(2,1,f,&a),value(0,1,f,&a)],limits:limits(),using:&a)
        let result = try contacts(original,[receipt],&a)
        folded.controlPoints[0][0] = .init(x:99,y:99,z:99)
        try require(try contains(result,tuple(1,0,f,&a,denominator:2),tuple(-1,0,f,&a,denominator:2),&a))
        try require(try !contains(result,tuple(-1,0,f,&a),tuple(1,0,f,&a),&a))
        try require(try contains(result,tuple(-2,1,f,&a,denominator:2),tuple(2,1,f,&a,denominator:2),&a))
        let diagonal = try tuple(1,0,f,&a,denominator:2)
        try require(try !contains(result,diagonal,diagonal,&a))
        try require(result.raw.pieces[0].first.law.source.original.controlPoints[0][0].x == 1)
        print("RUN M6 descendant query")
        let roots = try ExactRealRootDomain(field:f,using:&a),polynomials = roots.polynomials
        let equation = try polynomials.polynomial(terms:[.init(powers:[2],coefficient:f.integer(1,using:&a)),
            .init(powers:[0],coefficient:f.integer(-2,using:&a))],using:&a)
        let lawRoot = try roots.bind(equation,refinementAxis:.value,using:&a)
        let isolation = try roots.domain(lower:.finite(f.integer(1,using:&a)),upper:.finite(f.integer(2,using:&a)),using:&a)
        let root = try roots.isolate(lawRoot,in:isolation,limits:.init(maximumRoots:1),using:&a).roots[0]
        let extensionField = try f.adjoin(root,using:&a),query = extensionField.domain
        let u = try query.dividing(extensionField.generator,query.integer(2,using:&a),using:&a)
        let v = try query.integer(0,using:&a)
        try require(try result.contains(firstTuple:[u,v],secondTuple:[query.negated(u,using:&a),v],queryField:query,domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a))
        do {
            _ = try contains(result,[u,v],[u,v],&a)
            throw Failure.unexpectedSuccess("missing-query-field")
        } catch NativeExactRelationFailure.scalar(.incompatibleDomain) {}
        print("RUN M6 foreign query")
        let foreign = try f.adjoin(root,using:&a)
        do {
            _ = try result.contains(firstTuple:[query.integer(2,using:&a),v],secondTuple:[u,foreign.generator],
                queryField:query,domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a)
            throw Failure.unexpectedSuccess("foreign-excluded-second-coordinate")
        } catch NativeExactRelationFailure.scalar(.incompatibleDomain) {}
        for mode in 0..<4 {
            print("RUN M6 query refusal \(mode)")
            var refused = try ledger(work:mode == 0 ? 0:80_000_000,bytes:mode == 1 ? 0:1_073_741_824,depth:mode == 2 ? 0:32)
            if mode == 3 { refused.cancel() }
            do {
                _ = try result.contains(firstTuple:[u,v],secondTuple:[u,v],queryField:query,
                    domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&refused)
                throw Failure.unexpectedSuccess("algebraic-query-budget")
            } catch let failure as NativeExactRelationFailure {
                let published = NativeExactGeometryPublicationFailure.published(failure,tolerance:.standard)
                if mode == 3 { try require(published is CancellationError) }
                else { try require((published as? KernelError)?.code == .resourceLimitExceeded) }
            }
        }
        print("RUN M6 empty query")
        let outside = try prepared.space.frame.selection(intervals:[[interval(2,2,f,&a)],[interval(0,0,f,&a)]],limits:limits(),using:&a)
        let emptyCover = try DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>().issue(space:prepared.space,request:outside,limits:limits(),using:&a)
        let empty = try contacts(raw(emptyCover,&a),[],&a)
        try require(empty.refinements.isEmpty)
        try require(try !empty.contains(firstTuple:[u,v],secondTuple:[u,v],queryField:query,
            domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a))
        do {
            _ = try empty.contains(firstTuple:[u,v],secondTuple:[u,foreign.generator],queryField:query,
                domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a)
            throw Failure.unexpectedSuccess("empty-foreign-coordinate")
        } catch NativeExactRelationFailure.scalar(.incompatibleDomain) {}
        print("PASS M6 descendant algebraic UV, foreign/empty validation and query resources/cancel")
        print("PASS M6 exact folded sameXYZ nonidentity retained; scoped declared boundary excluded; retained lifetime")
    }
    static func verifyPeriodicSeam() throws {
        var a = try ledger();let f = try Field.base(field:.init(),maximumExtensionLevel:10,using:&a)
        let surface = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:0,z:0)],
                [.init(x:0,y:1,z:0),.init(x:1,y:1,z:0),.init(x:0,y:1,z:0)]],isUPeriodic:true)
        let prepared = try cover(surface,f,[[interval(0,0,f,&a),interval(2,2,f,&a)],[interval(0,0,f,&a),interval(1,1,f,&a)]],&a)
        let original = try raw(prepared,&a),before = try contacts(original,[],&a)
        try require(try contains(before,tuple(0,0,f,&a),tuple(2,0,f,&a),&a))
        let selected = try prepared.space.frame.selection(intervals:[[interval(0,0,f,&a)],[interval(0,0,f,&a)]],limits:limits(),using:&a)
        let cycle = try OriginalParameterCycle(exact:ExactRationalScalarDomain().integer(1,using:&a),using:&a)
        let ids = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        let seam = try ids.periodic(cover:prepared,from:selected,axis:0,cycle:cycle,limits:limits(),using:&a)
        let inverse = try ids.symmetric(seam,limits:limits(),using:&a)
        let result = try contacts(original,[seam,inverse],&a)
        try require(try !contains(result,tuple(0,0,f,&a),tuple(2,0,f,&a),&a))
        try require(try !contains(result,tuple(2,0,f,&a),tuple(0,0,f,&a),&a))
        try require(try contains(result,tuple(0,1,f,&a),tuple(2,1,f,&a),&a))
        try require(result.refinements.count == original.pieces.count)
        print("PASS M6 exact scoped periodic seam exclusion; unproved v=1 seam retained with all lift owners")
    }
    static func verifyCollapsedPole() throws {
        var a = try ledger();let f = try Field.base(field:.init(),maximumExtensionLevel:10,using:&a)
        let surface = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:0,y:0,z:0)],
                [.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
        let prepared = try cover(surface,f,[[interval(0,1,f,&a)],[interval(0,0,f,&a)]],&a),original = try raw(prepared,&a)
        let scope = try prepared.space.frame.selection(intervals:[[interval(0,1,f,&a,denominator:2,upper:false)],[interval(0,0,f,&a)]],limits:limits(),using:&a)
        let identity = try DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>().collapsed(law:original.pieces[0].first.law,on:scope,limits:limits(),using:&a)
        let result = try contacts(original,[identity],&a)
        try require(identity.kind == .collapsedSubset)
        try require(try !contains(result,tuple(1,0,f,&a,denominator:4),tuple(0,0,f,&a),&a))
        try require(try contains(result,tuple(1,0,f,&a,denominator:2),tuple(0,0,f,&a),&a))
        try require(try contains(result,tuple(1,0,f,&a),tuple(0,0,f,&a),&a))
        print("PASS M6 exact collapsed pole product proof excludes only selected open scope")
    }
    public static func verify(group: String? = nil) throws {
        if let group { guard ["diagonal","folded","seam","pole"].contains(group) else { throw Failure.check(0) } }
        if group == nil || group == "diagonal" { print("START M6 exact self diagonal");try verifyDiagonalAndFailures() }
        if group == nil || group == "folded" { print("START M6 exact self folded");try verifyFoldedDeclaredAndLifetime() }
        if group == nil || group == "seam" { print("START M6 exact self seam");try verifyPeriodicSeam() }
        if group == nil || group == "pole" { print("START M6 exact self pole");try verifyCollapsedPole() }
        print("PASS M6 complete Native exact self-contact consumer" + (group.map { " " + $0 } ?? ""))
    }
}
