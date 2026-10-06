/// Original STEP SI prefixes; their decimal exponent is an exact source law.
public enum IndependentShapeSIPrefix: String, Equatable, Sendable {
    case exa = "EXA", peta = "PETA", tera = "TERA", giga = "GIGA", mega = "MEGA", kilo = "KILO"
    case hecto = "HECTO", deca = "DECA", deci = "DECI", centi = "CENTI", milli = "MILLI"
    case micro = "MICRO", nano = "NANO", pico = "PICO", femto = "FEMTO", atto = "ATTO"
    public var decimalExponent: Int {
        switch self {
        case .exa: 18; case .peta: 15; case .tera: 12; case .giga: 9; case .mega: 6; case .kilo: 3
        case .hecto: 2; case .deca: 1; case .deci: -1; case .centi: -2; case .milli: -3
        case .micro: -6; case .nano: -9; case .pico: -12; case .femto: -15; case .atto: -18
        }
    }
}
#if !hasFeature(Embedded)
extension IndependentShapeSIPrefix: Codable {}
#endif
