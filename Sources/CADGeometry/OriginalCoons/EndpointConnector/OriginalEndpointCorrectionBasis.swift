/// Exact generated endpoint correction order, retaining authored tangent constraints.
public enum OriginalEndpointCorrectionBasis: String, Hashable, Sendable {
    case linear
    case cubicHermite
    case quinticHermite

    /// Coefficients of h1(t); h0(t) is exactly 1-h1(t).
    func coefficient(at power: Int) -> Double {
        switch self {
        case .linear: power == 1 ? 1 : 0
        case .cubicHermite:
            switch power { case 2: 3; case 3: -2; default: 0 }
        case .quinticHermite:
            switch power { case 3: 10; case 4: -15; case 5: 6; default: 0 }
        }
    }

    var degree: Int {
        switch self { case .linear: 1; case .cubicHermite: 3; case .quinticHermite: 5 }
    }
}
