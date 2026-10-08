#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactTopologyFormula {
    /// Perrucci/Roy, arXiv:1609.02879, Notation 3 and Proposition 4:
    /// the greatest differing derivative sign orders realizable Thom sign vectors.
    /// Higher matching signs and the next derivative orientation certify the whole
    /// comparison, including repeated roots; no numerical root station is used.
    mutating func orderedBoundary<A: ExactScalarAdmission & ~Copyable>(
        _ root: ExactRealCellBoundaryRoot<Base>, map: [Int], lower: Bool,
        weak: Bool, _ a: inout A
    ) throws {
        guard root.derivativeSigns.count >= 2, root.derivativeSigns.first == .zero else {
            throw ExactRealTopologyFailure.invalidDefinition
        }
        let source = try ExactPolynomialDomain(retaining: root.polynomial, using: &a)
        try ExactTopologyAccess.storage(root.derivativeSigns.count, Polynomial.self, &a)
        var derivatives: [Polynomial] = []; derivatives.reserveCapacity(root.derivativeSigns.count)
        var law = root.polynomial
        for order in root.derivativeSigns.indices {
            derivatives.append(try remap(law, map, &a))
            if order + 1 < root.derivativeSigns.count { law = try source.differentiated(law, in: root.axis, using: &a) }
        }
        try instruction(.literal(false), &a)
        for order in 0..<(root.derivativeSigns.count - 1) {
            try a.consumeWork(1)
            let orientation = root.derivativeSigns[order + 1]
            if orientation == .zero { continue }
            let greater = lower == (orientation == .positive)
            let relation: ExactRealCellSignRelation
            switch (root.derivativeSigns[order], greater) {
            case (.negative, true): relation = .greaterOrEqual
            case (.zero, true): relation = .greater
            case (.positive, true): continue
            case (.negative, false): continue
            case (.zero, false): relation = .less
            case (.positive, false): relation = .lessOrEqual
            }
            try instruction(.literal(true), &a)
            for higher in (order + 1)..<root.derivativeSigns.count {
                try atom(derivatives[higher], Self.relation(root.derivativeSigns[higher], weak: false), &a)
                try instruction(.and, &a)
            }
            try atom(derivatives[order], relation, &a); try instruction(.and, &a)
            try instruction(.or, &a)
        }
        if weak {
            try instruction(.literal(true), &a)
            for order in root.derivativeSigns.indices {
                try atom(derivatives[order], Self.relation(root.derivativeSigns[order], weak: false), &a)
                try instruction(.and, &a)
            }
            try instruction(.or, &a)
        }
    }
}
