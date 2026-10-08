import L0
import L1
import L2
import DI0
import DI
import SourceIssuer

struct PlaneInput: OriginalPlaneSourceReading {
    let origin: [Double]
    let normal: [Double]
    func originCoordinate(in axis: Int) -> Double { origin[axis] }
    func normalCoordinate(in axis: Int) -> Double { normal[axis] }
}
struct PlaneProvider: OriginalSourceSnapshotting {
    func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing PlaneInput,
        limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<PlaneInput> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard input.origin.count == 3,input.normal.count == 3 else { throw OriginalSourceIssuanceFailure.invalidSource }
            var nonzero = false
            for i in 0..<3 {
                try a.consumeWork(1)
                guard input.origin[i].isFinite,input.normal[i].isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
                nonzero = nonzero || input.normal[i] != 0
            }
            guard nonzero else { throw OriginalSourceIssuanceFailure.invalidSource }
            return .init(original:copy input,sourceDepth:0)
        } catch let error as OriginalSourceIssuanceFailure { throw error }
        catch let error as ExactScalarFailure { throw .scalar(error) }
        catch { throw .sourceRejected(error) }
    }
}
enum PlaneFixtureFailure: Error { case roundTrip,roundedAccepted,offPlaneAccepted,depthAccepted,storageAccepted,cancelAccepted,mapDepthAccepted }
public enum PlaneFixtures {
    public static func exactBasisAndUV() throws {
        typealias F = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
        var a = try TransportFixtures.admission(valueDepth:128)
        let limits = try TransportFixtures.limits()
        let base = try F.base(field:.init(),maximumExtensionLevel:2,using:&a)
        let roots = try ExactRealRootDomain(field:base,using:&a),p = roots.polynomials
        let equation = try p.polynomial(terms:[.init(powers:[2],coefficient:base.integer(1,using:&a)),
            .init(powers:[0],coefficient:base.integer(-2,using:&a))],using:&a)
        let law = try roots.bind(equation,refinementAxis:.coefficient,using:&a)
        let interval = try roots.domain(lower:.finite(base.integer(1,using:&a)),upper:.finite(base.integer(2,using:&a)),using:&a)
        let isolated = try roots.isolate(law,in:interval,limits:.init(maximumRoots:1),using:&a).roots[0]
        let refined = try roots.refine(isolated,maximumWidth:base.dividing(base.integer(1,using:&a),base.integer(16,using:&a),using:&a),using:&a)
        let extensionField = try base.adjoin(refined,using:&a)
        let f = extensionField.domain,sqrt2 = extensionField.generator
        let source = try DefaultOriginalSourceBindingIssuer(provider:PlaneProvider()).bind(
            PlaneInput(origin:[2,3,4],normal:[0,1,1]),limits:limits.source,using:&a)
        let issuer = DefaultOriginalPlaneBasisIssuer<PlaneInput,F>()
        let basis = try issuer.issue(source:source,field:f,firstLength:sqrt2,normalLength:sqrt2,limits:limits.source,using:&a)
        let x = try f.integer(3,using:&a),y = try f.integer(4,using:&a)
        let point = try basis.position(u:x,v:y,limits:limits,using:&a)
        let uv = try basis.parameters(of:point,limits:limits,using:&a)
        guard try f.compare(uv[0],x,using:&a) == .equal,try f.compare(uv[1],y,using:&a) == .equal else { throw PlaneFixtureFailure.roundTrip }
        let rounded = try f.binary64(exactly:Double(2).squareRoot(),using:&a)
        do { _ = try issuer.issue(source:source,field:f,firstLength:rounded,normalLength:rounded,limits:limits.source,using:&a); throw PlaneFixtureFailure.roundedAccepted }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        do { _ = try basis.parameters(of:[f.integer(2,using:&a),f.integer(3,using:&a),f.integer(5,using:&a)],limits:limits,using:&a); throw PlaneFixtureFailure.offPlaneAccepted }
        catch OriginalDomainIdentityFailure.outsideSupport {}
        // Reusing the receipt must still admit the retained selected-root depth.
        var shallow = ExactScalarLedger(limits:try .init(work:10_000_000,storageBytes:100_000_000,valueDepth:128,coefficientDepth:0))
        do { _ = try basis.position(u:x,v:y,limits:limits,using:&shallow); throw PlaneFixtureFailure.depthAccepted }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        let t = DefaultOriginalParameterTransporter<PlaneInput,F>()
        let whole = try ExactParameterInterval<F.Value>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,
            depth:.init(value:0,coefficient:0),using:&a)
        let frame = try t.frame(source:source,field:f,support:[[whole]],semantics:[.authoredScalar],limits:limits,using:&a)
        let map = try t.affine(from:frame.fullSelection(limits:limits,using:&a),to:frame,permutation:[0],gains:[sqrt2],offsets:[f.integer(0,using:&a)],limits:limits,using:&a)
        var mapShallow = ExactScalarLedger(limits:try .init(work:10_000_000,storageBytes:100_000_000,valueDepth:128,coefficientDepth:0))
        do { try t.admitted(map,limits:limits,using:&mapShallow); throw PlaneFixtureFailure.mapDepthAccepted }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        let foreign = try F.base(field:.init(),maximumExtensionLevel:2,using:&a)
        let foreignInterval = try ExactParameterInterval<F.Value>.checked(field:foreign,lower:.negativeInfinity,upper:.positiveInfinity,
            depth:.init(value:0,coefficient:0),using:&a)
        let foreignFrame = try t.frame(source:source,field:foreign,support:[[foreignInterval]],semantics:[.authoredScalar],limits:limits,using:&a)
        do { _ = try t.affine(from:frame.fullSelection(limits:limits,using:&a),to:foreignFrame,permutation:[0],
            gains:[foreign.integer(1,using:&a)],offsets:[foreign.integer(0,using:&a)],limits:limits,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.incompatibleDomain) {}
        var denied = try TransportFixtures.admission(storage:0,valueDepth:128)
        do { _ = try basis.position(u:x,v:y,limits:limits,using:&denied); throw PlaneFixtureFailure.storageAccepted }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        var observed = try TerminalAdmission(valueDepth:128,coefficientDepth:128)
        _ = try basis.parameters(of:point,limits:limits,using:&observed)
        var cancelled = try TerminalAdmission(valueDepth:128,coefficientDepth:128); cancelled.cancelAt = observed.checks
        do { _ = try basis.parameters(of:point,limits:limits,using:&cancelled); throw PlaneFixtureFailure.cancelAccepted }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
    }
}
