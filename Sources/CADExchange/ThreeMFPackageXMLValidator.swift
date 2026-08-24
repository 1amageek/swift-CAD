import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CADCore

enum ThreeMFPackageXMLValidator {
    static func validate(
        contentTypes: Data,
        relationships: Data,
        resources: inout ExchangeResourceAccountant
    ) throws {
        try ThreeMFContentTypesXMLReader.validate(contentTypes, resources: &resources)
        try ThreeMFRelationshipsXMLReader.validate(relationships, resources: &resources)
    }
}

private final class ThreeMFContentTypesXMLReader: NSObject, XMLParserDelegate {
    private var failure: (any Error)?
    private var elementStack: [String] = []
    private var defaults: [String: String] = [:]
    private var resources: ExchangeResourceAccountant?

    static func validate(
        _ data: Data,
        resources: inout ExchangeResourceAccountant
    ) throws {
        try validateThreeMFXMLData(data, documentName: "content types")
        let reader = ThreeMFContentTypesXMLReader()
        reader.resources = resources
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else {
            if let resolvedResources = reader.resources {
                resources = resolvedResources
            }
            if let failure = reader.failure {
                throw failure
            }
            throw ImportError.invalidData(parser.parserError?.localizedDescription ?? "Invalid 3MF content types XML.")
        }
        guard reader.elementStack.isEmpty else {
            throw ImportError.invalidData("3MF content types XML nesting is incomplete.")
        }
        if let resolvedResources = reader.resources {
            resources = resolvedResources
        }
        try reader.validateResolvedDefaults()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        guard accountStartElement(attributeCount: attributeDict.count, parser: parser) else {
            return
        }
        guard namespaceURI == packageContentTypesNamespaceURI else {
            fail("3MF content types element \(name) must use the OPC content-types namespace.", parser: parser)
            return
        }
        if elementStack.isEmpty {
            guard name == "Types" else {
                fail("3MF content types root element must be Types.", parser: parser)
                return
            }
            guard attributeDict.isEmpty else {
                fail("3MF content types root contains unsupported attributes.", parser: parser)
                return
            }
        } else {
            guard elementStack == ["Types"], name == "Default" else {
                fail("Unsupported 3MF content types element \(name).", parser: parser)
                return
            }
            readDefault(attributeDict, parser: parser)
            guard failure == nil else {
                return
            }
        }
        elementStack.append(name)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        guard elementStack.last == name else {
            fail("3MF content types XML nesting is inconsistent.", parser: parser)
            return
        }
        elementStack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("3MF content types XML contains unsupported character data.", parser: parser)
            return
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        fail("3MF content types XML contains unsupported CDATA.", parser: parser)
    }

    func parser(
        _ parser: XMLParser,
        foundInternalEntityDeclarationWithName name: String,
        value: String?
    ) {
        fail("3MF content types XML entity declarations are not supported.", parser: parser)
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        fail("3MF content types XML external entities are not supported.", parser: parser)
    }

    func parser(
        _ parser: XMLParser,
        foundProcessingInstructionWithTarget target: String,
        data: String?
    ) {
        fail("3MF content types XML processing instructions are not supported.", parser: parser)
    }

    private func readDefault(_ attributes: [String: String], parser: XMLParser) {
        guard Set(attributes.keys) == ["Extension", "ContentType"] else {
            fail("3MF content type Default must contain only Extension and ContentType.", parser: parser)
            return
        }
        guard let rawExtension = attributes["Extension"],
              let contentType = attributes["ContentType"] else {
            fail("3MF content type Default is malformed.", parser: parser)
            return
        }
        let ext = rawExtension.lowercased()
        guard expected3MFContentTypes.keys.contains(ext),
              expected3MFContentTypes[ext] == contentType else {
            fail("Unsupported 3MF content type Default for \(rawExtension).", parser: parser)
            return
        }
        guard defaults[ext] == nil else {
            fail("Duplicate 3MF content type Default for \(rawExtension).", parser: parser)
            return
        }
        defaults[ext] = contentType
    }

    private func validateResolvedDefaults() throws {
        guard defaults == expected3MFContentTypes else {
            throw ImportError.invalidData("3MF content types must declare only the supported rels and model defaults.")
        }
    }

    private func fail(_ message: String, parser: XMLParser) {
        fail(ImportError.invalidData(message), parser: parser)
    }

    private func fail(_ error: any Error, parser: XMLParser) {
        failure = error
        parser.abortParsing()
    }

    private func accountStartElement(attributeCount: Int, parser: XMLParser) -> Bool {
        do {
            guard var resources else {
                throw ImportError.invalidData("3MF content types resource accounting is unavailable.")
            }
            try resources.validateNestingDepth(elementStack.count + 1)
            try resources.recordEntities()
            try resources.recordIterations(1 + attributeCount)
            self.resources = resources
            return true
        } catch {
            fail(error, parser: parser)
            return false
        }
    }
}

private final class ThreeMFRelationshipsXMLReader: NSObject, XMLParserDelegate {
    private var failure: (any Error)?
    private var elementStack: [String] = []
    private var modelRelationshipCount = 0
    private var resources: ExchangeResourceAccountant?

