#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    public func separate<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactRealRoot<F>,
        _ rhs: borrowing ExactRealRoot<F>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSeparation<F> {
        let lhs = copy lhs, rhs = copy rhs
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try admitted(lhs, &a); try admitted(rhs, &a)
            guard try compare(lhs, rhs, using: &a) == .less else { throw ExactRealRootFailure.invalidDomain }
            var left = lhs, right = rhs
            let p = context.univariate, x = try p.variable(0, using: &a)
            let two = try context.field.integer(2, using: &a)
            while true {
                try a.consumeWork(1)
                guard case .finite(let leftLower) = left.isolation.lower,
                    case .finite(let leftUpper) = left.isolation.upper,
                    case .finite(let rightLower) = right.isolation.lower,
                    case .finite(let rightUpper) = right.isolation.upper else {
                    throw ExactRealRootFailure.invalidEvidence
                }
                if try context.field.compare(leftUpper, rightLower, using: &a) != .greater {
                    let candidate = try context.field.dividing(
                        context.field.adding(leftUpper, rightLower, using: &a), two, using: &a)
                    let law = try p.subtracting(x, p.constant(candidate, using: &a), using: &a)
                    let source = try sourceForLaw(law, variable: lhs.source.variable,
                        axis: lhs.source.refinementAxis, &a)
                    if try sign(of: source, at: left, using: &a) == .negative,
                        try sign(of: source, at: right, using: &a) == .positive {
                        return .init(left: left, right: right, value: candidate, depth: a.depth)
                    }
                }
                // A singleton is already exact. Refining it cannot create a strict gap.
                let refineLeft = try context.field.compare(leftLower, leftUpper, using: &a) != .equal
                let refineRight = try context.field.compare(rightLower, rightUpper, using: &a) != .equal
                guard refineLeft || refineRight else { throw ExactRealRootFailure.invalidEvidence }
                if refineLeft {
                    left = replaced(left, try contracted(left.proof, left.isolation,
                        axis: left.source.refinementAxis, &a), &a)
                }
                if refineRight {
                    right = replaced(right, try contracted(right.proof, right.isolation,
                        axis: right.source.refinementAxis, &a), &a)
                }
            }
        }
    }
}
