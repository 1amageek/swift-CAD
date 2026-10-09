import L0
import L1
import DI0
import DI
import SourceIssuer

struct AnalyticCoordinateInput: OriginalAnalyticCoordinateReading {
    let coordinateKind: OriginalAnalyticCoordinateKind
    var firstMagnitude: Double = 3
    var secondMagnitude: Double = 2
    var coneHalfAngle: Double = 0.5
    var phases: [OriginalSourceAngularMap] = [.intrinsic,.intrinsic]
    var matrix: [Double] = [1,0,0,0,1,0,0,0,1]
    var origin: [Double] = [1,2,3]
    func center(in axis: Int) -> Double { origin[axis] }
    func frame(row: Int,column: Int) -> Double { matrix[row*3+column] }
    func angularMap(axis: Int) -> OriginalSourceAngularMap { phases[axis] }
    func finiteLowerBound(axis: Int) -> Double? { nil }
    func finiteUpperBound(axis: Int) -> Double? { nil }
}
struct AnalyticCoordinateProvider: OriginalSourceSnapshotting {
    func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing AnalyticCoordinateInput,limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<AnalyticCoordinateInput> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard input.matrix.count == 9,input.origin.count == 3,input.phases.count == 2 else { throw OriginalSourceIssuanceFailure.invalidSource }
            return .init(original:copy input,sourceDepth:0)
        } catch let e as OriginalSourceIssuanceFailure { throw e }
        catch let e as ExactScalarFailure { throw .scalar(e) }
        catch { throw .sourceRejected(error) }
    }
}
public enum AnalyticDomainFixtures {
    public static func intrinsicWholeDomains() throws {
        var a = try TransportFixtures.admission(); let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        let sourceIssuer = DefaultOriginalAnalyticCoordinateIssuer<AnalyticCoordinateInput,ExactRationalScalarDomain>()
        let domainIssuer = DefaultOriginalAnalyticDomainIssuer<AnalyticCoordinateInput,ExactRationalScalarDomain>()
        let allKinds: [OriginalAnalyticCoordinateKind] = [.circle,.ellipse,.hyperbola,.parabola,.cylinder,.cone,.sphere,.torus]
        for kind in allKinds {
            let input = AnalyticCoordinateInput(coordinateKind:kind)
            let source = try DefaultOriginalSourceBindingIssuer(provider:AnalyticCoordinateProvider()).bind(input,limits:l.source,using:&a)
            let law = try sourceIssuer.issue(source:source,field:f,limits:l.source,using:&a)
            let frame = try domainIssuer.frame(law:law,limits:l,using:&a)
            if kind == .hyperbola || kind == .parabola {
                let noFamilies = try TransportFixtures.limits(families:0)
                let zeroRank = try domainIssuer.issue(request:frame.fullSelection(limits:noFamilies,using:&a),law:law,limits:noFamilies,using:&a)
                try TransportFixtures.require(zeroRank.incident(at:[f.integer(0,using:&a)],limits:noFamilies,using:&a).count == 1)
            }
            let cover = try domainIssuer.issue(request:frame.fullSelection(limits:l,using:&a),law:law,limits:l,using:&a)
            try TransportFixtures.require(law.axes.count == kind.arity && law.position.count == 3)
            let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
            var tuple = [zero]; if kind.arity == 2 { tuple.append(zero) }
            let incidents = try cover.incident(at:tuple,limits:l,using:&a)
            let expected = kind == .torus ? 4 : kind.isPeriodic(axis:0) ? 2 : 1
            try TransportFixtures.require(incidents.count == expected)
            var functions: [ExactRationalCoefficient]
            switch kind {
            case .circle,.ellipse,.hyperbola: functions = [one,zero]
            case .parabola: functions = [try f.integer(6,using:&a)]
            case .cylinder: functions = [one,zero,try f.integer(-7,using:&a)]
            case .cone: functions = [one,zero,zero,zero,one]
            case .sphere,.torus: functions = [one,zero,one,zero]
            }
            var xyz: [ExactRationalCoefficient] = []
            for polynomial in law.position { xyz.append(try law.polynomials.evaluated(polynomial,at:functions,using:&a).value) }
            let expectedXYZ: [Int]
            switch kind {
            case .circle,.ellipse,.hyperbola,.sphere: expectedXYZ = [4,2,3]
            case .parabola: expectedXYZ = [4,8,3]
            case .cylinder: expectedXYZ = [4,2,-4]
            case .cone: expectedXYZ = [1,2,3]
            case .torus: expectedXYZ = [6,2,3]
            }
            for axis in 0..<3 { try TransportFixtures.require(f.compare(xyz[axis],f.integer(expectedXYZ[axis],using:&a),using:&a) == .equal) }
            if kind == .sphere {
                try TransportFixtures.require(law.collapsedFibers.count == 2)
                let pole = try f.binary64(exactly:Double.pi * 0.5,using:&a)
                try TransportFixtures.require(cover.incident(at:[zero,pole],limits:l,using:&a).count == 2)
                let outside = try f.binary64(exactly:(Double.pi * 0.5).nextUp,using:&a)
                try TransportFixtures.require(cover.incident(at:[zero,outside],limits:l,using:&a).isEmpty)
                try TransportFixtures.require(f.compare(law.collapsedFibers[1].position[2],f.integer(6,using:&a),using:&a) == .equal)
            } else if kind == .cone {
                try TransportFixtures.require(law.collapsedFibers.count == 1)
                try TransportFixtures.require(cover.incident(at:[zero,f.integer(-1000000,using:&a)],limits:l,using:&a).count == 2)
                try TransportFixtures.require(cover.incident(at:[zero,f.integer(1000000,using:&a)],limits:l,using:&a).count == 2)
            }
            if kind.isPeriodic(axis:0) {
                let huge = try f.canonical(sign:-1,numerator:[0,0,0,1],denominator:[1],using:&a)
                let original = try f.multiplying(huge,law.periods[0].period,using:&a)
                tuple[0] = original
                try TransportFixtures.require(cover.incident(at:tuple,limits:l,using:&a).count == expected)
            }
        }
        var singular = AnalyticCoordinateInput(coordinateKind:.cylinder)
        singular.matrix = [1,0,0,0,0,0,0,0,1]
        let source = try DefaultOriginalSourceBindingIssuer(provider:AnalyticCoordinateProvider()).bind(singular,limits:l.source,using:&a)
        do { _ = try sourceIssuer.issue(source:source,field:f,limits:l.source,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.invalidSource {}
        let negative = try DefaultOriginalSourceBindingIssuer(provider:AnalyticCoordinateProvider()).bind(
            AnalyticCoordinateInput(coordinateKind:.torus,firstMagnitude:1,secondMagnitude:2),limits:l.source,using:&a)
        do { _ = try sourceIssuer.issue(source:negative,field:f,limits:l.source,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.invalidSource {}
    }
}

extension AnalyticDomainFixtures {
    public static func physicalPhasePeriodsAndPoles() throws {
        var a = try TransportFixtures.admission(valueDepth:128)
        let f = try OriginalPiScalarDomain(using:&a),q = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        let pi = try f.pi(using:&a),twoPi = try f.multiplying(f.integer(2,using:&a),pi,using:&a)
        let binaryPeriod = try f.binary64(exactly:2 * Double.pi,using:&a)
        try TransportFixtures.require(f.compare(twoPi,binaryPeriod,using:&a) == .greater)
        let gain = try q.integer(-2,using:&a),offset = try q.integer(1,using:&a)
        let physical = OriginalSourceAngularMap.physicalRadians(gain:gain,offset:offset)
        let provider = DefaultOriginalSourceBindingIssuer(provider:AnalyticCoordinateProvider())
        let source = try provider.bind(AnalyticCoordinateInput(coordinateKind:.torus,phases:[physical,physical]),limits:l.source,using:&a)
        let issuer = DefaultOriginalPhysicalAnalyticCoordinateIssuer<AnalyticCoordinateInput,OriginalPiScalarDomain>()
        let law = try issuer.issue(source:source,field:f,limits:l.source,using:&a)
        try TransportFixtures.require(law.periods.count == 2 && law.axes.allSatisfy { $0.meaning == .physicalRadian })
        try TransportFixtures.require(f.compare(law.periods[0].period,pi,using:&a) == .equal)
        let domain = DefaultOriginalAnalyticDomainIssuer<AnalyticCoordinateInput,OriginalPiScalarDomain>()
        let frame = try domain.frame(law:law,limits:l,using:&a)
        let cover = try domain.issue(request:frame.fullSelection(limits:l,using:&a),law:law,limits:l,using:&a)
        let zero = try f.integer(0,using:&a)
        try TransportFixtures.require(cover.incident(at:[zero,zero],limits:l,using:&a).count == 4)
        try TransportFixtures.require(cover.incident(at:[pi,pi],limits:l,using:&a).count == 4)
        let hugeRational = try q.canonical(sign:1,numerator:[0,0,0,1],denominator:[1],using:&a)
        let huge = try OriginalParameterCycle(exact:hugeRational,using:&a),noCycle = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        let member = try cover.member(template:0,cycles:[huge,noCycle],limits:l,using:&a)
        var largePower = try f.integer(1,using:&a)
        let wordBase = try f.integer(UInt64(1) << 32,using:&a)
        for _ in 0..<3 { largePower = try f.multiplying(largePower,wordBase,using:&a) }
        let largePi = try f.multiplying(largePower,pi,using:&a)
        let station = try DefaultOriginalParameterTransporter<AnalyticCoordinateInput,OriginalPiScalarDomain>().forward([zero,zero],through:member,limits:l,using:&a)
        try TransportFixtures.require(f.compare(station[0],largePi,using:&a) == .equal)

        let sphere = try provider.bind(AnalyticCoordinateInput(coordinateKind:.sphere,phases:[physical,physical]),limits:l.source,using:&a)
        let sphereLaw = try issuer.issue(source:sphere,field:f,limits:l.source,using:&a)
        try TransportFixtures.require(sphereLaw.collapsedFibers.count == 2)
        let sphereFrame = try domain.frame(law:sphereLaw,limits:l,using:&a)
        let sphereCover = try domain.issue(request:sphereFrame.fullSelection(limits:l,using:&a),law:sphereLaw,limits:l,using:&a)
        for pole in sphereLaw.collapsedFibers {
            try TransportFixtures.require(sphereCover.incident(at:[zero,pole.fixedValue],limits:l,using:&a).count == 2)
        }
        guard let upper = sphereLaw.axes[1].upper else { throw ExactScalarFailure.invalidEvidence }
        let outside = try f.adding(upper,f.dividing(f.integer(1,using:&a),f.integer(1000000,using:&a),using:&a),using:&a)
        try TransportFixtures.require(sphereCover.incident(at:[zero,outside],limits:l,using:&a).isEmpty)

        let arc = try provider.bind(AnalyticCoordinateInput(coordinateKind:.circle,phases:[.physicalRadianArc(start:q.integer(0,using:&a),end:q.integer(1,using:&a),additionalTurns:1),.intrinsic]),limits:l.source,using:&a)
        let arcLaw = try issuer.issue(source:arc,field:f,limits:l.source,using:&a)
        try TransportFixtures.require(arcLaw.axes[0].meaning == .normalizedPhysicalRadianArc)
        let expectedPeriod = try f.dividing(twoPi,f.adding(f.integer(1,using:&a),twoPi,using:&a),using:&a)
        try TransportFixtures.require(f.compare(arcLaw.periods[0].period,expectedPeriod,using:&a) == .equal)
        let arcFrame = try domain.frame(law:arcLaw,limits:l,using:&a)
        let arcCover = try domain.issue(request:arcFrame.fullSelection(limits:l,using:&a),law:arcLaw,limits:l,using:&a)
        try TransportFixtures.require(arcCover.incident(at:[f.integer(1,using:&a)],limits:l,using:&a).count == 1)
        try TransportFixtures.require(arcCover.incident(at:[f.integer(2,using:&a)],limits:l,using:&a).isEmpty)
        // A physical source cannot mint a binary intrinsic period in Q.
        let rational = ExactRationalScalarDomain()
        do { _ = try DefaultOriginalAnalyticCoordinateIssuer<AnalyticCoordinateInput,ExactRationalScalarDomain>().issue(source:source,field:rational,limits:l.source,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.unsupportedCoefficientField {}
    }
}

