import Foundation

public struct USDZArchiveEntry: Sendable, Equatable {
    public var path: String
    public var data: Data
    public var localHeaderOffset: Int
    public var localExtraFieldByteCount: Int
    public var dataOffset: Int
    public var crc32: UInt32

    public init(
        path: String,
        data: Data,
        localHeaderOffset: Int,
        localExtraFieldByteCount: Int,
        dataOffset: Int,
        crc32: UInt32
    ) {
        self.path = path
        self.data = data
        self.localHeaderOffset = localHeaderOffset
        self.localExtraFieldByteCount = localExtraFieldByteCount
        self.dataOffset = dataOffset
        self.crc32 = crc32
    }

    public var fileExtension: String {
        guard let lastComponent = path.split(separator: "/").last,
              let extensionStart = lastComponent.lastIndex(of: ".") else {
            return ""
        }
        return String(lastComponent[lastComponent.index(after: extensionStart)...]).lowercased()
    }

    public var isUSDLayer: Bool {
        switch fileExtension {
        case "usd", "usda", "usdc":
            true
        default:
            false
        }
    }

    public var isPayload64ByteAligned: Bool {
        dataOffset.isMultiple(of: 64)
    }
}
