import L0
import L1
import DI0
import DI
import SourceIssuer

struct PairedImage<C: Sendable>: OriginalParameterImageSourceReading {
    let originalChild: OriginalSourceBinding<C>
    let gains: [Int],offsets: [Int],axes: [Int]
    var spatial: [Int]? = nil
    var delta: Double = 0
    var parameterCount: Int { gains.count }
    var hasSpatialAction: Bool { spatial != nil || delta != 0 }
    func childAxis(forOriginalAxis axis: Int) -> Int { axes[axis] }
    func originalGain<F: ExactScalarArithmetic & ExactScalarOrdering,A: ExactScalarAdmission & ~Copyable>(in axis: Int,field: borrowing F,using a: inout A) throws(OriginalSourceIssuanceFailure) -> F.Value {
        do { return try field.integer(gains[axis],using:&a) } catch { throw .scalar(error) }
    }
    func originalOffset<F: ExactScalarArithmetic & ExactScalarOrdering,A: ExactScalarAdmission & ~Copyable>(in axis: Int,field: borrowing F,using a: inout A) throws(OriginalSourceIssuanceFailure) -> F.Value {
        do { return try field.integer(offsets[axis],using:&a) } catch { throw .scalar(error) }
    }
    func originalSpatialCoefficient<F: ExactScalarArithmetic & ExactScalarOrdering,A: ExactScalarAdmission & ~Copyable>(row: Int,column: Int,field: borrowing F,using a: inout A) throws(OriginalSourceIssuanceFailure) -> F.Value {
        do {
            let base = try field.integer(spatial?[row*4+column] ?? (row == column ? 1:0),using:&a)
            if row == 0 && column == 3 { return try field.adding(base,field.binary64(exactly:delta,using:&a),using:&a) }
            return base
        } catch { throw .scalar(error) }
    }
}

struct PairedSpatial<C: Sendable>: OriginalSpatialSourceReading {
    let originalChild: OriginalSourceBinding<C>
    let values: [ExactRationalCoefficient]
    func spatialCoefficient(row: Int,column: Int) -> ExactRationalCoefficient { values[row*4+column] }
}

