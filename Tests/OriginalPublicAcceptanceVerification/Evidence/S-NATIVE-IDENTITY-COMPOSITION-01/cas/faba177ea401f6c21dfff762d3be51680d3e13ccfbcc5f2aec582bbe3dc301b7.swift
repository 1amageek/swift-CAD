#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

extension ExactParameterDomain: ExactParameterDomainFieldQuerying {
    public func contains<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing F.Value,
        in selection: borrowing ExactParameterSet<F>, queryField: F, using admission: inout A)
        throws(ExactParameterDomainFailure) -> Bool {
        let value = copy value, selection = copy selection
        return try ExactParameterDomainAccess.run(&admission, depth: context.depth) { a in
            try require(selection, &a)
            _ = try queryField.sign(of: value, using: &a)
            // Validate every retained endpoint before exclusion can short-circuit comparison.
            for interval in selection.storage {
                try a.consumeWork(1)
                if case .finite(let lower) = interval.lower { _ = try queryField.sign(of: lower, using: &a) }
                if case .finite(let upper) = interval.upper { _ = try queryField.sign(of: upper, using: &a) }
            }
            return try membership(value, selection, queryField: queryField, &a)
        }
    }
}
