#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Four original directed boundaries; corner identity is proved by the issuer.
public protocol OriginalCoonsSourceReading: Sendable {
    associatedtype Bottom: Sendable
    associatedtype Top: Sendable
    associatedtype Left: Sendable
    associatedtype Right: Sendable
    var bottomBoundary: OriginalSourceBinding<Bottom> { get }
    var topBoundary: OriginalSourceBinding<Top> { get }
    var leftBoundary: OriginalSourceBinding<Left> { get }
    var rightBoundary: OriginalSourceBinding<Right> { get }
}
