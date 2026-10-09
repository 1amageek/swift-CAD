import L0
import SourceIssuer

public enum PiDomainFixtures {
    public static func exactPiAndFailures() throws {
        var a = try TransportFixtures.admission(work:20_000_000,storage:300_000_000)
        let f = try OriginalPiScalarDomain(using:&a)
        let pi = try f.pi(using:&a),one = try f.integer(1,using:&a),two = try f.integer(2,using:&a)
        try TransportFixtures.require(f.compare(pi,f.integer(3,using:&a),using:&a) == .greater)
        try TransportFixtures.require(f.compare(pi,f.integer(4,using:&a),using:&a) == .less)
        // These adjacent dyadics surround mathematical pi, rather than define it.
        let binary = try f.binary64(exactly:Double.pi,using:&a)
        let above = try f.binary64(exactly:Double.pi.nextUp,using:&a)
        try TransportFixtures.require(f.compare(pi,binary,using:&a) == .greater)
        try TransportFixtures.require(f.compare(pi,above,using:&a) == .less)
        let displaced = try f.subtracting(pi,binary,using:&a)
        try TransportFixtures.require(f.sign(of:displaced,using:&a) == .positive)
        let reciprocal = try f.dividing(one,displaced,using:&a)
        try TransportFixtures.require(f.compare(f.multiplying(reciprocal,displaced,using:&a),one,using:&a) == .equal)
        let period = try f.multiplying(two,pi,using:&a)
        let gain = try f.dividing(f.integer(-3,using:&a),two,using:&a)
        let originalPeriod = try f.dividing(period,f.negated(gain,using:&a),using:&a)
        try TransportFixtures.require(f.compare(f.multiplying(originalPeriod,gain,using:&a),f.negated(period,using:&a),using:&a) == .equal)
        let other = try OriginalPiScalarDomain(using:&a)
        let imported = try other.importing(pi,using:&a)
        try TransportFixtures.require(other.compare(imported,other.pi(using:&a),using:&a) == .equal)
        do { _ = try other.adding(pi,imported,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.incompatibleDomain {}
        let zero = try f.subtracting(pi,pi,using:&a)
        do { _ = try f.dividing(one,zero,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.divisionByZero {}
        var work = try TransportFixtures.admission(work:0)
        do { _ = try f.sign(of:pi,using:&work); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.resourceLimit(.work) {}
        var storage = try TransportFixtures.admission(storage:0)
        do { _ = try f.sign(of:displaced,using:&storage); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        var baseline = try TerminalAdmission()
        _ = try f.sign(of:displaced,using:&baseline)
        var cancel = try TerminalAdmission(); cancel.cancelAt = baseline.checks
        do { _ = try f.sign(of:displaced,using:&cancel); throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.cancelled {}
    }
}
