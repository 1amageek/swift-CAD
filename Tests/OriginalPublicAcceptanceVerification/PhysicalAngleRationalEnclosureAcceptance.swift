import CADGeometry

enum PhysicalAngleRationalEnclosureAcceptance {
    struct Failure: Error { let line: Int }
    static func require(_ condition: Bool, line: Int = #line) throws {
        guard condition else { throw Failure(line: line) }
    }
    static func ledger(work: Int = 20_000_000, storage: Int = 134_217_728,
        coefficient: Int = 32) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: storage,
            valueDepth: 32, coefficientDepth: coefficient))
    }
    static func run() throws {
        var a = try ledger()
        let q = ExactRationalScalarDomain()
        let zero = try q.integer(0, using: &a), one = try q.integer(1, using: &a)
        let period = try q.binary64(exactly: 2 * Double.pi, using: &a)
        let quarter = try q.dividing(period, q.integer(4, using: &a), using: &a)
        let atQuarter = try OriginalPhysicalAngleRationalEnclosures.normalizedLabelSineCosine(
            lower: quarter, upper: quarter, labelPeriod: period, refinementDepth: 6, using: &a)
        try require(try q.compare(atQuarter.sine.lower, one, using: &a) != .greater)
        try require(try q.compare(atQuarter.sine.upper, one, using: &a) != .less)
        try require(try q.compare(atQuarter.sine.lower,
            q.dividing(q.integer(999, using: &a), q.integer(1000, using: &a), using: &a), using: &a) == .greater)
        try require(try q.sign(of: atQuarter.cosine.lower, using: &a) != .positive)
        try require(try q.sign(of: atQuarter.cosine.upper, using: &a) != .negative)
        // The interior extremum is retained over a nondegenerate interval.
        let margin = try q.dividing(period, q.integer(100, using: &a), using: &a)
        let aroundQuarter = try OriginalPhysicalAngleRationalEnclosures.normalizedLabelSineCosine(
            lower: q.subtracting(quarter, margin, using: &a), upper: q.adding(quarter, margin, using: &a),
            labelPeriod: period, refinementDepth: 6, using: &a)
        try require(try q.compare(aroundQuarter.sine.lower, one, using: &a) != .greater)
        try require(try q.compare(aroundQuarter.sine.upper, one, using: &a) != .less)
        let full = try OriginalPhysicalAngleRationalEnclosures.normalizedLabelSineCosine(
            lower: zero, upper: period, labelPeriod: period, refinementDepth: 6, using: &a)
        let minusOne = try q.integer(-1, using: &a)
        for bounds in [full.sine, full.cosine] {
            try require(try q.compare(bounds.lower, minusOne, using: &a) != .greater)
            try require(try q.compare(bounds.upper, one, using: &a) != .less)
        }
        let physical = try OriginalPhysicalAngleScalarDomain(
            originalRadians: Double(bitPattern: 0x3fddac670561bb50), using: &a)
        for (value, low, high) in [(try physical.sine(using: &a), 4472, 4473),
            (try physical.cosine(using: &a), 8944, 8945)] {
            let bounds = try physical.enclosing(value, refinementDepth: 4, using: &a)
            let lower = try q.dividing(q.integer(low, using: &a), q.integer(10000, using: &a), using: &a)
            let upper = try q.dividing(q.integer(high, using: &a), q.integer(10000, using: &a), using: &a)
            try require(try q.compare(bounds.lower, lower, using: &a) == .greater)
            try require(try q.compare(bounds.upper, upper, using: &a) == .less)
        }
        let radicand = try OriginalPhysicalAngleRationalBounds(lower: q.integer(2, using: &a),
            upper: q.integer(3, using: &a), using: &a)
        let radical = try OriginalPhysicalAngleRationalEnclosures.positiveSquareRoot(
            radicand, refinementDepth: 6, using: &a)
        try require(try q.compare(q.multiplying(radical.lower, radical.lower, using: &a), radicand.lower, using: &a) != .greater)
        try require(try q.compare(q.multiplying(radical.upper, radical.upper, using: &a), radicand.upper, using: &a) != .less)
        try require(try q.compare(radical.lower, one, using: &a) == .greater)
        try require(try q.compare(radical.upper, q.integer(2, using: &a), using: &a) == .less)
        do {
            _ = try OriginalPhysicalAngleRationalBounds(lower: one, upper: zero, using: &a)
            throw Failure(line: #line)
        } catch ExactScalarFailure.invalidEvidence {}
        do {
            _ = try OriginalPhysicalAngleRationalEnclosures.positiveSquareRoot(
                .init(lower: zero, upper: one, using: &a), refinementDepth: 2, using: &a)
            throw Failure(line: #line)
        } catch ExactScalarFailure.invalidEvidence {}
        try resources(period: period, quarter: quarter)
        print("PASS exact physical-angle, full-label interval/extremum, radical squared bounds, resource/depth and cancellation proofs")
    }

    static func resources(period: ExactRationalCoefficient, quarter: ExactRationalCoefficient) throws {
        func calculate<A: ExactScalarAdmission & ~Copyable>(_ a: inout A) throws {
            _ = try OriginalPhysicalAngleRationalEnclosures.normalizedLabelSineCosine(
                lower: quarter, upper: quarter, labelPeriod: period, refinementDepth: 4, using: &a)
        }
        var measured = try ledger()
        try calculate(&measured)
        var exact = try ledger(work: measured.work, storage: measured.storageBytes)
        try calculate(&exact)
        try require(exact.work == measured.work && exact.storageBytes == measured.storageBytes)
        var lowWork = try ledger(work: measured.work - 1)
        do { try calculate(&lowWork); throw Failure(line: #line) }
        catch ExactScalarFailure.resourceLimit(.work) {}
        var lowStorage = try ledger(storage: measured.storageBytes - 1)
        do { try calculate(&lowStorage); throw Failure(line: #line) }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        var lowDepth = try ledger(coefficient: 3)
        do { try calculate(&lowDepth); throw Failure(line: #line) }
        catch ExactScalarFailure.resourceLimit(.coefficientDepth) {}
        var entry = try ledger(); entry.cancel()
        do { try calculate(&entry); throw Failure(line: #line) }
        catch ExactScalarFailure.cancelled {}
        try require(entry.work == 0 && entry.storageBytes == 0)
        var final = try FinalCancellation(storage: measured.storageBytes)
        do { try calculate(&final); throw Failure(line: #line) }
        catch ExactScalarFailure.cancelled {}
        try require(final.ledger.storageBytes == measured.storageBytes)
    }

    struct FinalCancellation: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        let storage: Int
        init(storage: Int) throws {
            self.storage = storage; ledger = try PhysicalAngleRationalEnclosureAcceptance.ledger()
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try ledger.retainStorage(bytes: bytes)
            if ledger.storageBytes == storage { ledger.cancel() }
        }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try ledger.visitCell(axis: axis, depth: depth)
        }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            try ledger.admitDepth(value: value, coefficient: coefficient)
        }
    }
}
