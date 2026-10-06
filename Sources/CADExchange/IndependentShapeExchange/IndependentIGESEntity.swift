/// Shared parser output retaining original IGES directory and parameter associations.
public struct IndependentIGESEntity: Sendable {
    public let pointer: Int
    public let type: Int
    public let form: Int
    public let transformationPointer: Int
    public let label: String
    public let parameters: [String]
    public let associationPointers: [Int]
    public let propertyPointers: [Int]
    public init(pointer: Int, type: Int, form: Int, transformationPointer: Int, label: String, parameters: [String], associationPointers: [Int] = [], propertyPointers: [Int] = []) {
        self.pointer = pointer; self.type = type; self.form = form
        self.transformationPointer = transformationPointer; self.label = label; self.parameters = parameters
        self.associationPointers = associationPointers; self.propertyPointers = propertyPointers
    }
}