    static func validate(
        _ data: Data,
        resources: inout ExchangeResourceAccountant
    ) throws {
        try validateThreeMFXMLData(data, documentName: "relationships")
        let reader = ThreeMFRelationshipsXMLReader()
        reader.resources = resources
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else {
            if let resolvedResources = reader.resources {
                resources = resolvedResources
            }
            if let failure = reader.failure {
                throw failure
            }
            throw ImportError.invalidData(parser.parserError?.localizedDescription ?? "Invalid 3MF relationships XML.")
        }
        guard reader.elementStack.isEmpty else {
            throw ImportError.invalidData("3MF relationships XML nesting is incomplete.")
        }
        if let resolvedResources = reader.resources {
            resources = resolvedResources
        }
        guard reader.modelRelationshipCount == 1 else {
            throw ImportError.invalidData("3MF relationships must declare exactly one model relationship.")
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        guard accountStartElement(attributeCount: attributeDict.count, parser: parser) else {
            return
        }
        guard namespaceURI == packageRelationshipsNamespaceURI else {
            fail("3MF relationships element \(name) must use the OPC relationships namespace.", parser: parser)
            return
        }
        if elementStack.isEmpty {
            guard name == "Relationships" else {
                fail("3MF relationships root element must be Relationships.", parser: parser)
                return
            }
            guard attributeDict.isEmpty else {
                fail("3MF relationships root contains unsupported attributes.", parser: parser)
                return
            }
        } else {
            guard elementStack == ["Relationships"], name == "Relationship" else {
                fail("Unsupported 3MF relationships element \(name).", parser: parser)
                return
            }
            readRelationship(attributeDict, parser: parser)
            guard failure == nil else {
                return
            }
        }
        elementStack.append(name)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        guard elementStack.last == name else {
            fail("3MF relationships XML nesting is inconsistent.", parser: parser)
            return
        }
        elementStack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("3MF relationships XML contains unsupported character data.", parser: parser)
            return
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        fail("3MF relationships XML contains unsupported CDATA.", parser: parser)
    }

    func parser(
        _ parser: XMLParser,
        foundInternalEntityDeclarationWithName name: String,
        value: String?
    ) {
        fail("3MF relationships XML entity declarations are not supported.", parser: parser)
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        fail("3MF relationships XML external entities are not supported.", parser: parser)
    }

    func parser(
        _ parser: XMLParser,
        foundProcessingInstructionWithTarget target: String,
        data: String?
    ) {
        fail("3MF relationships XML processing instructions are not supported.", parser: parser)
    }

    private func readRelationship(_ attributes: [String: String], parser: XMLParser) {
        guard Set(attributes.keys) == ["Target", "Id", "Type"] else {
            fail("3MF relationship must contain only Target, Id, and Type.", parser: parser)
            return
        }
        guard let id = attributes["Id"], !id.isEmpty,
              attributes["Target"] == "/3D/3dmodel.model",
              attributes["Type"] == threeMFModelRelationshipType else {
            fail("3MF relationship does not target the supported model part.", parser: parser)
            return
        }
        guard modelRelationshipCount == 0 else {
            fail("Duplicate 3MF model relationship.", parser: parser)
            return
        }
        modelRelationshipCount += 1
    }

    private func fail(_ message: String, parser: XMLParser) {
        fail(ImportError.invalidData(message), parser: parser)
    }

    private func fail(_ error: any Error, parser: XMLParser) {
        failure = error
        parser.abortParsing()
    }

    private func accountStartElement(attributeCount: Int, parser: XMLParser) -> Bool {
        do {
            guard var resources else {
                throw ImportError.invalidData("3MF relationships resource accounting is unavailable.")
            }
            try resources.validateNestingDepth(elementStack.count + 1)
            try resources.recordEntities()
            try resources.recordIterations(1 + attributeCount)
            self.resources = resources
            return true
        } catch {
            fail(error, parser: parser)
            return false
        }
    }
}

private let packageContentTypesNamespaceURI = "http://schemas.openxmlformats.org/package/2006/content-types"
private let packageRelationshipsNamespaceURI = "http://schemas.openxmlformats.org/package/2006/relationships"
private let threeMFModelRelationshipType = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
private let expected3MFContentTypes = [
    "rels": "application/vnd.openxmlformats-package.relationships+xml",
    "model": "application/vnd.ms-package.3dmanufacturing-3dmodel+xml"
]

func validateThreeMFXMLData(_ data: Data, documentName: String) throws {
    guard String(data: data, encoding: .utf8) != nil else {
        throw ImportError.invalidData("3MF \(documentName) XML is not UTF-8.")
    }
    for forbiddenDeclaration in ["<!doctype", "<!entity"] {
        guard !data.containsASCIICaseInsensitive(forbiddenDeclaration) else {
            throw ImportError.invalidData("3MF \(documentName) XML declarations are not supported.")
        }
    }
}

private func localName(_ value: String) -> String {
    value.split(separator: ":").last.map(String.init) ?? value
}

private extension Data {
    func containsASCIICaseInsensitive(_ pattern: String) -> Bool {
        let needle = Array(pattern.utf8)
        guard !needle.isEmpty, count >= needle.count else {
            return false
        }
        return withUnsafeBytes { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            for start in 0...(bytes.count - needle.count) {
                var matches = true
                for offset in needle.indices {
                    let candidate = bytes[start + offset]
                    let foldedCandidate = candidate >= 65 && candidate <= 90 ? candidate + 32 : candidate
                    if foldedCandidate != needle[offset] {
                        matches = false
                        break
                    }
                }
                if matches {
                    return true
                }
            }
            return false
        }
    }
}
