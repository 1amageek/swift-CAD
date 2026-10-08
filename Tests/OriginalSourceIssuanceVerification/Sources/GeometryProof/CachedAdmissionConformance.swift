@testable import L0
import protocol CADGeometry.RationalAlgebraAdmitting
import enum CADGeometry.ExactResource

// Only the cached-module verification has two nominal copies of the legacy
// protocol. Production has one. The existing scoped L0 borrow implements both
// witnesses; no pointer, allowance or coefficient value crosses this bridge.
extension L0.ExactScalarRationalAdmission: CADGeometry.RationalAlgebraAdmitting where A: ~Copyable {
    public var exactDepthResource: CADGeometry.ExactResource { .valueDepth }
}
