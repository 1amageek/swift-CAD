/// One attained original parameter and its exact same-law values at a cosine zero.
public struct OriginalAnalyticCosineZeroRoot<Value: Sendable>: Sendable {
    public let parameter: Value
    public let phase: Value
    public let sine: Value
    public let childLabel: Value
    public let position: [Value]
    /// Derivative with respect to the original authored parameter.
    public let derivative: [Value]

    init(parameter: Value, phase: Value, sine: Value, childLabel: Value,
        position: [Value], derivative: [Value]) {
        self.parameter = parameter; self.phase = phase; self.sine = sine
        self.childLabel = childLabel; self.position = position; self.derivative = derivative
    }
}
