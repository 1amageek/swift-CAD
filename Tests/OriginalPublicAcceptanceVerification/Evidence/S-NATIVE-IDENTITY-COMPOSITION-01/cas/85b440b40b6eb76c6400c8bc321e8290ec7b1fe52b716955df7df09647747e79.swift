import CADCore
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
import NativeDeclaredWholeEdgeSelf
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// First public observation of scoped symmetry and transitive composition on the original fold.
@main struct NativeIdentityCompositionAcceptance {
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Cells = ExactRealCellDomain<Base>
    typealias Raw = NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>
    typealias Result = NativeDeclaredWholeEdgeSelf.OriginalExactNativeSelfContacts
    enum Failure: Error { case assertion(Int), unexpectedSuccess }
    nonisolated static func require(_ value: Bool, _ line: Int = #line) throws {
        guard value else { metric("FAIL S-NATIVE-IDENTITY-COMPOSITION-01",[line]); throw Failure.assertion(line) }
    }
    nonisolated static func marker(_ text: StaticString) { print(text); fflush(nil) }
    nonisolated static func digits(_ value:Int) {
        if value >= 10 { digits(value/10) }
        _ = putchar(Int32(48+value%10))
    }
    nonisolated static func metric(_ text:StaticString,_ values:[Int]) {
        print(text,terminator:" ")
        for value in values { digits(value);_ = putchar(32) }
        _ = putchar(10);fflush(nil)
    }
    nonisolated static func limits(depth:Int = 16,count:Int = 64) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:0),maximumTransportDepth:depth,maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:count)
    }
    nonisolated static func cellLimits() throws -> ExactRealCellLimits { try .init(maximumStoredCells:20000,maximumRootsPerStack:100) }
    nonisolated static func topologyLimits() throws -> ExactRealTopologyLimits {
        try .init(maximumGeneratedCells:20000,maximumRootsPerStack:100,maximumClosures:20000,maximumAttachmentPieces:100000,maximumComponents:1000)
    }
    nonisolated static func ledger() throws -> ExactScalarLedger {
        .init(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
    }
    nonisolated static func interval(_ lo:Int,_ hi:Int,_ f:Field,_ a:inout ExactScalarLedger,denominator:Int = 1) throws -> ExactParameterInterval<Field.Value> {
        try .checked(field:f,lower:.finite(f.dividing(f.integer(lo,using:&a),f.integer(denominator,using:&a),using:&a)),upper:.finite(f.dividing(f.integer(hi,using:&a),f.integer(denominator,using:&a),using:&a)),
            includesLower:true,includesUpper:true,depth:.init(value:0,coefficient:0),using:&a)
    }
    nonisolated static func prepare(_ a:inout ExactScalarLedger) throws -> (Raw,OriginalParameterIdentity<BSplineSurface3D,Field>) {
        let f = try Field.base(field:Base(),maximumExtensionLevel:10,using:&a),l = try limits()
        let folded = BSplineSurface3D(uDegree:2,vDegree:1,uKnots:[-1,-1,-1,1,1,1],vKnots:[-1,-1,1,1],
            controlPoints:[[.init(x:1,y:-1,z:0),.init(x:-1,y:-1,z:0),.init(x:1,y:-1,z:0)],
                [.init(x:1,y:1,z:0),.init(x:-1,y:1,z:0),.init(x:1,y:1,z:0)]])
        let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:.standard))
            .bind(folded,limits:l.source,using:&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let space = try issuer.prepare(source:source,field:f,limits:l,using:&a)
        let cover = try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let raw = try DefaultSurfaceSurfaceIntersector().exactParameterRelations(first:cover,second:cover,domainLimits:l,
            maximumMaps:64,maximumPairs:4096,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        try require(raw.pieces.count == 1)
        let piece = raw.pieces[0],law = piece.first.law
        try require(piece.relation.original.kind == .surfaceSurface)
        let scope = try space.frame.selection(intervals:[[interval(-1,-1,f,&a)],[interval(-1,1,f,&a)]],limits:l,using:&a)
        let declaration = OriginalSourceBoundaryDeclaration(left:law.chart,right:law.chart,leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let ids = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        let proof = try ids.declaredBoundary(declaration:declaration,left:law,right:law,scope:scope,rightFrame:space.frame,
            permutation:[0,1],gains:[f.integer(1,using:&a),f.integer(1,using:&a)],offsets:[f.integer(2,using:&a),f.integer(0,using:&a)],limits:l,using:&a)
        let view = try ids.relation(of:proof,limits:l,using:&a)
        try require(view.kind == .declaredSharedBoundary)
        guard case .affine(let permutation,let gains,let offsets) = view.constraints else { throw Failure.assertion(#line) }
        try require(permutation == [0,1])
        for axis in 0..<2 {
            try require(f.compare(gains[axis],f.integer(1,using:&a),using:&a) == .equal)
            try require(f.compare(offsets[axis],f.integer(axis == 0 ? 2:0,using:&a),using:&a) == .equal)
        }
        for map in [piece.relation.original.first,piece.relation.original.second] {
            let c = try Cells(retaining:map.original,using:&a),ring = c.polynomials
            let u = try ring.variable(0,using:&a),v = try ring.variable(1,using:&a)
            let expected = [try ring.multiplying(u,u,using:&a),v,try ring.zero(using:&a),try ring.constant(f.integer(1,using:&a),using:&a)]
            try require(map.parameterCount == 2 && map.original.polynomials.count == 4)
            for i in 0..<4 { try require(ring.equals(map.original.polynomials[i],expected[i],using:&a)) }
            for d in map.original.domains {
                guard case .finite(let lo) = d.lower,case .finite(let hi) = d.upper else { throw Failure.assertion(#line) }
                try require(d.includesLower && d.includesUpper && f.compare(lo,f.integer(-1,using:&a),using:&a) == .equal && f.compare(hi,f.integer(1,using:&a),using:&a) == .equal)
            }
        }
        marker("PASS exact original fold, once-bound same owner, one chart/pair and checked whole closed directed edge")
        let leftCut = try space.frame.selection(intervals:[[interval(-1,-1,f,&a)],
            [interval(-2,1,f,&a,denominator:2)]],limits:l,using:&a)
        let rightCut = try space.frame.selection(intervals:[[interval(1,1,f,&a)],
            [interval(-1,2,f,&a,denominator:2)]],limits:l,using:&a)
        let restricted = try ids.restricted(proof,left:leftCut,right:rightCut,limits:l,using:&a)
        let symmetric = try ids.symmetric(proof,limits:l,using:&a)
        let intermediate = try ids.compose(symmetric,restricted,limits:l,using:&a)
        let composed = try ids.compose(intermediate,symmetric,limits:l,using:&a)
        try identity(restricted,leftU:-1,rightU:1,lowerV:-1,upperV:1,denominator:2,
            offset:2,depth:1,count:1,f,&a)
        try identity(symmetric,leftU:1,rightU:-1,lowerV:-1,upperV:1,denominator:1,
            offset:-2,depth:1,count:1,f,&a)
        try identity(intermediate,leftU:1,rightU:1,lowerV:-1,upperV:1,denominator:2,
            offset:0,depth:2,count:3,f,&a)
        try identity(composed,leftU:1,rightU:-1,lowerV:-1,upperV:1,denominator:2,
            offset:-2,depth:3,count:5,f,&a)
        marker("PASS actual E/R/S/I/C: middle intersection and full pullback, reverse closed J, depth3/proofCount5")
        return (raw,composed)
    }
    nonisolated static func identity(_ receipt:OriginalParameterIdentity<BSplineSurface3D,Field>,
        leftU:Int,rightU:Int,lowerV:Int,upperV:Int,denominator:Int,offset:Int,depth:Int,count:Int,
        _ f:Field,_ a:inout ExactScalarLedger) throws {
        let ids = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        let view = try ids.relation(of:receipt,limits:limits(),using:&a)
        try require(view.kind == .declaredSharedBoundary && view.depth == depth && view.proofCount == count)
        try require(view.left.sharesFrame(with:receipt.left) && view.right.sharesFrame(with:receipt.right))
        guard case .affine(let p,let g,let o) = view.constraints else { throw Failure.assertion(#line) }
        try require(p == [0,1])
        for axis in 0..<2 {
            try require(f.compare(g[axis],f.integer(1,using:&a),using:&a) == .equal)
            try require(f.compare(o[axis],f.integer(axis == 0 ? offset:0,using:&a),using:&a) == .equal)
        }
        for (selection,u) in [(view.left,leftU),(view.right,rightU)] {
            try require(selection.arity == 2 && selection.axes[0].intervalCount == 1 && selection.axes[1].intervalCount == 1)
            let expected = [try interval(u,u,f,&a),try interval(lowerV,upperV,f,&a,denominator:denominator)]
            for axis in 0..<2 {
                let actual = selection.axes[axis].intervals.first!
                guard case .finite(let lo) = actual.lower,case .finite(let hi) = actual.upper,
                    case .finite(let elo) = expected[axis].lower,case .finite(let ehi) = expected[axis].upper else { throw Failure.assertion(#line) }
                try require(actual.includesLower && actual.includesUpper)
                try require(f.compare(lo,elo,using:&a) == .equal && f.compare(hi,ehi,using:&a) == .equal)
            }
        }
    }
    nonisolated static func invariants(_ p:ExactRealCellPartition<Base>,refined:Bool,_ a:inout ExactScalarLedger) throws -> (Cells,[ExactRealCellSignInvariant<Base>]) {
        let c = try Cells(retaining:p.source,using:&a),r = c.polynomials
        let f = try c.coefficientField(of:p.source,using:&a)
        try require(p.source.variableCount == 4)
        let u = try r.variable(0,using:&a),v = try r.variable(1,using:&a),s = try r.variable(2,using:&a),w = try r.variable(3,using:&a)
        var laws = [try r.subtracting(r.multiplying(u,u,using:&a),r.multiplying(s,s,using:&a),using:&a),try r.subtracting(v,w,using:&a)]
        if refined {
            laws.append(try r.subtracting(u,s,using:&a))
            laws.append(try r.subtracting(u,r.constant(f.integer(1,using:&a),using:&a),using:&a))
            let half = try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
            laws.append(try r.subtracting(v,r.constant(f.negated(half,using:&a),using:&a),using:&a))
            laws.append(try r.subtracting(v,r.constant(half,using:&a),using:&a))
        }
        var proofs:[ExactRealCellSignInvariant<Base>] = []
        for (i,law) in laws.enumerated() {
            guard let proof = try c.signInvariant(for:law,in:p,using:&a) else { metric("MISSING whole-cell invariant",[refined ? 1:0,i]);throw Failure.assertion(#line) }
            proofs.append(proof)
        }
        return (c,proofs)
    }
    nonisolated static func oracle(_ result:Result,_ a:inout ExactScalarLedger) throws {
        let raw = result.raw,piece = raw.pieces[0],selected = piece.relation.selection
        try require(raw.pieces.count == 1 && result.refinements.count == 1 && result.identities.count == 2)
        let (c,proofs) = try invariants(selected.partition,refined:false,&a)
        var rawCount = 0,rawDimension = -1
        for cell in selected.partition.cells where cell.axis == 3 {
            let signs = try proofs.map { try c.sign(of:$0,at:cell,using:&a) }
            let expected = signs[0] == .zero && signs[1] == .zero
            try require(selected.cells.contains(cell) == expected)
            if expected { rawCount += 1;rawDimension = max(rawDimension,cell.dimension) }
        }
        try require(rawCount == selected.cells.count && rawDimension == 2)
        let pb = result.refinements[0].pullback,region = pb.region
        try require(pb.coordinateMap == [0,1,2,3] && pb.source.cells.count == selected.cells.count)
        for i in selected.cells.indices { try require(pb.source.cells[i] == selected.cells[i]) }
        try require(region.cells.count == region.included.count && region.cells.count == pb.sourceCellOrdinals.count)
        let (rc,rp) = try invariants(region.partition,refined:true,&a)
        var checked = 0,included = 0,dimension = -1
        for cell in region.partition.cells where cell.axis == 3 {
            let indices = region.cells.indices.filter { region.cells[$0] == cell }
            try require(indices.count == 1)
            let i = indices[0],signs = try rp.map { try rc.sign(of:$0,at:cell,using:&a) }
            let expected = signs[0] == .zero && signs[1] == .zero && signs[2] != .zero && !(signs[3] == .zero && signs[4] != .negative && signs[5] != .positive)
            try require(region.included[i] == expected)
            let ordinal = pb.sourceCellOrdinals[i]
            try require(expected ? selected.cells.indices.contains(ordinal):ordinal == -1)
            if expected { included += 1;dimension = max(dimension,cell.dimension) }
            checked += 1
        }
        try require(checked == region.cells.count && included > 0 && dimension == 2)
        metric("METRIC raw/refined/included/work/bytes",[rawCount,checked,included,a.work,a.storageBytes])
        marker("PASS every terminal raw/refined iff: (u,v,-u,v), u!=0, NOT(u=1 AND -1/2<=v<=1/2); alignment/range retained, image2/fiber0 is oracle meaning")
    }
    struct PublicationAdmission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var storageCalls = 0
        let cancellingCall: Int?
        init(cancellingCall:Int? = nil) throws {
            ledger = try NativeIdentityCompositionAcceptance.ledger();self.cancellingCall = cancellingCall
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes:Int) throws(ExactScalarFailure) {
            try ledger.retainStorage(bytes:bytes);storageCalls += 1
            if storageCalls == cancellingCall { ledger.cancel() }
        }
        mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    nonisolated static func query<A:ExactScalarAdmission & ~Copyable>(_ raw:Raw,_ c:OriginalParameterIdentity<BSplineSurface3D,Field>,_ a:inout A) throws -> Result {
        try NativeDeclaredWholeEdgeSelf.DefaultOriginalExactNativeSelfContactQuery().contacts(in:raw,excluding:[c],
            domainLimits:limits(),cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
    }
    nonisolated static func retained() throws -> (Result,Int,Int,Int) {
        var preparation = try ledger()
        let (raw,c) = try prepare(&preparation)
        var queryAdmission = try PublicationAdmission()
        let result = try query(raw,c,&queryAdmission)
        return (result,queryAdmission.ledger.work,queryAdmission.ledger.storageBytes,queryAdmission.storageCalls)
    }
    nonisolated static func tuples(_ result:Result,_ a:inout ExactScalarLedger) throws {
        let f = result.raw.first.space.frame.scalarField,c = result.identities[1]
        let ids = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        for numerator in [-2,-1,0,1,2] {
            let v = try f.dividing(f.integer(numerator,using:&a),f.integer(2,using:&a),using:&a)
            let left = [try f.integer(-1,using:&a),v],right = [try f.integer(1,using:&a),v]
            try require(result.contains(firstTuple:left,secondTuple:right,domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a))
            try require(result.contains(firstTuple:right,secondTuple:left,domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a) == (numerator < -1 || numerator > 1))
            let decision = try ids.decide(c,left:right,right:left,limits:limits(),using:&a)
            switch decision {
            case .proven:try require(numerator >= -1 && numerator <= 1)
            case .notEstablished:try require(numerator < -1 || numerator > 1)
            default:throw Failure.assertion(#line)
            }
        }
        marker("PASS released parents/result retention: closed J endpoints removed only in reverse direction; scope-exterior and every forward edge tuple retained")
    }
    nonisolated static func controls() throws {
        let (result,n,bytes,calls) = try retained()
        metric("METRIC preparedQueryBoundary",[n,bytes,calls])
        var a = try ledger()
        try tuples(result,&a)
        let c = result.identities[1],raw = result.raw,f = raw.first.space.frame.scalarField
        let ids = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        let admitted = try ids.relation(of:c,limits:limits(depth:3,count:5),using:&a)
        try require(admitted.kind == .declaredSharedBoundary && admitted.depth == 3 && admitted.proofCount == 5)
        for mode in 0..<2 {
            do {
                _ = try ids.relation(of:c,limits:limits(depth:mode == 0 ? 2:3,count:mode == 1 ? 4:5),using:&a)
                throw Failure.unexpectedSuccess
            } catch let failure as OriginalDomainIdentityFailure {
                switch (mode,failure) {
                case (0,.transportDepthLimit),(1,.identityLimit):break
                default:throw failure
                }
            }
        }
        let foreign = try DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>().prepare(source:raw.first.source,field:f,limits:limits(),using:&a)
        try require(!foreign.frame.fullSelection(limits:limits(),using:&a).sharesFrame(with:c.left))
        let law = raw.pieces[0].first.law
        let scope = try foreign.frame.selection(intervals:[[interval(-1,-1,f,&a)],[interval(-1,1,f,&a)]],limits:limits(),using:&a)
        let declaration = OriginalSourceBoundaryDeclaration(left:law.chart,right:law.chart,leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let foreignE = try ids.declaredBoundary(declaration:declaration,left:law,right:law,scope:scope,rightFrame:foreign.frame,
            permutation:[0,1],gains:[f.integer(1,using:&a),f.integer(1,using:&a)],offsets:[f.integer(2,using:&a),f.integer(0,using:&a)],limits:limits(),using:&a)
        do { _ = try ids.compose(c,foreignE,limits:limits(),using:&a);throw Failure.unexpectedSuccess }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        marker("PASS depth3/count5 exact readmission and depth2/count4 typed refusal; equal-field same-source independently prepared middle frame refused")
    }
    nonisolated static func boundary(_ group:String,n:Int,bytes:Int,calls:Int) throws {
        try require(n > 0 && bytes > 0 && calls > 0)
        var preparation = try ledger()
        let (raw,c) = try prepare(&preparation)
        if group == "cancel" {
            var entry = try ledger();entry.cancel()
            do { _ = try query(raw,c,&entry);throw Failure.unexpectedSuccess }
            catch NativeExactRelationFailure.scalar(.cancelled) {}
            var final = try PublicationAdmission(cancellingCall:calls)
            do { _ = try query(raw,c,&final);throw Failure.unexpectedSuccess }
            catch NativeExactRelationFailure.scalar(.cancelled) {}
            try require(final.storageCalls == calls && final.ledger.work == n && final.ledger.storageBytes == bytes)
            marker("PASS entry and final-publication checkpoint cancellation; no successful partial result")
            return
        }
        var a = ExactScalarLedger(limits:try .init(work:group == "work" ? n-1:n,
            storageBytes:group == "storage" ? bytes-1:bytes,valueDepth:32,coefficientDepth:32))
        if group == "exact" {
            let result = try query(raw,c,&a)
            try require(a.work == n && a.storageBytes == bytes)
            var oracleAdmission = try ledger()
            try oracle(result,&oracleAdmission)
            marker("PASS independent prepared query exact workN/storageN; whole-cell oracle uses separate ledger")
        } else {
            do { _ = try query(raw,c,&a);throw Failure.unexpectedSuccess }
            catch let failure as NativeExactRelationFailure {
                switch (group,failure) {
                case ("work",.scalar(.resourceLimit(.work))),("work",.domain(.scalar(.resourceLimit(.work)))),
                     ("storage",.scalar(.resourceLimit(.storage))),("storage",.domain(.scalar(.resourceLimit(.storage)))):break
                default:throw failure
                }
            }
            marker(group == "work" ? "PASS workN-1 exact typed work refusal" : "PASS storageN-1 exact typed storage refusal")
        }
    }
    nonisolated static func run() throws {
#if hasFeature(Embedded)
        let argument:String
        if let pointer = getenv("CAD_PROOF_GROUP") { argument = String(cString:pointer) }
        else { argument = "complete" }
#else
        let argument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]:"complete"
#endif
        let fields = argument.split(separator:":"),group = String(fields[0])
        if group == "controls" { try controls();return }
        if ["exact","work","storage","cancel"].contains(group) {
            try require(fields.count == 4)
            guard let n = Int(fields[1]),let bytes = Int(fields[2]),let calls = Int(fields[3]) else { throw Failure.assertion(#line) }
            try boundary(group,n:n,bytes:bytes,calls:calls);return
        }
        try require(group == "complete")
        var a = try ledger()
        marker("START S-NATIVE-IDENTITY-COMPOSITION-01 one complete original-domain public query")
        let (raw,c) = try prepare(&a)
        metric("METRIC preparationWork/storage",[a.work,a.storageBytes])
        let result = try query(raw,c,&a)
        metric("METRIC publicReturnWork/storage",[a.work,a.storageBytes])
        try require(result.identities.count == 2 && result.identities[1].depth == 3 && result.identities[1].proofCount == 5)
        var oracleAdmission = try ledger();try oracle(result,&oracleAdmission)
    }
    nonisolated static func main() {
        do { try run() }
        catch {
#if !hasFeature(Embedded)
            print("OBSERVED STOP S-NATIVE-IDENTITY-COMPOSITION-01",error)
#else
            marker("OBSERVED STOP S-NATIVE-IDENTITY-COMPOSITION-01")
#endif
            fflush(nil);exit(2)
        }
    }
}
