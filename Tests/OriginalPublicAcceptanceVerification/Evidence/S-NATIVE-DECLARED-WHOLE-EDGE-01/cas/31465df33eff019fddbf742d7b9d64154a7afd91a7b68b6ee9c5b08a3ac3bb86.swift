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

/// Whole-cell oracle for one directed declaration on the original quadratic fold.
@main struct NativeDeclaredWholeEdgeAcceptance {
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Cells = ExactRealCellDomain<Base>
    typealias Raw = NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>
    typealias Result = NativeDeclaredWholeEdgeSelf.OriginalExactNativeSelfContacts
    enum Failure: Error { case assertion(Int), unexpectedSuccess }
    static func require(_ value: Bool, _ line: Int = #line) throws {
        guard value else { metric("FAIL S-NATIVE-DECLARED-WHOLE-EDGE-01",[line]); throw Failure.assertion(line) }
    }
    static func marker(_ text: StaticString) { print(text); fflush(nil) }
    static func digits(_ value:Int) {
        if value >= 10 { digits(value/10) }
        _ = putchar(Int32(48+value%10))
    }
    static func metric(_ text:StaticString,_ values:[Int]) {
        print(text,terminator:" ")
        for value in values { digits(value);_ = putchar(32) }
        _ = putchar(10);fflush(nil)
    }
    static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:0),maximumTransportDepth:16,maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:64)
    }
    static func cellLimits() throws -> ExactRealCellLimits { try .init(maximumStoredCells:20000,maximumRootsPerStack:100) }
    static func topologyLimits() throws -> ExactRealTopologyLimits {
        try .init(maximumGeneratedCells:20000,maximumRootsPerStack:100,maximumClosures:20000,maximumAttachmentPieces:100000,maximumComponents:1000)
    }
    static func ledger() throws -> ExactScalarLedger {
        .init(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
    }
    static func interval(_ lo:Int,_ hi:Int,_ f:Field,_ a:inout ExactScalarLedger) throws -> ExactParameterInterval<Field.Value> {
        try .checked(field:f,lower:.finite(f.integer(lo,using:&a)),upper:.finite(f.integer(hi,using:&a)),
            includesLower:true,includesUpper:true,depth:.init(value:0,coefficient:0),using:&a)
    }
    static func prepare(_ a:inout ExactScalarLedger) throws -> (Raw,OriginalParameterIdentity<BSplineSurface3D,Field>) {
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
        return (raw,proof)
    }
    static func invariants(_ p:ExactRealCellPartition<Base>,refined:Bool,half:Bool = false,_ a:inout ExactScalarLedger) throws -> (Cells,[ExactRealCellSignInvariant<Base>]) {
        let c = try Cells(retaining:p.source,using:&a),r = c.polynomials
        let f = try c.coefficientField(of:p.source,using:&a)
        try require(p.source.variableCount == 4)
        let u = try r.variable(0,using:&a),v = try r.variable(1,using:&a),s = try r.variable(2,using:&a),w = try r.variable(3,using:&a)
        var laws = [try r.subtracting(r.multiplying(u,u,using:&a),r.multiplying(s,s,using:&a),using:&a),try r.subtracting(v,w,using:&a)]
        if refined {
            laws.append(try r.subtracting(u,s,using:&a))
            laws.append(try r.adding(u,r.constant(f.integer(1,using:&a),using:&a),using:&a))
        }
        if half { laws.append(v) }
        var proofs:[ExactRealCellSignInvariant<Base>] = []
        for (i,law) in laws.enumerated() {
            guard let proof = try c.signInvariant(for:law,in:p,using:&a) else { metric("MISSING whole-cell invariant",[refined ? 1:0,i]);throw Failure.assertion(#line) }
            proofs.append(proof)
        }
        return (c,proofs)
    }
    static func oracle(_ result:Result,half:Bool = false,_ a:inout ExactScalarLedger) throws {
        let raw = result.raw,piece = raw.pieces[0],selected = piece.relation.selection
        try require(raw.pieces.count == 1 && result.refinements.count == 1 && result.identities.count == 2)
        let (c,proofs) = try invariants(selected.partition,refined:false,&a)
        var rawCount = 0,rawDimension = -1,rawSignatures:[[ExactSign]] = []
        for cell in selected.partition.cells where cell.axis == 3 {
            let signs = try proofs.map { try c.sign(of:$0,at:cell,using:&a) }
            let expected = signs[0] == .zero && signs[1] == .zero
            try require(selected.cells.contains(cell) == expected)
            if expected { rawCount += 1;rawDimension = max(rawDimension,cell.dimension) }
        }
        try require(rawCount == selected.cells.count && rawDimension == 2)
        for cell in selected.cells { rawSignatures.append(try proofs.map { try c.sign(of:$0,at:cell,using:&a) }) }
        let pb = result.refinements[0].pullback,region = pb.region
        try require(pb.coordinateMap == [0,1,2,3] && pb.source.cells.count == selected.cells.count)
        for i in selected.cells.indices { try require(pb.source.cells[i] == selected.cells[i]) }
        try require(region.cells.count == region.included.count && region.cells.count == pb.sourceCellOrdinals.count)
        let (rc,rp) = try invariants(region.partition,refined:true,half:half,&a)
        var checked = 0,included = 0,dimension = -1
        for cell in region.partition.cells where cell.axis == 3 {
            let indices = region.cells.indices.filter { region.cells[$0] == cell }
            try require(indices.count == 1)
            let i = indices[0],signs = try rp.map { try rc.sign(of:$0,at:cell,using:&a) }
            let expected = signs[0] == .zero && signs[1] == .zero && signs[2] != .zero && (signs[3] == .positive || half && signs[4] == .positive)
            try require(region.included[i] == expected)
            let ordinal = pb.sourceCellOrdinals[i]
            try require(expected ? selected.cells.indices.contains(ordinal):ordinal == -1)
            if expected { try require(rawSignatures[ordinal] == Array(signs.prefix(2)));included += 1;dimension = max(dimension,cell.dimension) }
            checked += 1
        }
        try require(checked == region.cells.count && included > 0 && dimension == 2)
        metric("METRIC raw/refined/included/work/bytes",[rawCount,checked,included,a.work,a.storageBytes])
        marker(half ? "PASS complete half-scope oracle preserves undeclared positive-V forward edge" : "PASS complete raw/refined iff and every ordinal: (u,v,-u,v), -1<u<=1, u!=0, closed V; image2/fiber0 is oracle meaning")
    }
    struct PublicationAdmission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var storageCalls = 0
        let cancellingCall: Int?
        init(cancellingCall:Int? = nil) throws { ledger = try NativeDeclaredWholeEdgeAcceptance.ledger();self.cancellingCall = cancellingCall }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes:Int) throws(ExactScalarFailure) {
            try ledger.retainStorage(bytes:bytes);storageCalls += 1
            if storageCalls == cancellingCall { ledger.cancel() }
        }
        mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    static func query<A:ExactScalarAdmission & ~Copyable>(_ raw:Raw,_ proof:OriginalParameterIdentity<BSplineSurface3D,Field>?,_ a:inout A) throws -> Result {
        try NativeDeclaredWholeEdgeSelf.DefaultOriginalExactNativeSelfContactQuery().contacts(in:raw,excluding:proof.map { [$0] } ?? [],
            domainLimits:limits(),cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
    }
    static func retained() throws -> (Result,Int) {
        var preparation = try ledger()
        let (raw,proof) = try prepare(&preparation)
        var admission = try PublicationAdmission()
        let result = try query(raw,proof,&admission)
        metric("METRIC independentPreparedQuery work/bytes/storageCalls",[admission.ledger.work,admission.ledger.storageBytes,admission.storageCalls])
        return (result,admission.storageCalls)
    }
    static func controls() throws {
        let (result,storageCalls) = try retained()
        var a = try ledger()
        try oracle(result,&a)
        marker("PASS complete oracle after source/frame/construction/query admission scope release")
        let raw = result.raw,proof = result.identities[1],f = raw.first.space.frame.scalarField
        for v in [-1,0,1] {
            let x = try f.integer(-1,using:&a),y = try f.integer(1,using:&a),w = try f.integer(v,using:&a)
            try require(!result.contains(firstTuple:[x,w],secondTuple:[y,w],domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a))
            try require(result.contains(firstTuple:[y,w],secondTuple:[x,w],domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a))
        }
        marker("PASS directed exclusion and retained reverse edge at both closed V corners and interior")
        for mode in 0..<3 {
            var refusal = ExactScalarLedger(limits:try .init(work:mode == 0 ? 0:80_000_000,storageBytes:mode == 1 ? 0:1_073_741_824,valueDepth:32,coefficientDepth:32))
            if mode == 2 { refusal.cancel() }
            do { _ = try query(raw,proof,&refusal);throw Failure.unexpectedSuccess }
            catch let e as NativeExactRelationFailure {
                switch (mode,e) {
                case (0,.scalar(.resourceLimit(.work))),(0,.domain(.scalar(.resourceLimit(.work)))),
                     (1,.scalar(.resourceLimit(.storage))),(1,.domain(.scalar(.resourceLimit(.storage)))),
                     (2,.scalar(.cancelled)):break
                default:throw e
                }
            }
        }
        var final = try PublicationAdmission(cancellingCall:storageCalls)
        do { _ = try query(raw,proof,&final);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        marker("PASS prepared-query zero work/storage causes and entry/final-publication cancellation; whole-cost N/N-1 unmeasured")
        let law = raw.pieces[0].first.law,frame = raw.first.space.frame,l = try limits()
        let ids = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        let declaration = OriginalSourceBoundaryDeclaration(left:law.chart,right:law.chart,leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let scope = try frame.selection(intervals:[[interval(-1,-1,f,&a)],[interval(-1,1,f,&a)]],limits:l,using:&a)
        do {
            _ = try ids.declaredBoundary(declaration:declaration,left:law,right:law,scope:scope,rightFrame:frame,
                permutation:[0,1],gains:[f.integer(1,using:&a),f.integer(-1,using:&a)],offsets:[f.integer(2,using:&a),f.integer(0,using:&a)],limits:l,using:&a)
            throw Failure.unexpectedSuccess
        } catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        let derivative = try law.polynomials.differentiated(law.homogeneous[0],in:0,using:&a)
        let twoU = try law.polynomials.scaled(law.polynomials.variable(0,using:&a),by:f.integer(2,using:&a),using:&a)
        try require(law.polynomials.equals(derivative,twoU,using:&a))
        try require(f.compare(f.integer(-2,using:&a),f.integer(2,using:&a),using:&a) == .less)
        marker("PASS V reversal rejected by whole-law issuer; exact opposite Gu proves position receipt cannot establish common derivative/normal germ")
        let half = try frame.selection(intervals:[[interval(-1,-1,f,&a)],[interval(-1,0,f,&a)]],limits:l,using:&a)
        let halfProof = try ids.declaredBoundary(declaration:declaration,left:law,right:law,scope:half,rightFrame:frame,
            permutation:[0,1],gains:[f.integer(1,using:&a),f.integer(1,using:&a)],offsets:[f.integer(2,using:&a),f.integer(0,using:&a)],limits:l,using:&a)
        let halfResult = try query(raw,halfProof,&a)
        try oracle(halfResult,half:true,&a)
        let outside = try frame.selection(intervals:[[interval(2,2,f,&a)],[interval(-1,1,f,&a)]],limits:l,using:&a)
        let cover = try DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>().issue(space:raw.first.space,request:outside,limits:l,using:&a)
        let emptyRaw = try DefaultSurfaceSurfaceIntersector().exactParameterRelations(first:cover,second:cover,domainLimits:l,
            maximumMaps:64,maximumPairs:4096,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        try require(emptyRaw.pieces.isEmpty)
        var emptyAdmission = try PublicationAdmission()
        let empty = try query(emptyRaw,nil,&emptyAdmission)
        try require(empty.raw.pieces.isEmpty && empty.refinements.isEmpty && empty.identities.count == 1)
        var emptyFinal = try PublicationAdmission(cancellingCall:emptyAdmission.storageCalls)
        do { _ = try query(emptyRaw,nil,&emptyFinal);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        marker("PASS complete out-of-support empty publication and its final cancellation")
    }
    static func resources() throws {
        var preparation = try ledger()
        let (raw,proof) = try prepare(&preparation)
        var calibration = try ledger()
        let calibrated = try query(raw,proof,&calibration)
        let n = calibration.work,bytes = calibration.storageBytes
        try require(n > 0 && bytes > 0 && calibrated.refinements.count == 1)
        metric("METRIC independentPreparedQueryBoundary",[n,bytes])
        var exact = ExactScalarLedger(limits:try .init(work:n,storageBytes:bytes,valueDepth:32,coefficientDepth:32))
        let result = try query(raw,proof,&exact)
        try require(exact.work == n && exact.storageBytes == bytes)
        var oracleAdmission = try ledger()
        try oracle(result,&oracleAdmission)
        for mode in 0..<2 {
            var insufficient = ExactScalarLedger(limits:try .init(work:mode == 0 ? n-1:n,storageBytes:mode == 1 ? bytes-1:bytes,valueDepth:32,coefficientDepth:32))
            do { _ = try query(raw,proof,&insufficient);throw Failure.unexpectedSuccess }
            catch let failure as NativeExactRelationFailure {
                switch (mode,failure) {
                case (0,.scalar(.resourceLimit(.work))),(0,.domain(.scalar(.resourceLimit(.work)))),
                     (1,.scalar(.resourceLimit(.storage))),(1,.domain(.scalar(.resourceLimit(.storage)))):break
                default:throw failure
                }
            }
        }
        marker("PASS independent retained-raw prepared-query exact work/storage N and separate workN-1/storageN-1 typed refusal; oracle ledger excluded")
    }
    static func main() throws {
#if hasFeature(Embedded)
        let group = getenv("CAD_PROOF_GROUP").map { String(cString:$0) } ?? "complete"
#else
        let group = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]:"complete"
#endif
        if group == "controls" || group == "all" { try controls() }
        if group == "resources" || group == "all" { try resources() }
        if group == "complete" || group == "all" {
            var a = try ledger()
            marker("START S-NATIVE-DECLARED-WHOLE-EDGE-01 actual Native whole-edge query")
            let (raw,proof) = try prepare(&a)
            metric("METRIC preparation",[a.work,a.storageBytes])
            let result = try query(raw,proof,&a)
            metric("METRIC publicReturn",[a.work,a.storageBytes])
            try oracle(result,&a)
        }
        try require(["complete","controls","resources","all"].contains(group))
    }
}
