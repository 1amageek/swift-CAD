public struct AssemblyProductLookupResult: Equatable, Sendable {
    public let product: AssemblyProduct
    public let consumedWork: Int
    public init(product: AssemblyProduct, consumedWork: Int) {
        self.product = product; self.consumedWork = consumedWork
    }
}
