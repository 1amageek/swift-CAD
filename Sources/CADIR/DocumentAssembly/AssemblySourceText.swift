/// Exact authored UTF-8 identity; a value/COW string view, without explicit normalization or buffer materialization.
struct AssemblySourceText: Hashable, Sendable {
    let value: String
    init(_ value: String) { self.value = value }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value.utf8.elementsEqual(rhs.value.utf8)
    }
    func hash(into hasher: inout Hasher) {
        for byte in value.utf8 { hasher.combine(byte) }
    }
    static func equal(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return Self(left) == Self(right)
        default: return false
        }
    }
}
