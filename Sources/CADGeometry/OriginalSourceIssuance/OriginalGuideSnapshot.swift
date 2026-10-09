import CADCore

/// Original constructor remains the immutable C0 partition/join proof owner.
public struct OriginalGuideSnapshot<Child:Sendable>:OriginalGuideSourceReading {
    public typealias Traversal=OriginalTraversalSpanSnapshot<Child>
    public typealias Coefficient=OriginalExactScalar
    public let original:OriginalGuideTraversalChain3D
    public let field:OriginalExactScalarDomain
    public let traversals:[OriginalSourceBinding<Traversal>]
    public let stations:[OriginalExactScalar]
    public var originalTraversalCount:Int { traversals.count }
    public func originalTraversal(at index:Int)->OriginalSourceBinding<Traversal> { traversals[index] }
    public func originalStation(at index:Int)->OriginalExactScalar { stations[index] }
    public func originalSegmentOrdinal(at index:Int)->Int { original.sourceSegmentOrdinals[index] }
    init(original:OriginalGuideTraversalChain3D,field:OriginalExactScalarDomain,
        traversals:[OriginalSourceBinding<Traversal>],stations:[OriginalExactScalar]) {
        self.original=original;self.field=field;self.traversals=traversals;self.stations=stations
    }
}
