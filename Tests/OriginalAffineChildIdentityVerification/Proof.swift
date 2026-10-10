import L0
import L1
import DI0
import DI
import SourceIssuer

enum AffineChildIdentityProof {
    typealias F = ExactRationalScalarDomain
    typealias Child = AnalyticCoordinateInput
    typealias Family = OriginalAnalyticDomainCover<Child,F>
    typealias Parent = ComposedDomainFixtures.Image<Child>
    typealias Cover = OriginalAffineChildDomainCover<Parent,Family>
    typealias Receipt = OriginalParameterIdentity<Parent,F>
    static func family(_ kind: OriginalAnalyticCoordinateKind, _ a: inout ExactScalarLedger) throws -> Family {
        let l = try TransportFixtures.limits(),f = F()
        let source = try DefaultOriginalSourceBindingIssuer(provider:AnalyticCoordinateProvider()).bind(Child(coordinateKind:kind),limits:l.source,using:&a)
        let law = try DefaultOriginalAnalyticCoordinateIssuer<Child,F>().issue(source:source,field:f,limits:l.source,using:&a)
        let issuer = DefaultOriginalAnalyticDomainIssuer<Child,F>()
        let frame = try issuer.frame(law:law,limits:l,using:&a)
        return try issuer.issue(request:frame.fullSelection(limits:l,using:&a),law:law,limits:l,using:&a)
    }
    static func cover(_ child: Family,requested: [[ExactParameterInterval<F.Value>]]? = nil,_ a: inout ExactScalarLedger) throws -> Cover {
        let source = try ComposedDomainFixtures.bind(Parent(originalChild:child.source,gains:[-2,3],offsets:[3,-5],axes:[1,0]),depth:1,using:&a)
        return try DefaultOriginalParameterImageDomainIssuer<Parent,Family>().issue(source:source,child:child,requested:requested,limits:TransportFixtures.limits(),using:&a)
    }
    static func tuple(_ u: F.Value,_ v: F.Value,_ a: inout ExactScalarLedger) throws -> [F.Value] {
        let f = F()
        // Independently apply the authored child = gain * parent + offset law.
        return try [f.dividing(f.subtracting(v,f.integer(3,using:&a),using:&a),f.integer(-2,using:&a),using:&a),
            f.dividing(f.adding(u,f.integer(5,using:&a),using:&a),f.integer(3,using:&a),using:&a)]
    }
    static func retained() throws -> (Receipt,Cover) {
        var a = try TransportFixtures.admission()
        let child = try family(.torus,&a),parent = try cover(child,&a),l = try TransportFixtures.limits(),f = F()
        let cycle = try OriginalParameterCycle(exact:f.integer(-2,using:&a),using:&a)
        let proof = try DefaultOriginalParameterIdentityIssuer<Child,F>().periodic(cover:child,from:child.effective,axis:0,cycle:cycle,limits:l,using:&a)
        let lifted = try DefaultOriginalAffineChildParameterIdentityIssuer<Parent,Family>().lifted(proof,through:parent,limits:l,using:&a)
        return (lifted,parent)
    }
    static func detached() throws -> (Receipt,[F.Value],[F.Value]) {
        let (proof,cover) = try retained()
        var a = try TransportFixtures.admission()
        let f = F(),zero = try f.integer(0,using:&a)
        return (proof,try tuple(zero,zero,&a),try tuple(f.multiplying(cover.childFamily.law.periods[0].period,f.integer(-2,using:&a),using:&a),zero,&a))
    }
    static func periodsNestingAndLifetime() throws {
        let (proof,parent) = try retained()
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),ids = DefaultOriginalParameterIdentityIssuer<Parent,F>()
        let period = parent.childFamily.law.periods[0].period,zero = try f.integer(0,using:&a)
        let lhs = try tuple(zero,zero,&a),rhs = try tuple(f.multiplying(period,f.integer(-2,using:&a),using:&a),zero,&a)
        try TransportFixtures.require(proof.kind == .periodicOrbit && ids.decide(proof,left:lhs,right:rhs,limits:l,using:&a) == .proven)
        try TransportFixtures.require(ids.decide(proof,left:lhs,right:lhs,limits:l,using:&a) == .refutedForThisRelation)
        let view = try ids.relation(of:proof,limits:l,using:&a)
        guard case .affine(let permutation,_,_) = view.constraints else { throw ExactScalarFailure.invalidEvidence }
        try TransportFixtures.require(permutation == [0,1])
        if case .affine(_,var gains,_) = view.constraints {
            gains[0] = try f.integer(99,using:&a)
            try TransportFixtures.require(ids.decide(proof,left:lhs,right:rhs,limits:l,using:&a) == .proven)
        }
        var noStorage = try TransportFixtures.admission(storage:0)
        _ = try ids.relation(of:proof,limits:l,using:&noStorage)
        try TransportFixtures.require(noStorage.storageBytes == 0)
        let (detachedProof,detachedLeft,detachedRight) = try detached()
        try TransportFixtures.require(ids.decide(detachedProof,left:detachedLeft,right:detachedRight,limits:l,using:&a) == .proven)
        let inverse = try ids.symmetric(proof,limits:l,using:&a)
        let composed = try ids.compose(proof,inverse,limits:l,using:&a)
        try TransportFixtures.require(ids.decide(composed,left:lhs,right:lhs,limits:l,using:&a) == .proven)
        typealias Outer = ComposedDomainFixtures.Image<Parent>
        let source = try ComposedDomainFixtures.bind(Outer(originalChild:parent.source,gains:[1,-1],offsets:[7,2],axes:[1,0]),depth:2,using:&a)
        let nested = try DefaultOriginalParameterImageDomainIssuer<Outer,Cover>().issue(source:source,child:parent,limits:l,using:&a)
        let result = try DefaultOriginalAffineChildParameterIdentityIssuer<Outer,Cover>().lifted(proof,through:nested,limits:l,using:&a)
        let outer = DefaultOriginalParameterIdentityIssuer<Outer,F>()
        func swapped(_ tuple: [F.Value],_ a: inout ExactScalarLedger) throws -> [F.Value] {
            try [f.subtracting(tuple[1],f.integer(7,using:&a),using:&a),f.subtracting(f.integer(2,using:&a),tuple[0],using:&a)]
        }
        let x = try swapped(lhs,&a),y = try swapped(rhs,&a)
        try TransportFixtures.require(outer.decide(result,left:x,right:y,limits:l,using:&a) == .proven)
        try TransportFixtures.require(result.proofCount == proof.proofCount+1 && result.evidenceSourceDepth == 2)
        let huge = try f.multiplying(f.integer(1000000000,using:&a),f.integer(1000000000,using:&a),using:&a)
        let cycle = try OriginalParameterCycle(exact:f.negated(f.multiplying(huge,huge,using:&a),using:&a),using:&a)
        for axis in 0..<2 {
            let childProof = try DefaultOriginalParameterIdentityIssuer<Child,F>().periodic(cover:parent.childFamily,from:parent.childFamily.effective,axis:axis,cycle:cycle,limits:l,using:&a)
            let transported = try DefaultOriginalAffineChildParameterIdentityIssuer<Parent,Family>().lifted(childProof,through:parent,limits:l,using:&a)
            let displacement = try f.multiplying(parent.childFamily.law.periods[axis].period,cycle.original,using:&a)
            let target = try tuple(axis == 0 ? displacement:zero,axis == 1 ? displacement:zero,&a)
            try TransportFixtures.require(ids.decide(transported,left:lhs,right:target,limits:l,using:&a) == .proven)
        }
        print("PASS affine child identity: negative multi-cycle, reversal/swap, symmetry/composition, nested source types and post-source-scope lifetime")
    }
    static func scopesCollapseAndForeign() throws {
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),child = try family(.sphere,&a)
        let fiber = child.law.collapsedFibers[0],zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let fixed = try ExactParameterInterval.checked(field:f,lower:.finite(fiber.fixedValue),upper:.finite(fiber.fixedValue),depth:.init(value:0,coefficient:0),using:&a)
        let scope = try child.support.frame.selection(intervals:[[TransportFixtures.interval(-2,2,using:&a)],[fixed]],limits:l,using:&a)
        let original = try DefaultOriginalParameterIdentityIssuer<Child,F>().collapsed(cover:child,on:scope,fiber:0,limits:l,using:&a)
        let parent = try cover(child,&a),issuer = DefaultOriginalAffineChildParameterIdentityIssuer<Parent,Family>(),ids = DefaultOriginalParameterIdentityIssuer<Parent,F>()
        let result = try issuer.lifted(original,through:parent,limits:l,using:&a)
        let lhs = try tuple(f.integer(-2,using:&a),fiber.fixedValue,&a),rhs = try tuple(f.integer(2,using:&a),fiber.fixedValue,&a)
        try TransportFixtures.require(ids.decide(result,left:lhs,right:rhs,limits:l,using:&a) == .proven)
        guard case .completeProduct = try ids.relation(of:result,limits:l,using:&a).constraints else { throw ExactScalarFailure.invalidEvidence }
        let delta = try f.dividing(one,f.integer(1000000,using:&a),using:&a)
        let near = try tuple(zero,f.adding(fiber.fixedValue,delta,using:&a),&a)
        try TransportFixtures.require(ids.decide(result,left:near,right:near,limits:l,using:&a) == .notEstablished)
        let full = parent.support.axes[0].intervals
        let requested = [Array(full),[try TransportFixtures.interval(1,1,using:&a),try TransportFixtures.interval(2,2,using:&a)]]
        let partial = try cover(child,requested:requested,&a)
        let restricted = try issuer.lifted(original,through:partial,limits:l,using:&a)
        let u1 = try tuple(f.integer(-2,using:&a),fiber.fixedValue,&a),u2 = try tuple(one,fiber.fixedValue,&a)
        try TransportFixtures.require(ids.decide(restricted,left:u1,right:u2,limits:l,using:&a) == .proven)
        try TransportFixtures.require(ids.decide(restricted,left:rhs,right:rhs,limits:l,using:&a) == .notEstablished)
        let open = try cover(child,requested:[Array(full),[TransportFixtures.interval(1,2,false,false,using:&a)]],&a)
        let strict = try issuer.lifted(original,through:open,limits:l,using:&a)
        let inside = try tuple(zero,fiber.fixedValue,&a)
        try TransportFixtures.require(ids.decide(strict,left:inside,right:inside,limits:l,using:&a) == .proven)
        try TransportFixtures.require(ids.decide(strict,left:u1,right:inside,limits:l,using:&a) == .notEstablished)
        let empty = try cover(child,requested:[[],[]],&a)
        let excluded = try issuer.lifted(original,through:empty,limits:l,using:&a)
        try TransportFixtures.require(excluded.left.isEmpty && excluded.right.isEmpty)
        var emptyBaseline = try TerminalAdmission()
        _ = try issuer.lifted(original,through:empty,limits:l,using:&emptyBaseline)
        var emptyCancelled = try TerminalAdmission();emptyCancelled.cancelAt = emptyBaseline.checks
        do { _ = try issuer.lifted(original,through:empty,limits:l,using:&emptyCancelled);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        let other = try family(.sphere,&a),foreign = try cover(other,&a)
        do { _ = try issuer.lifted(original,through:foreign,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        let frame = try DefaultOriginalAnalyticDomainIssuer<Child,F>().frame(law:child.law,limits:l,using:&a)
        let shifted = try DefaultOriginalAnalyticDomainIssuer<Child,F>().issue(request:frame.fullSelection(limits:l,using:&a),law:child.law,limits:l,using:&a)
        do { _ = try issuer.lifted(original,through:cover(shifted,&a),limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        print("PASS affine child identity: collapsed full UV, near-pole refusal, disconnected/singleton/empty pullbacks and foreign owner/frame")
    }
    static func resourcesAndCancel() throws {
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),child = try family(.torus,&a),parent = try cover(child,&a)
        let cycle = try OriginalParameterCycle(exact:f.integer(1,using:&a),using:&a)
        let original = try DefaultOriginalParameterIdentityIssuer<Child,F>().periodic(cover:child,from:child.effective,axis:0,cycle:cycle,limits:l,using:&a)
        let issuer = DefaultOriginalAffineChildParameterIdentityIssuer<Parent,Family>()
        var measured = try TransportFixtures.admission()
        let proof = try issuer.lifted(original,through:parent,limits:l,using:&measured)
        var exact = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        _ = try issuer.lifted(original,through:parent,limits:l,using:&exact)
        var work = try TransportFixtures.admission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try issuer.lifted(original,through:parent,limits:l,using:&work); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var storage = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try issuer.lifted(original,through:parent,limits:l,using:&storage); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        for limit in [try TransportFixtures.limits(depth:proof.depth-1),try TransportFixtures.limits(identities:proof.proofCount-1),try TransportFixtures.limits(sourceDepth:0),try TransportFixtures.limits(charts:0),try TransportFixtures.limits(families:0)] {
            do { _ = try issuer.lifted(original,through:parent,limits:limit,using:&a); throw ExactScalarFailure.invalidEvidence }
            catch let error as OriginalDomainIdentityFailure {
                switch error { case .transportDepthLimit,.identityLimit,.sourceDepthLimit,.chartLimit,.familyLimit: break; default: throw error }
            }
        }
        var baseline = try TerminalAdmission()
        _ = try issuer.lifted(original,through:parent,limits:l,using:&baseline)
        for checkpoint in [1,baseline.checks/2,baseline.checks] {
            var cancel = try TerminalAdmission(); cancel.cancelAt = checkpoint
            do { _ = try issuer.lifted(original,through:parent,limits:l,using:&cancel); throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        }
        let ids = DefaultOriginalParameterIdentityIssuer<Parent,F>(),zero = try f.integer(0,using:&a)
        let x = try tuple(zero,zero,&a),y = try tuple(child.law.periods[0].period,zero,&a)
        var query = try TerminalAdmission(); _ = try ids.decide(proof,left:x,right:y,limits:l,using:&query)
        var cancelled = try TerminalAdmission(); cancelled.cancelAt = query.checks
        do { _ = try ids.decide(proof,left:x,right:y,limits:l,using:&cancelled); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        print("PASS affine child identity: exact work/storage \(measured.work)/\(measured.storageBytes), one-less refusal, independent limits, entry/mid/final/query cancel")
    }
    static func physicalFieldsAndReadmission() throws {
        typealias Field = OriginalPiScalarDomain
        typealias Circle = OriginalAnalyticDomainCover<Child,Field>
        var a = try TransportFixtures.admission(work:100_000_000,storage:400_000_000)
        let f = try Field(using:&a),q = F(),l = try TransportFixtures.limits()
        var input = Child(coordinateKind:.circle)
        input.phases = [.physicalRadians(gain:try q.integer(1,using:&a),offset:try q.integer(0,using:&a)),.intrinsic]
        let source = try DefaultOriginalSourceBindingIssuer(provider:AnalyticCoordinateProvider()).bind(input,limits:l.source,using:&a)
        input.origin[0] = -999
        let law = try DefaultOriginalPhysicalAnalyticCoordinateIssuer<Child,Field>().issue(source:source,field:f,limits:l.source,using:&a)
        let domain = DefaultOriginalAnalyticDomainIssuer<Child,Field>()
        let frame = try domain.frame(law:law,limits:l,using:&a)
        let child = try domain.issue(request:frame.fullSelection(limits:l,using:&a),law:law,limits:l,using:&a)
        let cycle = try OriginalParameterCycle(exact:q.integer(1,using:&a),using:&a)
        let original = try DefaultOriginalParameterIdentityIssuer<Child,Field>().periodic(cover:child,from:child.effective,axis:0,cycle:cycle,limits:l,using:&a)
        let parentSource = try ComposedDomainFixtures.bind(Parent(originalChild:source,gains:[-2],offsets:[3],axes:[0]),depth:1,using:&a)
        let parent = try DefaultOriginalParameterImageDomainIssuer<Parent,Circle>().issue(source:parentSource,child:child,limits:l,using:&a)
        let proof = try DefaultOriginalAffineChildParameterIdentityIssuer<Parent,Circle>().lifted(original,through:parent,limits:l,using:&a)
        let ids = DefaultOriginalParameterIdentityIssuer<Parent,Field>(),three = try f.integer(3,using:&a),minusTwo = try f.integer(-2,using:&a)
        let x = try [f.dividing(f.negated(three,using:&a),minusTwo,using:&a)]
        let y = try [f.dividing(f.subtracting(law.periods[0].period,three,using:&a),minusTwo,using:&a)]
        try TransportFixtures.require(ids.decide(proof,left:x,right:y,limits:l,using:&a) == .proven)
        let rounded = try [f.dividing(f.subtracting(f.binary64(exactly:2*Double.pi,using:&a),three,using:&a),minusTwo,using:&a)]
        try TransportFixtures.require(ids.decide(proof,left:x,right:rounded,limits:l,using:&a) == .refutedForThisRelation)
        let other = try Field(using:&a),foreign = try other.integer(0,using:&a)
        do { _ = try ids.decide(proof,left:[foreign],right:y,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.domain(.scalar(.incompatibleDomain)) {}
        try TransportFixtures.require(source.original.origin[0] == 1)
        print("PASS affine physical identity: exact pi versus binary64, source COW and foreign-field refusal")

    }
    static func exchangedChildBoundary() throws {
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits()
        // G(u,v)=(u+v,u*v,0): both declared edges have the same whole position law.
        let input = NativeInput(degrees:[1,1],knots:[[0,0,1,1],[0,0,1,1]],counts:[2,2],
            controls:[[0,0,0],[1,0,0],[1,0,0],[2,1,0]],weights:[1,1,1,1],periodic:[false,false])
        let source = try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:l.source,using:&a)
        let domain = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,F>()
        let space = try domain.prepare(source:source,field:f,limits:l,using:&a)
        let child = try domain.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let law = try DefaultOriginalBSplineChartIssuer<NativeSnapshot,F>().issue(source:source,chart:space.sourceCharts[0],field:f,limits:l.source,using:&a)
        let selected = try space.frame.selection(intervals:[[TransportFixtures.interval(0,0,using:&a)],[TransportFixtures.interval(0,1,using:&a)]],limits:l,using:&a)
        let declaration = OriginalSourceBoundaryDeclaration(left:law.chart,right:law.chart,leftAxis:0,rightAxis:1,leftSide:.lower,rightSide:.lower)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let original = try DefaultOriginalParameterIdentityIssuer<NativeSnapshot,F>().declaredBoundary(declaration:declaration,left:law,right:law,scope:selected,rightFrame:space.frame,
            permutation:[1,0],gains:[one,one],offsets:[zero,zero],limits:l,using:&a)
        typealias Parent = ComposedDomainFixtures.Image<NativeSnapshot>
        let parentSource = try ComposedDomainFixtures.bind(Parent(originalChild:source,gains:[-2,3],offsets:[3,-5],axes:[1,0]),depth:1,using:&a)
        let cover = try DefaultOriginalParameterImageDomainIssuer<Parent,OriginalBSplineDomainCover<NativeSnapshot,F>>().issue(source:parentSource,child:child,limits:l,using:&a)
        let result = try DefaultOriginalAffineChildParameterIdentityIssuer<Parent,OriginalBSplineDomainCover<NativeSnapshot,F>>().lifted(original,through:cover,limits:l,using:&a)
        let ids = DefaultOriginalParameterIdentityIssuer<Parent,F>(),half = try f.dividing(one,f.integer(2,using:&a),using:&a)
        let lhs = try tuple(zero,half,&a),rhs = try tuple(half,zero,&a)
        try TransportFixtures.require(result.kind == .declaredSharedBoundary && ids.decide(result,left:lhs,right:rhs,limits:l,using:&a) == .proven)
        let wrong = try tuple(one,zero,&a)
        try TransportFixtures.require(ids.decide(result,left:lhs,right:wrong,limits:l,using:&a) == .refutedForThisRelation)
        guard case .affine(let permutation,let gains,_) = try ids.relation(of:result,limits:l,using:&a).constraints else { throw ExactScalarFailure.invalidEvidence }
        try TransportFixtures.require(permutation == [1,0])
        try TransportFixtures.require(f.compare(gains[0],f.dividing(f.integer(-3,using:&a),f.integer(2,using:&a),using:&a),using:&a) == .equal)
        try TransportFixtures.require(f.compare(gains[1],f.dividing(f.integer(-2,using:&a),f.integer(3,using:&a),using:&a),using:&a) == .equal)
        print("PASS affine child boundary: whole-law axis exchange, nonuniform conjugated gains, exact paired scopes and unchanged position-only proof kind")
    }
}

#if !AFFINE_PAIRED_IDENTITY_VERIFICATION
@main
#endif
struct AffineChildIdentityVerification {
    static func main() throws {
        try AffineChildIdentityProof.periodsNestingAndLifetime()
        try AffineChildIdentityProof.scopesCollapseAndForeign()
        try AffineChildIdentityProof.resourcesAndCancel()
        try AffineChildIdentityProof.physicalFieldsAndReadmission()
        try AffineIdentityDepthFixtures.cancellationReadmission()
        try AffineChildIdentityProof.exchangedChildBoundary()
        try IdentityFixtures.scopedCoordinatesAndPeriods()
        try IdentityFixtures.collapsedAndBoundaryLaws()
        try IdentityFixtures.declaredWholeBoundary()
        try AnalyticIdentityFixtures.intrinsicPeriodsAndFibers()
        try AnalyticIdentityFixtures.physicalClippingAndFailures()
        try RelationViewFixtures.affineWordsAndLifetime()
        try RelationViewFixtures.completeProductsAndFailures()
        try ComposedDomainFixtures.completeFamilies()
        try ComposedDomainFixtures.completePullbackAndFailures()
        print("PASS affine child identity and retained identity/domain/view regression")
    }
}