enum AffinePairedIdentityProof {
    typealias F = ExactRationalScalarDomain
    typealias Family = OriginalBSplineDomainCover<NativeSnapshot,F>
    typealias Parent = PairedImage<NativeSnapshot>
    typealias Cover = OriginalAffineChildDomainCover<Parent,Family>
    typealias Receipt = OriginalParameterIdentity<Parent,F>
    typealias ChildReceipt = OriginalParameterIdentity<NativeSnapshot,F>
    typealias Action = OriginalSourceAffineActionReceipt<Parent,F>
    static let matrix = [2,0,0,5,0,-3,0,7,0,0,1,-2]
    static func family(_ controls: [[Double]],depth: Int = 0,_ a: inout ExactScalarLedger) throws -> Family {
        let l = try TransportFixtures.limits(),f = F()
        let s = try IdentityFixtures.bind(.init(degrees:[1,1],knots:[[0,0,1,1],[0,0,1,1]],counts:[2,2],controls:controls,weights:[1,1,1,1],periodic:[false,false],sourceDepth:depth),&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,F>()
        let space = try issuer.prepare(source:s,field:f,limits:l,using:&a)
        return try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
    }
    static func children(swapped: Bool = false,_ a: inout ExactScalarLedger) throws -> (ChildReceipt,Family,Family) {
        let l = try TransportFixtures.limits(),f = F(),ids = DefaultOriginalParameterIdentityIssuer<NativeSnapshot,F>()
        let left = try family(swapped ? [[0,0,0],[1,0,0],[1,0,0],[2,1,0]]:[[0,0,0],[1,0,0],[0,1,0],[1,1,0]],&a)
        let right = try family(swapped ? [[0,0,0],[1,0,0],[1,0,0],[3,2,0]]:[[1,0,0],[0,0,0],[1,-2,0],[0,-2,0]],depth:3,&a)
        let producer = DefaultOriginalBSplineChartIssuer<NativeSnapshot,F>()
        let ll = try producer.issue(source:left.source,chart:left.space.sourceCharts[0],field:f,limits:l.source,using:&a)
        let rr = try producer.issue(source:right.source,chart:right.space.sourceCharts[0],field:f,limits:l.source,using:&a)
        let scope = try left.support.frame.selection(intervals:swapped ? [[TransportFixtures.interval(0,0,using:&a)],[TransportFixtures.interval(0,1,using:&a)]]:[[TransportFixtures.interval(0,1,using:&a)],[TransportFixtures.interval(0,0,using:&a)]],limits:l,using:&a)
        let declaration = OriginalSourceBoundaryDeclaration(left:ll.chart,right:rr.chart,leftAxis:swapped ? 0:1,rightAxis:1,leftSide:.lower,rightSide:.lower)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let proof = try ids.declaredBoundary(declaration:declaration,left:ll,right:rr,scope:scope,rightFrame:right.support.frame,
            permutation:swapped ? [1,0]:[0,1],gains:swapped ? [one,one]:[f.integer(-1,using:&a),one],offsets:swapped ? [zero,zero]:[one,zero],limits:l,using:&a)
        // The original surfaces have different transverse derivatives along the shared edge.
        let ld = try ll.polynomials.differentiated(ll.homogeneous[swapped ? 0:1],in:swapped ? 0:1,using:&a)
        let rd = try rr.polynomials.differentiated(rr.homogeneous[swapped ? 0:1],in:1,using:&a)
        let half = try f.dividing(one,f.integer(2,using:&a),using:&a)
        let x = try ll.polynomials.evaluated(ld,at:swapped ? [zero,half]:[half,zero],using:&a).value
        let y = try rr.polynomials.evaluated(rd,at:[half,zero],using:&a).value
        try TransportFixtures.require(f.compare(x,y,using:&a) != .equal)
        return (proof,left,right)
    }
    static func cover(_ family: Family,right: Bool,requested: [[ExactParameterInterval<F.Value>]]? = nil,
        spatial: [Int]? = matrix,delta: Double = 0,_ a: inout ExactScalarLedger) throws -> Cover {
        var input = Parent(originalChild:family.source,gains:right ? [4,-3]:[-2,3],offsets:right ? [-1,2]:[3,-5],axes:right ? [0,1]:[1,0])
        input.spatial = spatial;input.delta = delta
        let source = try ComposedDomainFixtures.bind(input,depth:right ? 4:1,using:&a)
        return try DefaultOriginalParameterImageDomainIssuer<Parent,Family>().issue(source:source,child:family,requested:requested,limits:TransportFixtures.limits(),using:&a)
    }
    static func action(_ cover: Cover,_ a: inout ExactScalarLedger) throws -> Action {
        try DefaultOriginalParameterImageActionIssuer<Parent,F>().issue(source:cover.source,field:F(),limits:TransportFixtures.limits().source,using:&a)
    }
    static func tuple(_ u: F.Value,_ v: F.Value,right: Bool,_ a: inout ExactScalarLedger) throws -> [F.Value] {
        let f = F()
        if right { return try [f.dividing(f.adding(u,f.integer(1,using:&a),using:&a),f.integer(4,using:&a),using:&a),f.dividing(f.subtracting(v,f.integer(2,using:&a),using:&a),f.integer(-3,using:&a),using:&a)] }
        return try [f.dividing(f.subtracting(v,f.integer(3,using:&a),using:&a),f.integer(-2,using:&a),using:&a),f.dividing(f.adding(u,f.integer(5,using:&a),using:&a),f.integer(3,using:&a),using:&a)]
    }
    static func prepared(swapped: Bool = false) throws -> (Receipt,Cover,Cover,ChildReceipt,Action,Action) {
        var a = try TransportFixtures.admission()
        let (child,l,r) = try children(swapped:swapped,&a),left = try cover(l,right:false,&a),right = try cover(r,right:true,&a)
        let la = try action(left,&a),ra = try action(right,&a)
        let proof = try DefaultOriginalAffinePairedParameterIdentityIssuer<Parent,Family,Family>().lifted(child,from:left,to:right,leftAction:la,rightAction:ra,limits:TransportFixtures.limits(),using:&a)
        return (proof,left,right,child,la,ra)
    }
    static func boundaryAndNesting() throws {
        for swapped in [false,true] {
            let (proof,left,right,_,_,_) = try prepared(swapped:swapped)
            var a = try TransportFixtures.admission()
            let f = F(),l = try TransportFixtures.limits(),ids = DefaultOriginalParameterIdentityIssuer<Parent,F>()
            let zero = try f.integer(0,using:&a),half = try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
            let lhs = try tuple(swapped ? zero:half,swapped ? half:zero,right:false,&a)
            let rhs = try tuple(half,zero,right:true,&a)
            try TransportFixtures.require(proof.kind == .declaredSharedBoundary && ids.decide(proof,left:lhs,right:rhs,limits:l,using:&a) == .proven)
            let wrong = try tuple(f.integer(0,using:&a),zero,right:true,&a)
            try TransportFixtures.require(ids.decide(proof,left:lhs,right:wrong,limits:l,using:&a) == .refutedForThisRelation)
            let view = try ids.relation(of:proof,limits:l,using:&a)
            guard case .affine(let p,let gains,_) = view.constraints else { throw ExactScalarFailure.invalidEvidence }
            try TransportFixtures.require(p == (swapped ? [0,1]:[1,0]))
            let expected = try f.dividing(f.integer(swapped ? -1:-3,using:&a),f.integer(swapped ? 2:4,using:&a),using:&a)
            try TransportFixtures.require(f.compare(gains[0],expected,using:&a) == .equal)
            let symmetric = try ids.symmetric(proof,limits:l,using:&a),composed = try ids.compose(proof,symmetric,limits:l,using:&a)
            try TransportFixtures.require(ids.decide(symmetric,left:rhs,right:lhs,limits:l,using:&a) == .proven && ids.decide(composed,left:lhs,right:lhs,limits:l,using:&a) == .proven)
            typealias Outer = PairedImage<Parent>
            let ls = try ComposedDomainFixtures.bind(Outer(originalChild:left.source,gains:[1,-1],offsets:[7,2],axes:[1,0]),depth:2,using:&a)
            let rs = try ComposedDomainFixtures.bind(Outer(originalChild:right.source,gains:[2,1],offsets:[0,1],axes:[0,1]),depth:5,using:&a)
            let issuer = DefaultOriginalParameterImageDomainIssuer<Outer,Cover>()
            let lc = try issuer.issue(source:ls,child:left,limits:l,using:&a),rc = try issuer.issue(source:rs,child:right,limits:l,using:&a)
            let actions = DefaultOriginalParameterImageActionIssuer<Outer,F>()
            let nested = try DefaultOriginalAffinePairedParameterIdentityIssuer<Outer,Cover,Cover>().lifted(proof,from:lc,to:rc,leftAction:actions.issue(source:ls,field:f,limits:l.source,using:&a),rightAction:actions.issue(source:rs,field:f,limits:l.source,using:&a),limits:l,using:&a)
            let x = try [f.subtracting(lhs[1],f.integer(7,using:&a),using:&a),f.subtracting(f.integer(2,using:&a),lhs[0],using:&a)]
            let y = try [f.dividing(rhs[0],f.integer(2,using:&a),using:&a),f.subtracting(rhs[1],f.integer(1,using:&a),using:&a)]
            try TransportFixtures.require(DefaultOriginalParameterIdentityIssuer<Outer,F>().decide(nested,left:x,right:y,limits:l,using:&a) == .proven && nested.evidenceSourceDepth == 5)
            var noStorage = try TransportFixtures.admission(storage:0)
            _ = try ids.relation(of:proof,limits:l,using:&noStorage)
        }
        print("PASS paired affine boundary: distinct sources, independent reversed/swapped/nested maps, whole laws, unequal germs, original proof kind, symmetry/composition and retained lifetime")
    }
    static func scopesAndFailures() throws {
        let (_,left,right,child,la,ra) = try prepared()
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),ids = DefaultOriginalParameterIdentityIssuer<Parent,F>(),issuer = DefaultOriginalAffinePairedParameterIdentityIssuer<Parent,Family,Family>()
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a),half = try f.dividing(one,f.integer(2,using:&a),using:&a)
        let lhs = try tuple(half,zero,right:false,&a),rhs = try tuple(half,zero,right:true,&a)
        let singleton = try ExactParameterInterval.checked(field:f,lower:.finite(rhs[0]),upper:.finite(rhs[0]),depth:.init(value:0,coefficient:0),using:&a)
        let partial = try cover(right.childFamily,right:true,requested:[[singleton],Array(right.support.axes[1].intervals)],&a)
        let result = try issuer.lifted(child,from:left,to:partial,leftAction:la,rightAction:action(partial,&a),limits:l,using:&a)
        try TransportFixtures.require(ids.decide(result,left:lhs,right:rhs,limits:l,using:&a) == .proven)
        let endpoint = try tuple(zero,zero,right:false,&a)
        try TransportFixtures.require(ids.decide(result,left:endpoint,right:rhs,limits:l,using:&a) == .notEstablished)
        let empty = try cover(right.childFamily,right:true,requested:[[],[]],&a),ea = try action(empty,&a)
        let excluded = try issuer.lifted(child,from:left,to:empty,leftAction:la,rightAction:ea,limits:l,using:&a)
        try TransportFixtures.require(excluded.left.isEmpty && excluded.right.isEmpty)
        var baseline = try TerminalAdmission()
        _ = try issuer.lifted(child,from:left,to:empty,leftAction:la,rightAction:ea,limits:l,using:&baseline)
        var cancel = try TerminalAdmission();cancel.cancelAt = baseline.checks
        do { _ = try issuer.lifted(child,from:left,to:empty,leftAction:la,rightAction:ea,limits:l,using:&cancel);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        let changed = try cover(right.childFamily,right:true,delta:0x1p-50,&a)
        do { _ = try issuer.lifted(child,from:left,to:changed,leftAction:la,rightAction:action(changed,&a),limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.unsupportedSourceProof {}
        do { _ = try issuer.lifted(child,from:left,to:right,leftAction:ra,rightAction:la,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        let (_,otherLeft,otherRight) = try children(&a)
        let foreign = try cover(otherLeft,right:false,&a)
        do { _ = try issuer.lifted(child,from:foreign,to:right,leftAction:action(foreign,&a),rightAction:ra,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        let local = try cover(otherRight,right:true,&a)
        do { _ = try issuer.lifted(child,from:left,to:local,leftAction:la,rightAction:action(local,&a),limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        let symmetric = try ids.symmetric(result,limits:l,using:&a)
        let foreignMiddle = try prepared().0
        do { _ = try ids.compose(foreignMiddle,symmetric,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        let first = try tuple(one,zero,right:true,&a)[0],last = try tuple(zero,zero,right:true,&a)[0]
        let strictInterval = try ExactParameterInterval.checked(field:f,lower:.finite(last),upper:.finite(first),includesLower:false,includesUpper:false,depth:.init(value:0,coefficient:0),using:&a)
        let strict = try cover(right.childFamily,right:true,requested:[[strictInterval],Array(right.support.axes[1].intervals)],&a)
        let strictProof = try issuer.lifted(child,from:left,to:strict,leftAction:la,rightAction:action(strict,&a),limits:l,using:&a)
        try TransportFixtures.require(ids.decide(strictProof,left:lhs,right:rhs,limits:l,using:&a) == .proven)
        try TransportFixtures.require(ids.decide(strictProof,left:endpoint,right:tuple(one,zero,right:true,&a),limits:l,using:&a) == .notEstablished)
        let low = try ExactParameterInterval.checked(field:f,lower:.finite(last),upper:.finite(last),depth:.init(value:0,coefficient:0),using:&a)
        let high = try ExactParameterInterval.checked(field:f,lower:.finite(first),upper:.finite(first),depth:.init(value:0,coefficient:0),using:&a)
        let disconnected = try cover(right.childFamily,right:true,requested:[[low,high],Array(right.support.axes[1].intervals)],&a)
        let dp = try issuer.lifted(child,from:left,to:disconnected,leftAction:la,rightAction:action(disconnected,&a),limits:l,using:&a)
        try TransportFixtures.require(ids.decide(dp,left:lhs,right:rhs,limits:l,using:&a) == .notEstablished)
        try TransportFixtures.require(ids.decide(dp,left:endpoint,right:tuple(one,zero,right:true,&a),limits:l,using:&a) == .proven)
        let native = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,F>()
        let newSpace = try native.prepare(source:left.childFamily.source,field:f,limits:l,using:&a)
        let newFamily = try native.issue(space:newSpace,request:newSpace.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let newFrame = try cover(newFamily,right:false,&a)
        do { _ = try issuer.lifted(child,from:newFrame,to:right,leftAction:action(newFrame,&a),rightAction:ra,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        let identity = [1,0,0,0,0,1,0,0,0,0,1,0]
        let noAction = try cover(left.childFamily,right:false,spatial:nil,&a),explicitIdentity = try cover(right.childFamily,right:true,spatial:identity,&a)
        let equivalent = try issuer.lifted(child,from:noAction,to:explicitIdentity,leftAction:action(noAction,&a),rightAction:action(explicitIdentity,&a),limits:l,using:&a)
        try TransportFixtures.require(ids.decide(equivalent,left:lhs,right:rhs,limits:l,using:&a) == .proven)
        print("PASS paired affine scopes: independent singleton/empty pullbacks, terminal empty cancel, exact tiny unequal action and foreign action/child/middle owners")
    }
    static func resourcesAndCancel() throws {
        let (proof,left,right,child,la,ra) = try prepared()
        let l = try TransportFixtures.limits(),issuer = DefaultOriginalAffinePairedParameterIdentityIssuer<Parent,Family,Family>()
        var measured = try TransportFixtures.admission()
        _ = try issuer.lifted(child,from:left,to:right,leftAction:la,rightAction:ra,limits:l,using:&measured)
        var exact = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        _ = try issuer.lifted(child,from:left,to:right,leftAction:la,rightAction:ra,limits:l,using:&exact)
        var work = try TransportFixtures.admission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try issuer.lifted(child,from:left,to:right,leftAction:la,rightAction:ra,limits:l,using:&work);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var storage = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try issuer.lifted(child,from:left,to:right,leftAction:la,rightAction:ra,limits:l,using:&storage);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        for limited in [try TransportFixtures.limits(depth:proof.depth-1),try TransportFixtures.limits(charts:0),try TransportFixtures.limits(sourceDepth:3),try TransportFixtures.limits(identities:proof.proofCount-1)] {
            var limitedAdmission = try TransportFixtures.admission()
            do { _ = try issuer.lifted(child,from:left,to:right,leftAction:la,rightAction:ra,limits:limited,using:&limitedAdmission);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.transportDepthLimit {}
            catch OriginalDomainIdentityFailure.chartLimit {}
            catch OriginalDomainIdentityFailure.sourceDepthLimit {}
            catch OriginalDomainIdentityFailure.identityLimit {}
        }
        var baseline = try TerminalAdmission()
        _ = try issuer.lifted(child,from:left,to:right,leftAction:la,rightAction:ra,limits:l,using:&baseline)
        for at in [1,baseline.checks/2,baseline.checks] {
            var cancel = try TerminalAdmission();cancel.cancelAt = at
            do { _ = try issuer.lifted(child,from:left,to:right,leftAction:la,rightAction:ra,limits:l,using:&cancel);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
            catch OriginalDomainIdentityFailure.source(.scalar(.cancelled)) {}
            catch OriginalDomainIdentityFailure.domain(.scalar(.cancelled)) {}
        }
        print("PASS paired affine resources: exact work\(measured.work)/storage\(measured.storageBytes), one-less, independent depth/chart/source/proof and entry/mid/final cancellation")
    }
    static func sourceActions() throws {
        let (_,left,_,_,_,_) = try prepared()
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),issuer = DefaultOriginalParameterImageActionIssuer<Parent,F>()
        var measured = try TransportFixtures.admission()
        let receipt = try issuer.issue(source:left.source,field:f,limits:l.source,using:&measured)
        var exact = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        _ = try issuer.issue(source:left.source,field:f,limits:l.source,using:&exact)
        var work = try TransportFixtures.admission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try issuer.issue(source:left.source,field:f,limits:l.source,using:&work);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        var storage = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try issuer.issue(source:left.source,field:f,limits:l.source,using:&storage);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        var baseline = try TerminalAdmission()
        _ = try issuer.issue(source:left.source,field:f,limits:l.source,using:&baseline)
        for at in [1,baseline.checks/2,baseline.checks] {
            var cancel = try TerminalAdmission();cancel.cancelAt = at
            do { _ = try issuer.issue(source:left.source,field:f,limits:l.source,using:&cancel);throw ExactScalarFailure.invalidEvidence }
            catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        }
        do { _ = try receipt.action.coefficient(row:3,column:0,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.invalidSource {}
        var values = try matrix.map { try f.integer($0,using:&a) }
        let spatial = try ComposedDomainFixtures.bind(PairedSpatial(originalChild:left.childFamily.source,values:values),depth:1,using:&a)
        values[0] = try f.integer(999,using:&a)
        let word = try DefaultOriginalSpatialActionIssuer<PairedSpatial<NativeSnapshot>,F>().issue(source:spatial,field:f,limits:l.source,using:&a)
        let traversal = try ComposedDomainFixtures.bind(ComposedDomainFixtures.Traversal(originalChild:left.childFamily.source,originalStart:f.integer(1,using:&a),originalEnd:f.integer(0,using:&a)),depth:1,using:&a)
        let directed = try DefaultOriginalTraversalActionIssuer<ComposedDomainFixtures.Traversal<NativeSnapshot>,F>().issue(source:traversal,field:f,limits:l.source,using:&a)
        for row in 0..<3 { for column in 0..<4 {
            try TransportFixtures.require(f.compare(word.action.coefficient(row:row,column:column,using:&a),receipt.action.coefficient(row:row,column:column,using:&a),using:&a) == .equal)
            try TransportFixtures.require(f.compare(directed.action.coefficient(row:row,column:column,using:&a),f.integer(row == column ? 1:0,using:&a),using:&a) == .equal)
        } }
        print("PASS source affine actions: original parameter-image/spatial-word/traversal values, retained receipt, checked indices, exact resources and cancellation")
    }
}

@main struct AffinePairedIdentityVerification {
    static func main() throws {
        try AffinePairedIdentityProof.boundaryAndNesting()
        try AffinePairedIdentityProof.scopesAndFailures()
        try AffinePairedIdentityProof.resourcesAndCancel()
        try AffinePairedIdentityProof.sourceActions()
        try PairedActionDepthProof.retainedActionDepth()
        try PairedActionDepthProof.physicalFieldsAndProducts()
        try AffineChildIdentityVerification.main()
        print("PASS paired affine identity and retained single-cover/domain/view regression")
    }
}
