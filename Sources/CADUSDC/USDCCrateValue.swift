import CADUSD

enum USDCCrateValue: Sendable, Equatable {
    case token(String)
    case string(String)
    case double(Double)
    case intArray([Int])
    case pointArray([USDPoint3D])

    var stringValue: String? {
        switch self {
        case let .token(value), let .string(value):
            return value
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        if case let .double(value) = self {
            return value
        }
        return nil
    }

    var intArrayValue: [Int]? {
        if case let .intArray(value) = self {
            return value
        }
        return nil
    }

    var pointArrayValue: [USDPoint3D]? {
        if case let .pointArray(value) = self {
            return value
        }
        return nil
    }
}
