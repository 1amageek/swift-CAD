public struct STEPStringResult: Equatable, Sendable {
    public let value: String
    public let consumedWork: Int
    public let outputBytes: Int
    public init(value: String, consumedWork: Int, outputBytes: Int) {
        self.value = value; self.consumedWork = consumedWork; self.outputBytes = outputBytes
    }
}
