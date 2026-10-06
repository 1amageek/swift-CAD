/// A condition retained from an incomplete production implementation.
/// Its text is descriptive; callers must not parse it to decide geometric validity.
public struct KernelDomainLimitation: Hashable, Sendable {
    public let id: String
    public let operations: [String]
    public let dimensions: [KernelDomainDimension]
    public let condition: String
    public let sourcePath: String
    public let sourceLine: Int

    public init(
        id: String, operations: [String], dimensions: [KernelDomainDimension],
        condition: String, sourcePath: String, sourceLine: Int
    ) {
        self.id = id
        self.operations = operations
        self.dimensions = dimensions
        self.condition = condition
        self.sourcePath = sourcePath
        self.sourceLine = sourceLine
    }

    public func validate(registeredOperations: Set<String>) throws {
        guard !id.isEmpty, !condition.isEmpty, sourceLine > 0,
              sourcePath.hasPrefix("Sources/"), sourcePath.hasSuffix(".swift"),
              !sourcePath.split(separator: "/").contains(".."),
              !operations.isEmpty, Set(operations).count == operations.count,
              operations.allSatisfy(registeredOperations.contains),
              !dimensions.isEmpty, Set(dimensions).count == dimensions.count else {
            throw KernelError(
                phase: .validation, code: .invalidInput, tolerance: nil,
                message: "A capability limitation must bind unique registered operations, dimensions and a source condition."
            )
        }
    }
}

#if !hasFeature(Embedded)
extension KernelDomainLimitation: Codable {}
#endif
