import L0

extension SourceFixtures {
    public static func scalarTransport() throws {
        let root = try selectedRoot(2)
        var preparing = try TraceAdmission()
        let first = try retainedRootBinding(root, using: &preparing)
        let alpha = try first.generator(using: &preparing)
        let other = try retainedRootBinding(try selectedRoot(3), using: &preparing)
        let beta = try other.generator(using: &preparing)
        let destination = try OriginalExactScalarDomain(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, using: &preparing)
        let values = [alpha, beta, alpha]
        let transporter = DefaultOriginalScalarTransporter()
        var measured = try TraceAdmission()
        let receipt = try transporter.transfer(values, into: destination, using: &measured)
        try require(receipt.values.count == 3 && receipt.sources.count == 3)
        var a = try TraceAdmission()
        let field = receipt.field
        let two = try field.integer(2, using: &a), three = try field.integer(3, using: &a)
        try require(try field.compare(field.multiplying(receipt.values[0], receipt.values[0], using: &a), two, using: &a) == .equal)
        try require(try field.compare(field.multiplying(receipt.values[1], receipt.values[1], using: &a), three, using: &a) == .equal)
        try require(try field.compare(receipt.values[0], receipt.values[2], using: &a) == .equal)
        try require(try field.compare(receipt.values[0], receipt.values[1], using: &a) == .less)
        try require(receipt.values.allSatisfy { $0.depth.coefficient >= max(alpha.depth.coefficient, beta.depth.coefficient) })
        do { _ = try destination.importing(alpha, using: &a); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.incompatibleDomain {}
        let ancestor = try transporter.transfer([alpha], into: first, using: &a)
        try require(try ancestor.field.compare(ancestor.values[0], alpha, using: &a) == .equal)
        let escaped = try {
            let temporary = try retainedRootBinding(root, using: &a)
            return try transporter.transfer([temporary.generator(using: &a)], into: destination, using: &a)
        }()
        try require(try escaped.field.compare(escaped.field.multiplying(escaped.values[0], escaped.values[0], using: &a), escaped.field.integer(2, using: &a), using: &a) == .equal)
        let rational = try destination.binary64(exactly: 0.125, using: &a)
        let constant = try transporter.transfer([rational], into: first, using: &a)
        try require(try constant.field.compare(constant.values[0], first.binary64(exactly: 0.125, using: &a), using: &a) == .equal)
        let empty = try transporter.transfer([], into: destination, using: &a)
        try require(empty.values.isEmpty && empty.sources.isEmpty)
        var exact = try TraceAdmission(work: measured.work, storage: measured.storageBytes)
        _ = try transporter.transfer(values, into: destination, using: &exact)
        var work = try TraceAdmission(work: measured.work - 1, storage: measured.storageBytes)
        do { _ = try transporter.transfer(values, into: destination, using: &work); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.resourceLimit(.work) {}
        var storage = try TraceAdmission(work: measured.work, storage: measured.storageBytes - 1)
        do { _ = try transporter.transfer(values, into: destination, using: &storage); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        var entry = try TraceAdmission(); entry.base.cancel()
        do { _ = try transporter.transfer(values, into: destination, using: &entry); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.cancelled {}
        var final = try TraceAdmission(cancelAtStorage: measured.storageCalls)
        do { _ = try transporter.transfer(values, into: destination, using: &final); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.cancelled {}
        let shallow = try OriginalExactScalarDomain(maximumValueDepth: 32,
            maximumCoefficientDepth: 0, using: &a)
        do { _ = try transporter.transfer(values, into: shallow, using: &a); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.resourceLimit(.coefficientDepth) {}
        print("PASS explicit retained scalar transport, exact values, foreign import rejection, lifetime and atomic budgets/depth/cancel")
    }
}
