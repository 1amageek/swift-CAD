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
    static func require(_ value: Bool, _ line: Int = #line) throws {
        guard value else { metric("FAIL S-NATIVE-IDENTITY-COMPOSITION-01",[line]); throw Failure.assertion(line) }
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
    static func interval(_ lo:Int,_ hi:Int,_ f:Field,_ a:inout ExactScalarLedger,denominator:Int = 1) throws -> ExactParameterInterval<Field.Value> {
        try .checked(field:f,lower:.finite(f.dividing(f.integer(lo,using:&a),f.integer(denominator,using:&a),using:&a)),upper:.finite(f.dividing(f.integer(hi,using:&a),f.integer(denominator,using:&a),using:&a)),
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
    static func identity(_ receipt:OriginalParameterIdentity<BSplineSurface3D,Field>,
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
    static func invariants(_ p:ExactRealCellPartition<Base>,refined:Bool,_ a:inout ExactScalarLedger) throws -> (Cells,[ExactRealCellSignInvariant<Base>]) {
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
    static func oracle(_ result:Result,_ a:inout ExactScalarLedger) throws {
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
    static func main() {
        do {
            var a = try ledger()
            marker("START S-NATIVE-IDENTITY-COMPOSITION-01 one complete original-domain public query")
            let (raw,composed) = try prepare(&a)
            metric("METRIC preparationWork/storage",[a.work,a.storageBytes])
            let result = try NativeDeclaredWholeEdgeSelf.DefaultOriginalExactNativeSelfContactQuery().contacts(
                in:raw,excluding:[composed],domainLimits:limits(),cellLimits:cellLimits(),
                topologyLimits:topologyLimits(),using:&a)
            metric("METRIC publicReturnWork/storage",[a.work,a.storageBytes])
            try require(result.identities.count == 2 && result.identities[1].depth == 3 && result.identities[1].proofCount == 5)
            var oracleAdmission = try ledger()
            try oracle(result,&oracleAdmission)
        } catch {
            print("OBSERVED STOP S-NATIVE-IDENTITY-COMPOSITION-01",error);fflush(nil);exit(2)
        }
    }
}
