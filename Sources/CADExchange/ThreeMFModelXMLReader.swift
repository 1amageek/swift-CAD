import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CADCore
import CADIR

struct ThreeMFModelXML {
    var unit: LengthUnit
    var meshes: [Mesh]
}

private struct ThreeMFMeshObject {
    var vertices: [Point3D] = []
    var triangles: [(Int, Int, Int)] = []
}

final class ThreeMFModelXMLReader: NSObject, XMLParserDelegate {
    private var fallbackUnit: LengthUnit = .millimeter
    private var unit: LengthUnit?
    private var objects: [Int: ThreeMFMeshObject] = [:]
    private var buildObjectIDs: [Int] = []
    private var currentObjectID: Int?
    private var currentObject: ThreeMFMeshObject?
    private var importError: ImportError?
    private var elementStack: [String] = []

    static func read(_ data: Data, fallbackUnit: LengthUnit) throws -> ThreeMFModelXML {
        let reader = ThreeMFModelXMLReader()
        reader.fallbackUnit = fallbackUnit
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else {
            if let importError = reader.importError {
                throw importError
            }
            throw ImportError.invalidData(parser.parserError?.localizedDescription ?? "Invalid 3MF XML.")
        }
        return try reader.resolvedModel()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        guard validateElementNamespace(name, namespaceURI: namespaceURI, parser: parser) else {
            return
        }
        if elementStack.isEmpty {
            guard name == "model" else {
                fail("3MF model root element must be model.", parser: parser)
                return
            }
        }
        if unsupported3MFPropertyResourceElements.contains(name) {
            fail("3MF material and property resources are not supported.", parser: parser)
            return
        }
        guard supported3MFElements.contains(name) || elementStack.contains("metadata") else {
            fail("Unsupported 3MF element \(name).", parser: parser)
            return
        }
        guard validateElementPlacement(name, parser: parser) else {
            return
        }
        guard validateSupportedAttributes(attributeDict, for: name, parser: parser) else {
            return
        }
        if elementStack.isEmpty {
            readModelUnit(attributeDict, parser: parser)
            guard importError == nil else {
                return
            }
        }
        switch name {
        case "object":
            beginObject(attributeDict, parser: parser)
        case "vertex":
            guard elementStack == ["model", "resources", "object", "mesh", "vertices"] else {
                fail("3MF vertex is outside the vertices container.", parser: parser)
                return
            }
            readVertex(attributeDict, parser: parser)
        case "triangle":
            guard elementStack == ["model", "resources", "object", "mesh", "triangles"] else {
                fail("3MF triangle is outside the triangles container.", parser: parser)
                return
            }
            readTriangle(attributeDict, parser: parser)
        case "item":
            readBuildItem(attributeDict, parser: parser)
        case "components", "component":
            fail("3MF component object references are not supported.", parser: parser)
            return
        default:
            break
        }
        if importError == nil {
            elementStack.append(name)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        guard elementStack.last == name else {
            fail("3MF XML nesting is inconsistent.", parser: parser)
            return
        }
        if name == "object" {
            finishObject(parser: parser)
        }
        elementStack.removeLast()
    }

    private func validateElementNamespace(_ name: String, namespaceURI: String?, parser: XMLParser) -> Bool {
        guard !elementStack.contains("metadata") else {
            return true
        }
        guard namespaceURI == threeMFCoreNamespaceURI else {
            fail("3MF element \(name) must use the 3MF core namespace.", parser: parser)
            return false
        }
        return true
    }

    private func validateElementPlacement(_ name: String, parser: XMLParser) -> Bool {
        if elementStack.contains("metadata") {
            guard !metadataDisallowed3MFElements.contains(name) else {
                fail("3MF \(name) is inside a metadata lookalike container.", parser: parser)
                return false
            }
            return true
        }

        let expectedPath: [String]?
        switch name {
        case "model":
            expectedPath = []
        case "resources", "build":
            expectedPath = ["model"]
        case "object":
            expectedPath = ["model", "resources"]
        case "mesh":
            expectedPath = ["model", "resources", "object"]
        case "vertices", "triangles":
            expectedPath = ["model", "resources", "object", "mesh"]
        case "vertex":
            expectedPath = ["model", "resources", "object", "mesh", "vertices"]
        case "triangle":
            expectedPath = ["model", "resources", "object", "mesh", "triangles"]
        case "item":
            expectedPath = ["model", "build"]
        case "metadata":
            return !elementStack.isEmpty
        default:
            expectedPath = nil
        }

        guard let expectedPath else {
            return true
        }
        guard elementStack == expectedPath else {
            fail("3MF \(name) is outside its supported container path.", parser: parser)
            return false
        }
        return true
    }

    private func resolvedModel() throws -> ThreeMFModelXML {
        let resolvedUnit = unit ?? fallbackUnit
        guard !buildObjectIDs.isEmpty else {
            throw ImportError.invalidData("3MF build contains no items.")
        }
        let referencedObjectIDs = Set(buildObjectIDs)
        if let unreferencedObjectID = Set(objects.keys).subtracting(referencedObjectIDs).sorted().first {
            throw ImportError.invalidData("3MF resource object \(unreferencedObjectID) is not referenced by the build.")
        }

        var meshes: [Mesh] = []
        for objectID in buildObjectIDs {
            guard let object = objects[objectID] else {
                throw ImportError.invalidData("3MF build item references a missing object.")
            }
            guard !object.vertices.isEmpty else {
                throw ImportError.invalidData("3MF build item references an object with no vertices.")
            }
            guard !object.triangles.isEmpty else {
                throw ImportError.invalidData("3MF build item references an object with no triangles.")
            }
            var positions: [Point3D] = []
            var indices: [UInt32] = []
            for triangle in object.triangles {
                let sourceIndices = [triangle.0, triangle.1, triangle.2]
                for sourceIndex in sourceIndices {
                    guard object.vertices.indices.contains(sourceIndex) else {
                        throw ImportError.invalidData("3MF triangle index is out of range.")
                    }
                    guard UInt64(positions.count) < UInt64(UInt32.max) else {
                        throw ImportError.invalidData("3MF mesh vertex count exceeds UInt32 range.")
                    }
                    positions.append(object.vertices[sourceIndex])
                    indices.append(UInt32(positions.count - 1))
                }
            }
            meshes.append(Mesh(positions: positions, normals: [], indices: indices))
        }

        return ThreeMFModelXML(unit: resolvedUnit, meshes: meshes)
    }

    private func readModelUnit(_ attributes: [String: String], parser: XMLParser) {
        guard let value = attributes["unit"] else {
            return
        }
        guard let parsedUnit = parseLengthUnitName(value) else {
            fail("Unsupported 3MF model unit \(value).", parser: parser)
            return
        }
        unit = parsedUnit
    }

    private func beginObject(_ attributes: [String: String], parser: XMLParser) {
        guard elementStack == ["model", "resources"] else {
            fail("3MF object is outside the resources container.", parser: parser)
            return
        }
        guard currentObjectID == nil else {
            fail("Nested 3MF objects are not supported.", parser: parser)
            return
        }
        guard let id = intAttribute("id", in: attributes), id > 0 else {
            fail("Invalid 3MF object id.", parser: parser)
            return
        }
        guard objects[id] == nil else {
            fail("3MF object id is duplicated.", parser: parser)
            return
        }
        if let type = attributes["type"], type.lowercased() != "model" {
            fail("Unsupported 3MF object type \(type).", parser: parser)
            return
        }
        currentObjectID = id
        currentObject = ThreeMFMeshObject()
    }

    private func finishObject(parser: XMLParser) {
        guard let id = currentObjectID,
              let object = currentObject else {
            fail("3MF object state is inconsistent.", parser: parser)
            return
        }
        objects[id] = object
        currentObjectID = nil
        currentObject = nil
    }

    private func readVertex(_ attributes: [String: String], parser: XMLParser) {
        guard var object = currentObject else {
            fail("3MF vertex is outside an object.", parser: parser)
            return
        }
        let resolvedUnit = unit ?? fallbackUnit
        guard let x = doubleAttribute("x", in: attributes),
              let y = doubleAttribute("y", in: attributes),
              let z = doubleAttribute("z", in: attributes) else {
            fail("Invalid 3MF vertex.", parser: parser)
            return
        }
        let point = Point3D(
            x: resolvedUnit.toInternal(x),
            y: resolvedUnit.toInternal(y),
            z: resolvedUnit.toInternal(z)
        )
        guard point.x.isFinite,
              point.y.isFinite,
              point.z.isFinite else {
            fail("3MF vertex contains a non-finite coordinate.", parser: parser)
            return
        }
        object.vertices.append(point)
        currentObject = object
    }

    private func readTriangle(_ attributes: [String: String], parser: XMLParser) {
        guard var object = currentObject else {
            fail("3MF triangle is outside an object.", parser: parser)
            return
        }
        guard let v1 = intAttribute("v1", in: attributes),
              let v2 = intAttribute("v2", in: attributes),
              let v3 = intAttribute("v3", in: attributes) else {
            fail("Invalid 3MF triangle.", parser: parser)
            return
        }
        guard v1 >= 0, v2 >= 0, v3 >= 0 else {
            fail("3MF triangle index is negative.", parser: parser)
            return
        }
        object.triangles.append((v1, v2, v3))
        currentObject = object
    }

    private func readBuildItem(_ attributes: [String: String], parser: XMLParser) {
        guard elementStack == ["model", "build"] else {
            fail("3MF build item is outside the build container.", parser: parser)
            return
        }
        guard attributes["transform"] == nil else {
            fail("3MF build item transforms are not supported.", parser: parser)
            return
        }
        guard let objectID = intAttribute("objectid", in: attributes), objectID > 0 else {
            fail("Invalid 3MF build item object reference.", parser: parser)
            return
        }
        buildObjectIDs.append(objectID)
    }

    private func fail(_ message: String, parser: XMLParser) {
        importError = ImportError.invalidData(message)
        parser.abortParsing()
    }

    private func validateSupportedAttributes(
        _ attributes: [String: String],
        for elementName: String,
        parser: XMLParser
    ) -> Bool {
        guard !elementStack.contains("metadata") else {
            return true
        }
        let allowedAttributes = supported3MFAttributes[elementName] ?? []
        for attribute in attributes.keys.sorted() {
            guard allowedAttributes.contains(attribute) else {
                fail("Unsupported 3MF attribute \(attribute) on \(elementName).", parser: parser)
                return false
            }
        }
        return true
    }
}

private func localName(_ value: String) -> String {
    value.split(separator: ":").last.map(String.init) ?? value
}

private let threeMFCoreNamespaceURI = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"

private let unsupported3MFPropertyResourceElements: Set<String> = [
    "basematerials",
    "colorgroup",
    "compositematerials",
    "texture2d",
    "texture2dgroup",
    "multiproperties"
]

private let supported3MFElements: Set<String> = [
    "model",
    "metadata",
    "resources",
    "object",
    "mesh",
    "vertices",
    "vertex",
    "triangles",
    "triangle",
    "build",
    "item"
]

private let metadataDisallowed3MFElements: Set<String> = [
    "model",
    "metadata",
    "resources",
    "object",
    "mesh",
    "vertices",
    "vertex",
    "triangles",
    "triangle",
    "build",
    "item",
    "components",
    "component"
]

private let supported3MFAttributes: [String: Set<String>] = [
    "model": ["lang", "unit", "xml:lang"],
    "metadata": ["name"],
    "resources": [],
    "object": ["id", "type"],
    "mesh": [],
    "vertices": [],
    "vertex": ["x", "y", "z"],
    "triangles": [],
    "triangle": ["v1", "v2", "v3"],
    "build": [],
    "item": ["objectid"]
]

private func doubleAttribute(_ name: String, in attributes: [String: String]) -> Double? {
    guard let value = attributes[name] else {
        return nil
    }
    guard let number = Double(value), number.isFinite else {
        return nil
    }
    return number
}

private func intAttribute(_ name: String, in attributes: [String: String]) -> Int? {
    guard let value = attributes[name] else {
        return nil
    }
    return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
}
