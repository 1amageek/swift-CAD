import L0
import DI0
import DI
import SourceIssuer

public enum AnalyticIdentityFixtures {
    typealias S = AnalyticCoordinateInput
    public static func intrinsicPeriodsAndFibers() throws {
        var a = try TransportFixtures.admission()
        let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        let producer = DefaultOriginalAnalyticCoordinateIssuer<S,ExactRationalScalarDomain>()
        let domain = DefaultOriginalAnalyticDomainIssuer<S,ExactRationalScalarDomain>()
        let ids = DefaultOriginalParameterIdentityIssuer<S,ExactRationalScalarDomain>()
        let provider = DefaultOriginalSourceBindingIssuer(provider:AnalyticCoordinateProvider())
        let oneCycle = try OriginalParameterCycle(exact:f.integer(1,using:&a),using:&a)
        for kind in [OriginalAnalyticCoordinateKind.circle,.ellipse,.cylinder,.cone,.sphere,.torus] {
            let source = try provider.bind(S(coordinateKind:kind),limits:l.source,using:&a)
            let law = try producer.issue(source:source,field:f,limits:l.source,using:&a)
            let frame = try domain.frame(law:law,limits:l,using:&a)
            let cover = try domain.issue(request:frame.fullSelection(limits:l,using:&a),law:law,limits:l,using:&a)
            for period in law.periods {
                let proof = try ids.periodic(cover:cover,from:cover.effective,axis:period.axis,cycle:oneCycle,limits:l,using:&a)
                var left = [try f.integer(0,using:&a)]
                if frame.arity == 2 { left.append(try f.integer(0,using:&a)) }
                var right = left;right[period.axis] = period.period
                try TransportFixtures.require(ids.decide(proof,left:left,right:right,limits:l,using:&a) == .proven)
                try TransportFixtures.require(ids.decide(proof,left:left,right:left,limits:l,using:&a) == .refutedForThisRelation)
                let view = try ids.relation(of:proof,limits:l,using:&a)
                guard case .affine = view.constraints else { throw ExactScalarFailure.invalidEvidence }
            }
            for index in law.collapsedFibers.indices {
                let fiber = law.collapsedFibers[index]
                let fixed = try ExactParameterInterval.checked(field:f,lower:.finite(fiber.fixedValue),upper:.finite(fiber.fixedValue),depth:.init(value:0,coefficient:0),using:&a)
                let selected = try frame.selection(intervals:[[TransportFixtures.interval(-2,2,using:&a)],[fixed]],limits:l,using:&a)
                let proof = try ids.collapsed(cover:cover,on:selected,fiber:index,limits:l,using:&a)
                let left = try [f.integer(-2,using:&a),fiber.fixedValue]
                let right = try [f.integer(2,using:&a),fiber.fixedValue]
                try TransportFixtures.require(ids.decide(proof,left:left,right:right,limits:l,using:&a) == .proven)
                guard case .completeProduct = try ids.relation(of:proof,limits:l,using:&a).constraints else { throw ExactScalarFailure.invalidEvidence }
                let delta = try f.dividing(f.integer(1,using:&a),f.integer(1000000,using:&a),using:&a)
                let near = kind == .sphere && index == 0 ? try f.adding(fiber.fixedValue,delta,using:&a) : try f.subtracting(fiber.fixedValue,delta,using:&a)
                try TransportFixtures.require(ids.decide(proof,left:[left[0],near],right:[right[0],near],limits:l,using:&a) == .notEstablished)
                let band = try ExactParameterInterval.checked(field:f,lower:.finite(kind == .sphere && index == 0 ? fiber.fixedValue : near),upper:.finite(kind == .sphere && index == 0 ? near : fiber.fixedValue),depth:.init(value:0,coefficient:0),using:&a)
                let invalid = try frame.selection(intervals:[[TransportFixtures.interval(-2,2,using:&a)],[band]],limits:l,using:&a)
                do { _ = try ids.collapsed(cover:cover,on:invalid,fiber:index,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
                catch OriginalDomainIdentityFailure.invalidIdentityProof {}
                let symmetric = try ids.symmetric(proof,limits:l,using:&a)
                try TransportFixtures.require(ids.decide(symmetric,left:right,right:left,limits:l,using:&a) == .proven)
            }
            let foreign = try provider.bind(S(coordinateKind:kind),limits:l.source,using:&a)
            let otherLaw = try producer.issue(source:foreign,field:f,limits:l.source,using:&a)
            let otherFrame = try domain.frame(law:otherLaw,limits:l,using:&a)
            let otherSelection = try otherFrame.fullSelection(limits:l,using:&a)
            do { _ = try ids.periodic(cover:cover,from:otherSelection,axis:0,cycle:oneCycle,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.foreignOwner {}
        }
        print("PASS analytic scoped identities: genuine intrinsic periods, both torus axes, cone vertex/sphere poles, retained UV, foreign and near-pole refusal")
    }
    public static func physicalClippingAndFailures() throws {
        var a = try TransportFixtures.admission(work:20_000_000,storage:300_000_000)
        let f = try OriginalPiScalarDomain(using:&a),q = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        let input = try S(coordinateKind:.circle,phases:[.physicalRadianArc(start:q.integer(0,using:&a),end:q.integer(1,using:&a),additionalTurns:1),.intrinsic])
        let source = try DefaultOriginalSourceBindingIssuer(provider:AnalyticCoordinateProvider()).bind(input,limits:l.source,using:&a)
        let law = try DefaultOriginalPhysicalAnalyticCoordinateIssuer<S,OriginalPiScalarDomain>().issue(source:source,field:f,limits:l.source,using:&a)
        let domain = DefaultOriginalAnalyticDomainIssuer<S,OriginalPiScalarDomain>()
        let frame = try domain.frame(law:law,limits:l,using:&a)
        let cover = try domain.issue(request:frame.fullSelection(limits:l,using:&a),law:law,limits:l,using:&a)
        let ids = DefaultOriginalParameterIdentityIssuer<S,OriginalPiScalarDomain>()
        let cycle = try OriginalParameterCycle(exact:q.integer(1,using:&a),using:&a)
        let proof = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:cycle,limits:l,using:&a)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a),period = law.periods[0].period
        try TransportFixtures.require(!proof.left.isEmpty && ids.decide(proof,left:[zero],right:[period],limits:l,using:&a) == .proven)
        try TransportFixtures.require(!proof.left.contains([one],limits:l,using:&a))
        let twoCycles = try OriginalParameterCycle(exact:q.integer(2,using:&a),using:&a)
        let empty = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:twoCycles,limits:l,using:&a)
        try TransportFixtures.require(empty.left.isEmpty && empty.right.isEmpty)
        let inverse = try ids.symmetric(proof,limits:l,using:&a)
        try TransportFixtures.require(ids.decide(inverse,left:[period],right:[zero],limits:l,using:&a) == .proven)
        let negative = try OriginalParameterCycle(exact:q.integer(-1,using:&a),using:&a)
        let reversed = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:negative,limits:l,using:&a)
        try TransportFixtures.require(ids.decide(reversed,left:[period],right:[zero],limits:l,using:&a) == .proven)
        let dyadic = try f.binary64(exactly:2 * Double.pi,using:&a)
        let guessed = try f.dividing(dyadic,f.adding(one,dyadic,using:&a),using:&a)
        try TransportFixtures.require(ids.decide(proof,left:[zero],right:[guessed],limits:l,using:&a) != .proven)
        do { _ = try ids.periodic(cover:cover,from:cover.effective,axis:1,cycle:cycle,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.unsupportedSourceProof {}
        do { _ = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:cycle,limits:TransportFixtures.limits(families:0),using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.familyLimit {}
        var measured = try TransportFixtures.admission(work:20_000_000,storage:300_000_000)
        _ = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:cycle,limits:l,using:&measured)
        var exact = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        _ = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:cycle,limits:l,using:&exact)
        var shortWork = try TransportFixtures.admission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:cycle,limits:l,using:&shortWork); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var shortStorage = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:cycle,limits:l,using:&shortStorage); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        var baseline = try TerminalAdmission()
        _ = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:cycle,limits:l,using:&baseline)
        var terminal = try TerminalAdmission();terminal.cancelAt = baseline.checks
        do { _ = try ids.periodic(cover:cover,from:cover.effective,axis:0,cycle:cycle,limits:l,using:&terminal); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        print("PASS analytic physical period: mathematical pi, exact finite clipping/empty overlap, reversed cycles, independent budgets and terminal cancel")
    }
}
