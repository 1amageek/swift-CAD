import L0
import L1
import L2

public enum CellVisitFixtures {
    private enum Rejection: Error, Equatable { case exhausted, retainedCause }
    private struct Recorder: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var visits: [(axis: ExactScalarRootAxis, depth: Int)] = []
        var checkpoints = 0
        let maximumVisits: Int
        var rejectAt: Int? = nil
        var cancelAt: Int? = nil

        init(maximumVisits: Int = Int.max) throws {
            self.maximumVisits = maximumVisits
            ledger = .init(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
                valueDepth: 100, coefficientDepth: 100))
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints == cancelAt { throw .cancelled }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes: bytes) }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            try ledger.admitDepth(value: value, coefficient: coefficient)
        }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try checkpoint()
            guard visits.count < maximumVisits else { throw .admissionRejected(Rejection.exhausted) }
            if visits.count + 1 == rejectAt { throw .admissionRejected(Rejection.retainedCause) }
            try ledger.visitCell(axis: axis, depth: depth)
            visits.append((axis, depth))
            try checkpoint()
        }
    }

    private static func workload<A: ExactScalarAdmission & ~Copyable>(
        _ domain: ExactRealRootDomain<ExactRationalScalarDomain>,
        sources: [ExactRealRootSource<ExactRationalScalarDomain>],
        all: ExactRealRootInterval<ExactRationalCoefficient>, width: ExactRationalCoefficient,
        using a: inout A
    ) throws {
        for source in sources {
            let roots = try domain.isolate(source, in: all, limits: .init(maximumRoots: 2), using: &a)
            try RootFixtures.require(roots.classification == .finite(distinct: 2, totalMultiplicity: 2))
            let root = roots.roots[1]
            let refined = try domain.refine(root, maximumWidth: width, using: &a)
            try RootFixtures.require(refined.ordinal == root.ordinal && refined.multiplicity == root.multiplicity)
        }
    }

    public static func run() throws {
        var preparation = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let field = ExactRationalScalarDomain(), domain = try ExactRealRootDomain(field: field, using: &preparation)
        let p = domain.polynomials, x = try p.variable(0, using: &preparation)
        let two = try field.integer(2, using: &preparation)
        let law = try p.subtracting(p.multiplying(x, x, using: &preparation), p.constant(two, using: &preparation), using: &preparation)
        let valueSource = try domain.bind(law, refinementAxis: .value, using: &preparation)
        let coefficientSource = try domain.bind(law, refinementAxis: .coefficient, using: &preparation)
        let sources = [valueSource, coefficientSource]
        let all = try domain.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &preparation)
        let width = try field.dividing(field.integer(1, using: &preparation), field.integer(256, using: &preparation), using: &preparation)
        var observed = try Recorder()
        try workload(domain, sources: sources, all: all, width: width, using: &observed)
        let count = observed.visits.count
        try RootFixtures.require(count > 2)
        for axis in [ExactScalarRootAxis.value, .coefficient] {
            var previous = 0, found = false, refined = false
            for visit in observed.visits where visit.axis == axis {
                try RootFixtures.require(visit.depth >= previous)
                previous = visit.depth; found = true; refined = refined || visit.depth > 0
            }
            try RootFixtures.require(found && refined)
        }
        var exact = try Recorder(maximumVisits: count)
        try workload(domain, sources: sources, all: all, width: width, using: &exact)
        try RootFixtures.require(exact.visits.count == count && exact.ledger.work == observed.ledger.work
            && exact.ledger.storageBytes == observed.ledger.storageBytes)
        var short = try Recorder(maximumVisits: count - 1)
        do {
            try workload(domain, sources: sources, all: all, width: width, using: &short)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.admissionRejected(let cause)) {
            guard let failure = cause as? Rejection, failure == .exhausted else { throw ExactRealRootFailure.invalidEvidence }
        }
        try RootFixtures.require(short.visits.count == count - 1)
        var rejected = try Recorder()
        rejected.rejectAt = 2
        do {
            try workload(domain, sources: sources, all: all, width: width, using: &rejected)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.admissionRejected(let cause)) {
            guard let failure = cause as? Rejection, failure == .retainedCause else { throw ExactRealRootFailure.invalidEvidence }
        }
        var cancelled = try Recorder()
        cancelled.cancelAt = observed.checkpoints
        do {
            try workload(domain, sources: sources, all: all, width: width, using: &cancelled)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.cancelled) { }
        try exactCandidate(domain, x, all, using: &preparation)
        print("PASS: L2 isolate/refine cumulative visits N=\(count), both axes, exact ceiling, cause and final cancellation")
    }

    private static func exactCandidate(_ domain: ExactRealRootDomain<ExactRationalScalarDomain>,
        _ x: ExactPolynomial<ExactRationalScalarDomain>, _ all: ExactRealRootInterval<ExactRationalCoefficient>,
        using preparation: inout ExactScalarLedger
    ) throws {
        let field = ExactRationalScalarDomain(), p = domain.polynomials
        let one = try field.integer(1, using: &preparation)
        let source = try domain.bind(p.subtracting(x, p.constant(one, using: &preparation), using: &preparation),
            refinementAxis: .coefficient, using: &preparation)
        let original = try domain.isolate(source, in: all, limits: .init(maximumRoots: 1), using: &preparation).roots[0]
        var observed = try Recorder(maximumVisits: 1)
        let refined = try domain.refine(original, toExactValue: one, using: &observed)
        try RootFixtures.require(observed.visits.count == 1 && observed.visits[0].axis == .coefficient
            && observed.visits[0].depth >= original.isolation.depth.coefficient
            && refined.ordinal == original.ordinal && refined.multiplicity == original.multiplicity)
        var rejected = try Recorder(maximumVisits: 0)
        do {
            _ = try domain.refine(original, toExactValue: one, using: &rejected)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.admissionRejected(let cause)) {
            guard let failure = cause as? Rejection, failure == .exhausted else { throw ExactRealRootFailure.invalidEvidence }
        }
    }
}
