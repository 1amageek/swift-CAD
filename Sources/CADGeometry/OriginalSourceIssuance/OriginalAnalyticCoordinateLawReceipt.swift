#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete original X/Y/Z polynomial pullback through the defined coordinate
/// functions, with identity authored UV correspondence and whole original support.
public struct OriginalAnalyticCoordinateLawReceipt<S: OriginalAnalyticCoordinateReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let source: OriginalSourceBinding<S>
    public let field: F
    public let polynomials: ExactPolynomialDomain<F>
    public let position: [ExactPolynomial<F>]
    public let functions: [OriginalSourceCoordinateFunction<F.Value>]
    public let axes: [OriginalSourceCoordinateAxis<F.Value>]
    public let periods: [OriginalSourcePeriodReceipt<S,F>]
    public let collapsedFibers: [OriginalSourceCollapsedFiberReceipt<S,F>]
    public let frameDeterminant: F.Value
    init(source: OriginalSourceBinding<S>,field: F,polynomials: ExactPolynomialDomain<F>,position: [ExactPolynomial<F>],functions: [OriginalSourceCoordinateFunction<F.Value>],
        axes: [OriginalSourceCoordinateAxis<F.Value>],periods: [OriginalSourcePeriodReceipt<S,F>],collapsedFibers: [OriginalSourceCollapsedFiberReceipt<S,F>],frameDeterminant: F.Value) {
        self.source = source; self.field = field; self.polynomials = polynomials; self.position = position; self.functions = functions
        self.axes = axes; self.periods = periods; self.collapsedFibers = collapsedFibers; self.frameDeterminant = frameDeterminant
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint(); try source.require(limits)
            _ = try field.sign(of:frameDeterminant,using:&a)
            for p in position { try a.consumeWork(1); _ = try polynomials.degree(of:p,in:0,using:&a) }
            for axis in axes { if let value = axis.lower { _ = try field.sign(of:value,using:&a) }; if let value = axis.upper { _ = try field.sign(of:value,using:&a) } }
            for period in periods { _ = try field.sign(of:period.period,using:&a) }
            for function in functions {
                switch function {
                case .physicalCosine(_,let gain,let offset),.physicalSine(_,let gain,let offset): _ = try field.sign(of:gain,using:&a); _ = try field.sign(of:offset,using:&a)
                default: break
                }
            }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
