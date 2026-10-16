/// One invocation owns all accumulated resources and observes cancellation.
public protocol ExactScalarAdmission: ~Copyable {
    var proofScopes: ExactScalarProofScopes { get set }
    var depth: ExactScalarDepth { get throws(ExactScalarFailure) }
    var exactDepthResource: ExactResource { get }
    mutating func openProofScope(original:ExactScalarDepth?,inherited:ExactScalarDepth?,maximum:ExactScalarDepth?,
        valueAxis:ExactScalarRootAxis,maximumWorkUnits:Int?) throws(ExactScalarFailure) -> ExactScalarProofScopeToken
    mutating func closeProofScope(_ token:ExactScalarProofScopeToken) throws(ExactScalarFailure) -> ExactScalarDepth
    mutating func checkpoint() throws(ExactScalarFailure)
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure)
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure)
    /// One retained root interval or accepted decomposition cell is about to be visited.
    /// Depth is already mapped to the caller axis; wrappers must forward every visit.
    /// The caller owns any cumulative cell ceiling independently of stored-cell limits.
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure)
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure)
}

extension ExactScalarAdmission where Self: ~Copyable {
    public var depth: ExactScalarDepth { get throws(ExactScalarFailure) { proofScopes.depth } }
    public var exactDepthResource: ExactResource { proofScopes.exactDepthResource }
    public mutating func openProofScope(original: ExactScalarDepth? = nil,
        inherited: ExactScalarDepth? = nil, maximum: ExactScalarDepth? = nil,
        valueAxis: ExactScalarRootAxis = .value, maximumWorkUnits: Int? = nil) throws(ExactScalarFailure) -> ExactScalarProofScopeToken {
        try checkpoint()
        guard maximumWorkUnits.map({ $0 >= 0 }) ?? true else { throw .invalidSource }
        let inherited=inherited ?? .zero
        let maximum=maximum ?? .init(uncheckedValue:Int.max,coefficient:Int.max)
        guard inherited.value<=maximum.value else { throw .resourceLimit(.valueDepth) }
        guard inherited.coefficient<=maximum.coefficient else { throw .resourceLimit(.coefficientDepth) }
        try admitDepth(value:inherited.value,coefficient:inherited.coefficient)
        let bytes=try proofScopes.openingStorageBytes()
        if bytes>0 { try retainStorage(bytes:bytes) }
        try checkpoint()
        let token=try proofScopes.open(.init(original:original,inherited:inherited,maximum:maximum,valueAxis:valueAxis),maximumWorkUnits:maximumWorkUnits)
        return token
    }
    public mutating func closeProofScope(_ token:ExactScalarProofScopeToken) throws(ExactScalarFailure) -> ExactScalarDepth {
        try proofScopes.close(token)
    }
    public mutating func withProofScope<Result>(original:ExactScalarDepth? = nil,
        inherited:ExactScalarDepth? = nil,maximum:ExactScalarDepth? = nil,valueAxis:ExactScalarRootAxis = .value,maximumWorkUnits:Int? = nil,
        _ body:(inout Self) throws -> Result) throws -> Result {
        let token=try openProofScope(original:original,inherited:inherited,maximum:maximum,valueAxis:valueAxis,maximumWorkUnits:maximumWorkUnits)
        let result:Result
        do { result=try body(&self) }
        catch {
            try proofScopes.unwind(token)
            throw error
        }
        do { _=try closeProofScope(token) }
        catch {
            try proofScopes.unwind(token)
            throw error
        }
        try checkpoint()
        return result
    }
}
