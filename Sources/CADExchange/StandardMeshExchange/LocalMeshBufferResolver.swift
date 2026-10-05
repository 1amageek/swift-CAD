import Foundation
import CADCore

struct LocalMeshBufferResolver: StandardMeshBufferResolving {
    let directory: URL

    func readBuffer(uri: String, maximumBytes: Int) throws -> Data {
        guard let decoded = uri.removingPercentEncoding,
              !decoded.isEmpty, !decoded.hasPrefix("/"), !decoded.contains(":"),
              !decoded.contains("\\"), !decoded.contains("?"), !decoded.contains("#") else {
            throw ImportError.securityViolation("glTF buffers must use local relative file URIs.")
        }
        let base = directory.standardizedFileURL.resolvingSymlinksInPath()
        let url = base.appendingPathComponent(decoded).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(base.path + "/") else {
            throw ImportError.securityViolation("glTF buffer escapes its input directory.")
        }
        do {
            let source = try MappedFileByteSource(url: url)
            guard source.count <= maximumBytes else {
                throw exchangeResourceLimitError(format: .gltf, detail: "external buffer exceeds the byte limit.")
            }
            return try source.withNoCopyData { Data($0) }
        } catch let error as ByteSourceError {
            throw ImportError.resourceUnavailable("Unable to read glTF buffer: \(error)")
        }
    }
}
