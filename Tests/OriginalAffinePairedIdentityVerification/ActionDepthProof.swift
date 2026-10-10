import L0
import L1
import DI0
import DI
import SourceIssuer

enum PairedActionDepthProof {
    static func retainedActionDepth() throws {
        for coefficient in [false,true] {
            var a = try TransportFixtures.admission()
            let f = IdentityDepthField(usesCoefficientDepth:coefficient),l = try TransportFixtures.limits(),source = try TransportFixtures.binding(true)
            let issuer = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,IdentityDepthField>()
            let space = try issuer.prepare(source:source,field:f,limits:l,using:&a)
            let child = try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
            let cycle = try OriginalParameterCycle(exact:ExactRationalScalarDomain().integer(1,using:&a),using:&a)
            let original = try DefaultOriginalParameterIdentityIssuer<NativeSnapshot,IdentityDepthField>().periodic(cover:child,from:child.effective,axis:0,cycle:cycle,limits:l,using:&a)
            typealias Parent = PairedImage<NativeSnapshot>
            typealias Family = OriginalBSplineDomainCover<NativeSnapshot,IdentityDepthField>
            var input = Parent(originalChild:source,gains:[1],offsets:[0],axes:[0])
            input.spatial = [1,0,0,5,0,1,0,0,0,0,1,0]
            let left = try ComposedDomainFixtures.bind(input,depth:1,using:&a),right = try ComposedDomainFixtures.bind(input,depth:2,using:&a)
            input.spatial?[3] = 999
            let coverIssuer = DefaultOriginalParameterImageDomainIssuer<Parent,Family>()
            let lc = try coverIssuer.issue(source:left,child:child,limits:l,using:&a),rc = try coverIssuer.issue(source:right,child:child,limits:l,using:&a)
            let actionIssuer = DefaultOriginalParameterImageActionIssuer<Parent,IdentityDepthField>()
            let la = try actionIssuer.issue(source:left,field:f,limits:l.source,using:&a),ra = try actionIssuer.issue(source:right,field:f,limits:l.source,using:&a)
            try TransportFixtures.require(coefficient ? la.action.evidenceDepth.coefficient == 7:la.action.evidenceDepth.value == 7)
            let proof = try DefaultOriginalAffinePairedParameterIdentityIssuer<Parent,Family,Family>().lifted(original,from:lc,to:rc,leftAction:la,rightAction:ra,limits:l,using:&a)
            let ids = DefaultOriginalParameterIdentityIssuer<Parent,IdentityDepthField>(),symmetric = try ids.symmetric(proof,limits:l,using:&a)
            let composed = try ids.compose(proof,symmetric,limits:l,using:&a)
            for receipt in [proof,symmetric,composed] {
                var exact = ExactScalarLedger(limits:try .init(work:10_000_000,storageBytes:100_000_000,valueDepth:coefficient ? 32:7,coefficientDepth:coefficient ? 7:32))
                _ = try ids.relation(of:receipt,limits:l,using:&exact)
                var shallow = ExactScalarLedger(limits:try .init(work:10_000_000,storageBytes:100_000_000,valueDepth:coefficient ? 32:6,coefficientDepth:coefficient ? 6:32))
                do { _ = try ids.relation(of:receipt,limits:l,using:&shallow);throw ExactScalarFailure.invalidEvidence }
                catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.valueDepth)) {}
                catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.coefficientDepth)) {}
            }
        }
        print("PASS paired source action depth: independent value/coefficient depth7 retained after coordinate cancellation, symmetry/composition and input COW mutation")
    }
    static func physicalFieldsAndProducts() throws {
        var a = try TransportFixtures.admission(work:100_000_000,storage:400_000_000)
        typealias Field = OriginalPiScalarDomain
        typealias Child = AnalyticCoordinateInput
        typealias Family = OriginalAnalyticDomainCover<Child,Field>
        typealias Parent = PairedImage<Child>
        let f = try Field(using:&a),q = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        var input = Child(coordinateKind:.circle)
        input.phases = [.physicalRadians(gain:try q.integer(1,using:&a),offset:try q.integer(0,using:&a)),.intrinsic]
        let source = try DefaultOriginalSourceBindingIssuer(provider:AnalyticCoordinateProvider()).bind(input,limits:l.source,using:&a)
        let law = try DefaultOriginalPhysicalAnalyticCoordinateIssuer<Child,Field>().issue(source:source,field:f,limits:l.source,using:&a)
        let di = DefaultOriginalAnalyticDomainIssuer<Child,Field>(),frame = try di.frame(law:law,limits:l,using:&a)
        let child = try di.issue(request:frame.fullSelection(limits:l,using:&a),law:law,limits:l,using:&a)
        let cycle = try OriginalParameterCycle(exact:q.integer(1,using:&a),using:&a)
        let original = try DefaultOriginalParameterIdentityIssuer<Child,Field>().periodic(cover:child,from:child.effective,axis:0,cycle:cycle,limits:l,using:&a)
        let ls = try ComposedDomainFixtures.bind(Parent(originalChild:source,gains:[-2],offsets:[3],axes:[0]),depth:1,using:&a)
        let rs = try ComposedDomainFixtures.bind(Parent(originalChild:source,gains:[3],offsets:[-1],axes:[0]),depth:1,using:&a)
        let covers = DefaultOriginalParameterImageDomainIssuer<Parent,Family>(),lc = try covers.issue(source:ls,child:child,limits:l,using:&a),rc = try covers.issue(source:rs,child:child,limits:l,using:&a)
        let actions = DefaultOriginalParameterImageActionIssuer<Parent,Field>(),la = try actions.issue(source:ls,field:f,limits:l.source,using:&a)
        let issuer = DefaultOriginalAffinePairedParameterIdentityIssuer<Parent,Family,Family>()
        let proof = try issuer.lifted(original,from:lc,to:rc,leftAction:la,rightAction:actions.issue(source:rs,field:f,limits:l.source,using:&a),limits:l,using:&a)
        let ids = DefaultOriginalParameterIdentityIssuer<Parent,Field>(),one = try f.integer(1,using:&a),three = try f.integer(3,using:&a)
        let x = try [f.dividing(three,f.integer(2,using:&a),using:&a)],y = try [f.dividing(f.adding(law.periods[0].period,one,using:&a),three,using:&a)]
        try TransportFixtures.require(ids.decide(proof,left:x,right:y,limits:l,using:&a) == .proven)
        let rounded = try [f.dividing(f.adding(f.binary64(exactly:2*Double.pi,using:&a),one,using:&a),three,using:&a)]
        try TransportFixtures.require(ids.decide(proof,left:x,right:rounded,limits:l,using:&a) == .refutedForThisRelation)
        let foreign = try Field(using:&a)
        do { _ = try issuer.lifted(original,from:lc,to:rc,leftAction:la,rightAction:actions.issue(source:rs,field:foreign,limits:l.source,using:&a),limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.incompatibleDomain) {}
        typealias SphereFamily = AffineChildIdentityProof.Family
        typealias SphereParent = PairedImage<Child>
        let sphere = try AffineChildIdentityProof.family(.sphere,&a),fiber = sphere.law.collapsedFibers[0]
        let fixed = try ExactParameterInterval.checked(field:q,lower:.finite(fiber.fixedValue),upper:.finite(fiber.fixedValue),depth:.init(value:0,coefficient:0),using:&a)
        let selected = try sphere.support.frame.selection(intervals:[[TransportFixtures.interval(-2,2,using:&a)],[fixed]],limits:l,using:&a)
        let collapse = try DefaultOriginalParameterIdentityIssuer<Child,ExactRationalScalarDomain>().collapsed(cover:sphere,on:selected,fiber:0,limits:l,using:&a)
        let sl = try ComposedDomainFixtures.bind(SphereParent(originalChild:sphere.source,gains:[1,1],offsets:[0,0],axes:[0,1]),depth:1,using:&a)
        let sr = try ComposedDomainFixtures.bind(SphereParent(originalChild:sphere.source,gains:[-1,1],offsets:[0,0],axes:[0,1]),depth:1,using:&a)
        let sd = DefaultOriginalParameterImageDomainIssuer<SphereParent,SphereFamily>()
        let sc = try sd.issue(source:sl,child:sphere,limits:l,using:&a),tc = try sd.issue(source:sr,child:sphere,limits:l,using:&a)
        let sa = DefaultOriginalParameterImageActionIssuer<SphereParent,ExactRationalScalarDomain>()
        let product = try DefaultOriginalAffinePairedParameterIdentityIssuer<SphereParent,SphereFamily,SphereFamily>().lifted(collapse,from:sc,to:tc,leftAction:sa.issue(source:sl,field:q,limits:l.source,using:&a),rightAction:sa.issue(source:sr,field:q,limits:l.source,using:&a),limits:l,using:&a)
        let si = DefaultOriginalParameterIdentityIssuer<SphereParent,ExactRationalScalarDomain>()
        guard case .completeProduct = try si.relation(of:product,limits:l,using:&a).constraints else { throw ExactScalarFailure.invalidEvidence }
        let u = try q.integer(-2,using:&a),v = fiber.fixedValue
        try TransportFixtures.require(si.decide(product,left:[u,v],right:[u,v],limits:l,using:&a) == .proven)
        let near = try q.subtracting(v,q.dividing(q.integer(1,using:&a),q.integer(1000000,using:&a),using:&a),using:&a)
        try TransportFixtures.require(si.decide(product,left:[u,near],right:[u,near],limits:l,using:&a) == .notEstablished)
        print("PASS paired physical/product identities: exact pi, foreign action field refusal, complete collapsed UV product and near-pole exclusion")
    }
}
