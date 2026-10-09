#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original offset relation in (authored U, authored V, positive q).
public struct OriginalOffsetLawReceipt<S:OriginalOffsetSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:Sendable where F.Source == F.Value {
    public let source:OriginalSourceBinding<S>
    public let child:OriginalRationalChartReceipt<S.Child,C,F>
    public let field:F
    public let polynomials:ExactPolynomialDomain<F>
    public let homogeneous:[ExactPolynomial<F>]
    public let normalSquared:ExactPolynomial<F>
    /// q^2-normalSquared==0 together with q>0 defines the unique original normal length.
    public let positiveRootEquation:ExactPolynomial<F>
    /// Internal knot upper faces are retained chart limits, not owning offset values.
    public let ownsUpperBoundary:[Bool]
    public let proofDepth:ExactScalarDepth
    public var positiveRootVariable:Int { 2 }
    /// Enclosing chart extent only; D!=0 and normalSquared>0 remain mandatory.
    public var enclosingSupport:[OriginalSourceParameterInterval<F.Value>] { child.support }
    public var denominator:ExactPolynomial<F> { homogeneous[3] }
    init(source:OriginalSourceBinding<S>,child:OriginalRationalChartReceipt<S.Child,C,F>,field:F,
        polynomials:ExactPolynomialDomain<F>,homogeneous:[ExactPolynomial<F>],normalSquared:ExactPolynomial<F>,
        positiveRootEquation:ExactPolynomial<F>,ownsUpperBoundary:[Bool],proofDepth:ExactScalarDepth) {
        self.source=source;self.child=child;self.field=field;self.polynomials=polynomials
        self.homogeneous=homogeneous;self.normalSquared=normalSquared
        self.positiveRootEquation=positiveRootEquation;self.ownsUpperBoundary=ownsUpperBoundary;self.proofDepth=proofDepth
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            try child.admitProof(using:&a)
            for law in homogeneous { _ = try polynomials.degree(of:law,in:2,using:&a) }
            _ = try polynomials.degree(of:positiveRootEquation,in:2,using:&a)
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
    /// The root sign and equation are source predicates, not a free extra parameter.
    public func admitsLiftedPosition<A:ExactScalarAdmission & ~Copyable>(at coordinates:[F.Value],
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> Bool {
        do {
            guard coordinates.count==3 else { throw OriginalSourceIssuanceFailure.invalidChart }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:F.Value.self))
            guard try admitsPosition(at:[coordinates[0],coordinates[1]],limits:limits,using:&a),
                try field.sign(of:coordinates[2],using:&a) == .positive else { return false }
            let relation=try polynomials.evaluated(positiveRootEquation,at:coordinates,using:&a).value
            let valid=try field.sign(of:relation,using:&a) == .zero
            try a.checkpoint();return valid
        } catch { throw .init(preserving:error) }
    }
    /// Exact source-domain membership; no numerical query-tolerance claim.
    public func admitsPosition<A:ExactScalarAdmission & ~Copyable>(at parameters:[F.Value],
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> Bool {
        do {
            try admitProof(limits:limits,using:&a)
            guard parameters.count==2 else { throw OriginalSourceIssuanceFailure.invalidChart }
            for axis in 0..<2 {
                if try field.compare(parameters[axis],child.support[axis].lower,using:&a) == .less { return false }
                let upperOrder=try field.compare(parameters[axis],child.support[axis].upper,using:&a)
                if upperOrder == .greater || (upperOrder == .equal && !ownsUpperBoundary[axis]) { return false }
            }
            let d=try child.polynomials.evaluated(child.denominator,at:parameters,using:&a).value
            if try field.sign(of:d,using:&a) == .zero { return false }
            for guardLaw in child.parameterTransport.denominators {
                let guardValue=try child.polynomials.evaluated(guardLaw,at:parameters,using:&a).value
                if try field.sign(of:guardValue,using:&a) == .zero { return false }
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:F.Value.self))
            let values=[parameters[0],parameters[1],try field.integer(0,using:&a)]
            let square=try polynomials.evaluated(normalSquared,at:values,using:&a).value
            let valid=try field.sign(of:square,using:&a) == .positive
            try a.checkpoint();return valid
        } catch { throw .init(preserving:error) }
    }
}
