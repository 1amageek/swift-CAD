#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

/// Scalar interval storage shared with L2; axis binding belongs to ExactParameterSet.
public struct ExactParameterInterval<Value: Sendable>: Sendable {
    public let lower: ExactParameterBound<Value>
    public let upper: ExactParameterBound<Value>
    public let includesLower: Bool
    public let includesUpper: Bool
    public let isEmpty: Bool
    public let depth: ExactScalarDepth

    init(lower: ExactParameterBound<Value>, upper: ExactParameterBound<Value>,
        includesLower: Bool, includesUpper: Bool, isEmpty: Bool, depth: ExactScalarDepth) {
        self.lower = lower; self.upper = upper
        self.includesLower = includesLower; self.includesUpper = includesUpper
        self.isEmpty = isEmpty; self.depth = depth
    }
    public static func checked<F: ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
        field: F, lower: ExactParameterBound<Value>, upper: ExactParameterBound<Value>,
        includesLower: Bool = true, includesUpper: Bool = true,
        depth: ExactScalarDepth, using admission: inout A
    ) throws(ExactParameterDomainFailure) -> Self where F.Value == Value {
        try ExactParameterDomainAccess.run(&admission, depth: depth) { a in
            if case .positiveInfinity = lower { throw ExactParameterDomainFailure.invalidDomain }
            if case .negativeInfinity = upper { throw ExactParameterDomainFailure.invalidDomain }
            if case .finite = lower, case .finite = upper {
                // The required comparison validates both operands in this field.
            } else {
                if case .finite(let v) = lower { _ = try field.sign(of: v, using: &a) }
                if case .finite(let v) = upper { _ = try field.sign(of: v, using: &a) }
            }
            let order = try ExactParameterDomainAccess.compare(lower, upper, field: field, using: &a)
            guard order != .greater else { throw ExactParameterDomainFailure.invalidDomain }
            let il: Bool = { if case .finite = lower { return includesLower }; return false }()
            let iu: Bool = { if case .finite = upper { return includesUpper }; return false }()
            return Self(lower: lower, upper: upper, includesLower: il, includesUpper: iu,
                isEmpty: order == .equal && !(il && iu), depth: depth)
        }
    }
    public static func empty<A: ExactScalarAdmission & ~Copyable>(depth: ExactScalarDepth,
        using admission: inout A) throws(ExactParameterDomainFailure) -> Self {
        try ExactParameterDomainAccess.run(&admission, depth: depth) { _ in
            Self(lower: .negativeInfinity, upper: .positiveInfinity,
                includesLower: false, includesUpper: false, isEmpty: true, depth: depth)
        }
    }
    /// Adds a consumer's causal depths without weakening retained evidence.
    public func retainingDepth<A: ExactScalarAdmission & ~Copyable>(_ inherited: ExactScalarDepth,
        using admission: inout A) throws(ExactParameterDomainFailure) -> Self {
        do {
            let next = try ExactParameterDomainAccess.joined(depth, inherited)
            return try ExactParameterDomainAccess.run(&admission, depth: next) { _ in
                Self(lower: lower, upper: upper, includesLower: includesLower,
                    includesUpper: includesUpper, isEmpty: isEmpty, depth: next)
            }
        } catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch let failure as ExactParameterDomainFailure { throw failure }
        catch { throw .operationRejected(error) }
    }
}
