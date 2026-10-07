#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain: ExactPolynomialGCDProducing {
    func gcd<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing Polynomial,
        _ second: borrowing Polynomial, _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        typealias Task = ExactPolynomialGCDTask<F>
        var tasks: [Task] = []
        func push(_ task: Task, _ usage: inout ExactPolynomialAdmission<A>) throws {
            try usage.consumeWork(1); try ExactPolynomialAccess.storage(1, Task.self, &usage)
            tasks.append(task)
        }
        var last = try wrap([], &usage)
        try push(.gcd(copy first, copy second), &usage)
        while let task = tasks.popLast() {
            try usage.consumeWork(1)
            switch task {
            case .gcd(let a, let b):
                if a.terms.isEmpty { last = try monic(b, &usage); continue }
                if b.terms.isEmpty { last = try monic(a, &usage); continue }
                let aa = try activeVariable(a, &usage), bb = try activeVariable(b, &usage)
                let variable: Int
                if let aa, let bb { variable = max(aa, bb) }
                else if let aa { variable = aa }
                else if let bb { variable = bb }
                else { last = try constant(context.one, &usage); continue }
                try push(.afterFirstContent(a, b, variable), &usage)
                try push(.content(a, variable), &usage)
            case .content(let p, let variable):
                let entries = try coefficients(p, variable, &usage)
                try push(.contentStep(entries, 0, wrap([], &usage)), &usage)
            case .contentStep(let entries, let index, let value):
                let constant = value.terms.isEmpty ? false : try activeVariable(value, &usage) == nil
                if index == entries.count || constant {
                    last = try monic(value, &usage); continue
                }
                try push(.afterContentStep(entries, index + 1), &usage)
                try push(.gcd(value, entries[index].polynomial), &usage)
            case .afterContentStep(let entries, let index):
                try push(.contentStep(entries, index, last), &usage)
            case .afterFirstContent(let a, let b, let variable):
                try push(.afterSecondContent(a, b, variable, last), &usage)
                try push(.content(b, variable), &usage)
            case .afterSecondContent(let a, let b, let variable, let ca):
                let cb = last
                let pa = try exactDivide(a, ca, &usage), pb = try exactDivide(b, cb, &usage)
                try push(.afterSharedContent(pa, pb, variable), &usage)
                try push(.gcd(ca, cb), &usage)
            case .afterSharedContent(let a, let b, let variable):
                if (try degree(a, variable, &usage) ?? -1) < (try degree(b, variable, &usage) ?? -1) {
                    try push(.prs(b, a, last, variable), &usage)
                } else { try push(.prs(a, b, last, variable), &usage) }
            case .prs(let a, let b, let content, let variable):
                if b.terms.isEmpty { last = try monic(multiplying(a, content, &usage), &usage); continue }
                let remainder = try pseudoRemainder(a, b, variable, &usage)
                if remainder.terms.isEmpty { try push(.prs(b, remainder, content, variable), &usage) }
                else {
                    try push(.afterRemainderContent(b, remainder, content, variable), &usage)
                    try push(.content(remainder, variable), &usage)
                }
            case .afterRemainderContent(let b, let remainder, let content, let variable):
                try push(.prs(b, exactDivide(remainder, last, &usage), content, variable), &usage)
            }
        }
        return try wrap(last.terms, &usage)
    }
    public func greatestCommonDivisor<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing Polynomial,
        _ second: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy first, copy second) { try gcd(copy first, copy second, &$0) }
    }
}
