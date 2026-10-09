import L0
import DI0
import DI
import SourceIssuer

public enum FiniteFamilyQueryFixtures {
    public static func completeSelection() throws {
        var a = try TransportFixtures.admission()
        let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        let source = try TransportFixtures.binding(true)
        let issuer = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let space = try issuer.prepare(source:source,field:f,limits:l,using:&a)
        let closed = try space.frame.selection(intervals:[[TransportFixtures.interval(-2,4,using:&a)]],limits:l,using:&a)
        let cover = try issuer.issue(space:space,request:closed,limits:l,using:&a)
        let members = try cover.selectedMembers(limits:l,using:&a)
        try TransportFixtures.require(members.count == 8)
        var left = 0,right = 0
        for m in members {
            if try m.selectedImage.contains([f.integer(-2,using:&a)],limits:l,using:&a) { left += 1 }
            if try m.selectedImage.contains([f.integer(4,using:&a)],limits:l,using:&a) { right += 1 }
        }
        try TransportFixtures.require(left == 2 && right == 2)
        let open = try space.frame.selection(intervals:[[TransportFixtures.interval(-2,4,false,false,using:&a)]],limits:l,using:&a)
        let opened = try issuer.issue(space:space,request:open,limits:l,using:&a)
        try TransportFixtures.require(opened.selectedMembers(limits:l,using:&a).count == 6)
        let singleton = try space.frame.selection(intervals:[[TransportFixtures.interval(0,0,using:&a)]],limits:l,using:&a)
        let seam = try issuer.issue(space:space,request:singleton,limits:l,using:&a)
        try TransportFixtures.require(seam.selectedMembers(limits:l,using:&a).count == 2)
        let full = try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        do { _ = try full.selectedMembers(limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.unsupportedSourceProof {}
        // Disconnected intervals inside one cycle select one occurrence, not
        // duplicate laws or lost selected pieces.
        let fractional = try f.dividing(f.integer(1,using:&a),f.integer(4,using:&a),using:&a)
        let half = try f.adding(fractional,fractional,using:&a)
        let d = space.frame.axisDomains[0]
        let disconnected = try space.frame.selection(intervals:[[d.interval(lower:.finite(fractional),upper:.finite(fractional),using:&a),
            d.interval(lower:.finite(half),upper:.finite(half),using:&a)]],limits:l,using:&a)
        let disconnectedCover = try issuer.issue(space:space,request:disconnected,limits:l,using:&a)
        let pieces = try disconnectedCover.selectedMembers(limits:l,using:&a)
        try TransportFixtures.require(pieces.count == 1 && pieces[0].selectedImage.axes[0].intervalCount == 2)
        let huge = try f.canonical(sign:1,numerator:[0,0,0,1],denominator:[1],using:&a)
        let authored = try f.multiplying(huge,f.integer(2,using:&a),using:&a)
        let giant = try space.frame.selection(intervals:[[d.interval(lower:.finite(authored),upper:.finite(authored),using:&a)]],limits:l,using:&a)
        let giantCover = try issuer.issue(space:space,request:giant,limits:l,using:&a)
        try TransportFixtures.require(giantCover.selectedMembers(limits:l,using:&a).count == 2)
        var baseline = try TerminalAdmission()
        _ = try cover.selectedMembers(limits:l,using:&baseline)
        var cancel = try TerminalAdmission();cancel.cancelAt = baseline.checks
        do { _ = try cover.selectedMembers(limits:l,using:&cancel); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        do { _ = try cover.selectedMembers(limits:TransportFixtures.limits(charts:7),using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.chartLimit {}
    }
}
