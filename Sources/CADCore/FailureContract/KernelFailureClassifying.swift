/// Source-independent classification without discarding an error's retained cause.
public protocol KernelFailureClassifying: Error {
    var kernelFailure: KernelError { get }
}
