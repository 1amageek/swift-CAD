/// A kernel error reads as its message wherever it is shown or interpolated, so a refusal
/// reaches the person as "Fillet radius must fit both endpoint edges." rather than as the
/// value's fields; the phase, code and context stay in its debug description.
extension KernelError: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { message }

    public var debugDescription: String {
        var fields = ["phase: \(phase)", "code: \(code)"]
        if let featureID { fields.append("featureID: \(featureID)") }
        if let subshapeID { fields.append("subshapeID: \(subshapeID)") }
        if let residual { fields.append("residual: \(residual)") }
        if let tolerance { fields.append("tolerance: \(tolerance)") }
        fields.append("message: \(message)")
        return "KernelError(\(fields.joined(separator: ", ")))"
    }
}

#if !hasFeature(Embedded)
import Foundation

extension KernelError: LocalizedError {
    public var errorDescription: String? { message }
}
#endif
