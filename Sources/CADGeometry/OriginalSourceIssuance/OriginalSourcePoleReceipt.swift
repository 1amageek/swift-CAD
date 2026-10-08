#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Source theorem for an entire longitude fiber, preserving the ambient UV arity.
public struct OriginalSourcePoleReceipt<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let anchor: OriginalSourceChart<S,Int>
    public let field: F
    public let latitude: F.Value
    public let position: [F.Value]
    public var source: OriginalSourceBinding<S> { anchor.binding }
    init(anchor: OriginalSourceChart<S,Int>,field: F,latitude: F.Value,position: [F.Value]) {
        self.anchor = anchor; self.field = field; self.latitude = latitude; self.position = position
    }
}
