import Foundation
import CADCore

struct USDAAttributeSyntaxNormalizer {
    func normalize(_ data: Data) throws -> Data {
        guard let source = String(data: data, encoding: .utf8) else {
            throw ExportError.fileWriteFailure("Authored USDA data is not UTF-8.")
        }
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        var output: [String] = []
        output.reserveCapacity(lines.count)
        var index = 0
        while index < lines.count {
            let line = omittingDefaultVaryingQualifier(from: lines[index])
            guard line.hasSuffix(" (") else {
                output.append(line)
                index += 1
                continue
            }
            var metadata: [String] = []
            var closingIndex = index + 1
            var assignment: String?
            var closingIndentation = ""
            while closingIndex < lines.count {
                let candidate = omittingDefaultVaryingQualifier(
                    from: lines[closingIndex]
                )
                if let separator = candidate.range(of: ") = ") {
                    closingIndentation = String(candidate[..<separator.lowerBound])
                    assignment = String(candidate[separator.upperBound...])
                    break
                }
                metadata.append(candidate)
                closingIndex += 1
            }
            guard let assignment else {
                output.append(line)
                index += 1
                continue
            }
            output.append(String(line.dropLast(2)) + " = " + assignment + " (")
            output.append(contentsOf: metadata)
            output.append(closingIndentation + ")")
            index = closingIndex + 1
        }
        return Data(output.joined(separator: "\n").utf8)
    }

    private func omittingDefaultVaryingQualifier(from line: String) -> String {
        let indentation = line.prefix(while: { $0 == " " || $0 == "\t" })
        let content = line.dropFirst(indentation.count)
        guard content.hasPrefix("varying ") else {
            return line
        }
        return String(indentation) + content.dropFirst("varying ".count)
    }
}
