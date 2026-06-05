import CADUSD

enum USDCCrateValue: Sendable, Equatable {
    case token(String)
    case tokenArray([String])
    case string(String)
    case double(Double)
    case vector3(USDCVector3D)
    case matrix4x4(USDCMatrix4x4)
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

    var tokenArrayValue: [String]? {
        if case let .tokenArray(value) = self {
            return value
        }
        return nil
    }

    var vector3Value: USDCVector3D? {
        if case let .vector3(value) = self {
            return value
        }
        return nil
    }

    var matrix4x4Value: USDCMatrix4x4? {
        if case let .matrix4x4(value) = self {
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
