import CADCore

public enum DocumentFoundationError: Error, Equatable, Sendable {
    case duplicateAttribute(DocumentAttributeID)
    case duplicateName(String, owner: DocumentObjectReference)
    case invalidName(String)
    case invalidValue(String)
    case foreignOwner(DocumentObjectReference)
    case ownershipCycle(DocumentAttributeID)
    case missingDocument(DocumentID)
    case snapshotIDMismatch(expected: DocumentID, actual: DocumentID)
    case missingTarget(DocumentObjectReference)
    case missingAttribute(DocumentAttributeID)

    public var kernelCode: KernelErrorCode {
        switch self {
        case .missingDocument, .missingTarget, .missingAttribute: .missingReference
        default: .invalidInput
        }
    }
}
