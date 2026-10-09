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
        try selectedScalarBinding()
        print("PASS explicit retained scalar transport, exact values, foreign import rejection, lifetime and atomic budgets/depth/cancel")
    }
}

extension SourceFixtures {
    static func selectedScalarBinding() throws {
        var a = try TraceAdmission()
        let base = try OriginalExactScalarDomain(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, using: &a)
        let transporter = DefaultOriginalScalarTransporter()
        let zero = try base.integer(0, using: &a), one = try base.integer(1, using: &a)
        let two = try base.integer(2, using: &a)
        let depth = try ExactScalarDepth(value: 0, coefficient: 0)
        let coefficients = [try base.negated(two, using: &a), zero, one]
        let q = ExactRationalScalarDomain()
        let lower = try q.integer(1, using: &a), upper = try q.integer(2, using: &a)
        var measured = try TraceAdmission()
        let selected = try transporter.bindSelectedRoot(coefficients: coefficients, in: base,
            lower: lower, upper: upper, includesLower: true, includesUpper: true,
            depth: depth, axis: .value, using: &measured)
        let field = selected.field
        try require(try field.compare(field.multiplying(selected.value, selected.value, using: &a),
            field.integer(2, using: &a), using: &a) == .equal)
        for bounds in [(try q.integer(-2, using: &a), upper),
                       (try q.integer(3, using: &a), try q.integer(4, using: &a))] {
            do {
                _ = try transporter.bindSelectedRoot(coefficients: coefficients, in: base,
                    lower: bounds.0, upper: bounds.1, includesLower: true, includesUpper: true,
                    depth: depth, axis: .value, using: &a)
                throw Failure.incorrectEvidence
            } catch ExactScalarFailure.invalidEvidence {}
        }
        do {
            _ = try transporter.bindSelectedRoot(coefficients: [try base.negated(one, using: &a), one],
                in: base, lower: lower, upper: lower, includesLower: false, includesUpper: false,
                depth: depth, axis: .value, using: &a)
            throw Failure.incorrectEvidence
        } catch ExactScalarFailure.invalidEvidence {}
        let mapped = try transporter.transfer([selected.value], into: base, using: &a)
        let secondValue = try field.adding(selected.value, field.integer(1, using: &a), using: &a)
        let secondMapped = try transporter.importing(secondValue, through: mapped, using: &a)
        try require(try mapped.field.compare(mapped.field.subtracting(secondMapped, mapped.values[0], using: &a),
            mapped.field.integer(1, using: &a), using: &a) == .equal)
        let unrelated = try retainedRootBinding(try selectedRoot(3), using: &a)
        do {
            _ = try transporter.importing(unrelated.generator(using: &a), through: mapped, using: &a)
            throw Failure.incorrectEvidence
        } catch ExactScalarFailure.incompatibleDomain {}
        var exact = try TraceAdmission(work: measured.work, storage: measured.storageBytes)
        _ = try transporter.bindSelectedRoot(coefficients: coefficients, in: base, lower: lower, upper: upper,
            includesLower: true, includesUpper: true, depth: depth, axis: .value, using: &exact)
        var storage = try TraceAdmission(storage: measured.storageBytes - 1)
        do {
            _ = try transporter.bindSelectedRoot(coefficients: coefficients, in: base, lower: lower, upper: upper,
                includesLower: true, includesUpper: true, depth: depth, axis: .value, using: &storage)
            throw Failure.incorrectEvidence
        } catch ExactScalarFailure.resourceLimit(.storage) {}
        var final = try TraceAdmission(cancelAtStorage: measured.storageCalls)
        do {
            _ = try transporter.bindSelectedRoot(coefficients: coefficients, in: base, lower: lower, upper: upper,
                includesLower: true, includesUpper: true, depth: depth, axis: .value, using: &final)
            throw Failure.incorrectEvidence
        } catch ExactScalarFailure.cancelled {}
    }
}
