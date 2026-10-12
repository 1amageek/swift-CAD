/// Computes typed payload bytes without allocating storage or mutating an admission.
public func exactScalarPayloadBytes<T>(count: Int, of type: T.Type)
    throws(ExactScalarFailure) -> Int {
    guard count >= 0 else { throw .countOverflow }
    let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
    guard !bytes.overflow else { throw .countOverflow }
    return bytes.partialValue
}
