import CADCore

extension OriginalExactBoundaryCompiler {
    /// Positive exact scaling preserves every sign while interning scalar associates.
    mutating func canonicalizeAtoms<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws {
        for index in laws.indices {
            try a.consumeWork(1)
            guard let coefficient = laws[index].terms.first?.coefficient else { continue }
            let sign = try field.sign(of:coefficient,using:&a)
            guard sign != .zero else { throw NativeExactRelationFailure.invalidDomain }
            let magnitude = sign == .negative ? try field.negated(coefficient,using:&a):coefficient
            let gain = try field.dividing(field.integer(1,using:&a),magnitude,using:&a)
            laws[index] = try cells.polynomials.scaled(laws[index],by:gain,using:&a)
        }
        try a.checkpoint()
    }

    /// Imports the retained program and every original interval guard without solving it.
    mutating func retainedPredicate<A: ExactScalarAdmission & ~Copyable>(
        _ predicate: ExactRealCellPredicate<Base>, using a: inout A
    ) throws -> Int {
        guard predicate.source.variableCount == cells.polynomials.variableCount else {
            throw NativeExactRelationFailure.invalidDomain
        }
        let original = try ExactRealCellDomain<Base>(retaining:predicate.source,using:&a)
        let originalField = try original.coefficientField(of:predicate.source,using:&a)
        _ = try field.importing(originalField.integer(0,using:&a),using:&a)
        try a.admitDepth(value:predicate.depth.value,coefficient:predicate.depth.coefficient)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:predicate.instructions.count,of:Int.self))
        var stack: [Int] = []; stack.reserveCapacity(predicate.instructions.count)
        for instruction in predicate.instructions {
            try a.consumeWork(1)
            switch instruction {
            case .literal(let value): stack.append(try node(.literal(value),&a))
            case .sign(let index,let relation):
                guard predicate.source.polynomials.indices.contains(index) else { throw NativeExactRelationFailure.invalidDomain }
                stack.append(try atom(cells.polynomials.importing(predicate.source.polynomials[index],using:&a),relation,&a))
            case .not:
                guard let child = stack.popLast() else { throw NativeExactRelationFailure.invalidDomain }
                stack.append(try not(child,&a))
            case .and,.or:
                guard let right = stack.popLast(),let left = stack.popLast() else { throw NativeExactRelationFailure.invalidDomain }
                if case .and = instruction { stack.append(try and(left,right,&a)) }
                else { stack.append(try or(left,right,&a)) }
            }
        }
        guard stack.count == 1, var root = stack.first else { throw NativeExactRelationFailure.invalidDomain }
        let ring = cells.polynomials
        for axis in predicate.source.domains.indices {
            let domain = predicate.source.domains[axis]
            try a.consumeWork(1)
            if domain.isEmpty { root = try and(root,node(.literal(false),&a),&a) }
            for edge in 0..<2 {
                let lower = edge == 0
                let bound = lower ? domain.lower:domain.upper
                switch bound {
                case .finite(let value):
                    let delta = try ring.subtracting(ring.variable(axis,using:&a),
                        ring.constant(field.importing(value,using:&a),using:&a),using:&a)
                    let relation: ExactRealCellSignRelation = lower
                        ? (domain.includesLower ? .greaterOrEqual:.greater)
                        : (domain.includesUpper ? .lessOrEqual:.less)
                    root = try and(root,atom(delta,relation,&a),&a)
                case .negativeInfinity:
                    guard lower else { throw NativeExactRelationFailure.invalidDomain }
                case .positiveInfinity:
                    guard !lower else { throw NativeExactRelationFailure.invalidDomain }
                }
            }
        }
        try a.checkpoint()
        return root
    }
}
