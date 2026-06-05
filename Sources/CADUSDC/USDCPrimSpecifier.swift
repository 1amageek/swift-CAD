public enum USDCPrimSpecifier: Sendable, Equatable {
    case def
    case over
    case `class`
    case unknown(UInt64)

    init(payload: UInt64) {
        switch payload {
        case 0:
            self = .def
        case 1:
            self = .over
        case 2:
            self = .class
        default:
            self = .unknown(payload)
        }
    }
}
