struct ExactCurveIdentity: Hashable, Comparable, Sendable {
    let ordinal: Int

    static func < (lhs: ExactCurveIdentity, rhs: ExactCurveIdentity) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}
