import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CADCore

struct SVGXMLModel {
    var unit: LengthUnit
    var polygons: [[Point3D]]
}

final class SVGXMLReader: NSObject, XMLParserDelegate {
    private var fallbackUnit: LengthUnit = .meter
    private var unit: LengthUnit?
    private var polygons: [[Point3D]] = []
    private var importError: ImportError?
    private var elementStack: [String] = []

    static func read(_ data: Data, fallbackUnit: LengthUnit) throws -> SVGXMLModel {
        let reader = SVGXMLReader()
        reader.fallbackUnit = fallbackUnit
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        guard parser.parse() else {
            if let importError = reader.importError {
                throw importError
            }
            throw ImportError.invalidData(parser.parserError?.localizedDescription ?? "Invalid SVG XML.")
        }
        return SVGXMLModel(unit: reader.unit ?? fallbackUnit, polygons: reader.polygons)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = svgLocalName(elementName)
        guard namespaceURI == svgNamespaceURI else {
            fail("SVG element \(name) must use the SVG namespace.", parser: parser)
            return
        }
        if elementStack.isEmpty {
            guard name == "svg" else {
                fail("SVG root element must be svg.", parser: parser)
                return
            }
        } else if name == "svg" {
            fail("Nested SVG containers are not supported.", parser: parser)
            return
        }
        guard validateSupportedAttributes(attributeDict, for: name, parser: parser) else {
            return
        }
        if elementStack.isEmpty, let value = attributeDict["data-unit"] {
            readUnit(value, parser: parser)
        }
        if supportedSVGContainerElements.contains(name), attributeDict["transform"] != nil {
            fail("SVG transforms are not supported.", parser: parser)
            return
        }
        if name == "polygon" {
            guard isSupportedPolygonContainerPath else {
                fail("SVG polygon is outside the supported svg/g container path.", parser: parser)
                return
            }
            guard let pointsValue = attributeDict["points"] else {
                fail("SVG polygon is missing points.", parser: parser)
                return
            }
            readPolygon(pointsValue, parser: parser)
            if importError == nil {
                elementStack.append(name)
            }
            return
        }
        if unsupportedSVGGeometryElements.contains(name) {
            fail("Unsupported SVG geometry element \(name).", parser: parser)
            return
        }
        guard supportedSVGContainerElements.contains(name) else {
            fail("Unsupported SVG element \(name).", parser: parser)
            return
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
        let name = svgLocalName(elementName)
        guard elementStack.last == name else {
            fail("SVG XML nesting is inconsistent.", parser: parser)
            return
        }
        elementStack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("SVG contains unsupported character data.", parser: parser)
            return
        }
    }

    private func readUnit(_ value: String, parser: XMLParser) {
        guard let parsedUnit = parseLengthUnitName(value) else {
            fail("Unsupported SVG unit \(value).", parser: parser)
            return
        }
        unit = parsedUnit
    }

    private func readPolygon(_ value: String, parser: XMLParser) {
        let resolvedUnit = unit ?? fallbackUnit
        do {
            let numbers = try svgNumbers(from: value)
            guard numbers.count.isMultiple(of: 2) else {
                fail("SVG polygon point list has an odd number of coordinates.", parser: parser)
                return
            }
            var points: [Point3D] = []
            var index = 0
            while index < numbers.count {
                let point = Point3D(
                    x: resolvedUnit.toInternal(numbers[index]),
                    y: resolvedUnit.toInternal(-numbers[index + 1]),
                    z: 0.0
                )
                guard point.x.isFinite,
                      point.y.isFinite else {
                    fail("SVG polygon contains a non-finite coordinate.", parser: parser)
                    return
                }
                points.append(point)
                index += 2
            }
            guard points.count >= 3 else {
                fail("SVG polygon must contain at least three points.", parser: parser)
                return
            }
            try validateSupportedPolygon(points)
            polygons.append(points)
        } catch let error as ImportError {
            importError = error
            parser.abortParsing()
        } catch {
            fail(error.localizedDescription, parser: parser)
        }
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
        let allowedAttributes = supportedSVGAttributes[elementName] ?? []
        for attribute in attributes.keys {
            guard allowedAttributes.contains(attribute) else {
                fail("Unsupported SVG attribute \(attribute) on \(elementName).", parser: parser)
                return false
            }
        }
        return true
    }

    private var isSupportedPolygonContainerPath: Bool {
        guard elementStack.first == "svg" else {
            return false
        }
        return elementStack.dropFirst().allSatisfy { $0 == "g" }
    }
}

private let svgNamespaceURI = "http://www.w3.org/2000/svg"

private let supportedSVGContainerElements: Set<String> = [
    "svg",
    "g",
    "polygon"
]

private let supportedSVGAttributes: [String: Set<String>] = [
    "svg": ["data-generator", "data-unit", "viewBox"],
    "g": ["data-unit"],
    "polygon": ["fill", "points", "stroke"]
]

private let unsupportedSVGGeometryElements: Set<String> = [
    "path",
    "polyline",
    "rect",
    "circle",
    "ellipse",
    "line"
]

private func svgLocalName(_ value: String) -> String {
    value.split(separator: ":").last.map(String.init) ?? value
}

private func svgNumbers(from value: String) throws -> [Double] {
    var numbers: [Double] = []
    var index = value.startIndex
    var hasReadNumber = false
    while index < value.endIndex {
        let separators = skipSVGSeparators(in: value, index: &index)
        if separators.commaCount > 0 {
            guard hasReadNumber,
                  separators.commaCount == 1,
                  index < value.endIndex else {
                throw ImportError.invalidData("SVG point list contains an empty coordinate field.")
            }
        } else if hasReadNumber,
                  !separators.consumedAny,
                  index < value.endIndex,
                  value[index] != "+",
                  value[index] != "-" {
            throw ImportError.invalidData("SVG point list has an invalid coordinate separator.")
        }
        guard index < value.endIndex else {
            break
        }
        let start = index
        if value[index] == "+" || value[index] == "-" {
            index = value.index(after: index)
        }
        var hasDigits = false
        while index < value.endIndex, value[index].isNumber {
            hasDigits = true
            index = value.index(after: index)
        }
        if index < value.endIndex, value[index] == "." {
            index = value.index(after: index)
            while index < value.endIndex, value[index].isNumber {
                hasDigits = true
                index = value.index(after: index)
            }
        }
        guard hasDigits else {
            throw ImportError.invalidData("Invalid SVG numeric value.")
        }
        if index < value.endIndex, value[index] == "e" || value[index] == "E" {
            let exponentMarker = index
            index = value.index(after: index)
            if index < value.endIndex, value[index] == "+" || value[index] == "-" {
                index = value.index(after: index)
            }
            var hasExponentDigits = false
            while index < value.endIndex, value[index].isNumber {
                hasExponentDigits = true
                index = value.index(after: index)
            }
            guard hasExponentDigits else {
                throw ImportError.invalidData("Invalid SVG exponent near \(value[exponentMarker...]).")
            }
        }
        let token = String(value[start..<index])
        guard let number = Double(token), number.isFinite else {
            throw ImportError.invalidData("Invalid SVG numeric value \(token).")
        }
        numbers.append(number)
        hasReadNumber = true
    }
    return numbers
}

private struct SVGSeparatorRun {
    var commaCount: Int = 0
    var whitespaceCount: Int = 0

    var consumedAny: Bool {
        commaCount > 0 || whitespaceCount > 0
    }
}

private func skipSVGSeparators(in value: String, index: inout String.Index) -> SVGSeparatorRun {
    var run = SVGSeparatorRun()
    while index < value.endIndex {
        let character = value[index]
        if character == "," {
            run.commaCount += 1
            index = value.index(after: index)
        } else if character.isWhitespace {
            run.whitespaceCount += 1
            index = value.index(after: index)
        } else {
            break
        }
    }
    return run
}

private func validateSupportedPolygon(_ points: [Point3D]) throws {
    let area = signedXYArea(of: points)
    let areaTolerance = ModelingTolerance.standard.distance * ModelingTolerance.standard.distance
    guard abs(area) > areaTolerance else {
        throw ImportError.invalidData("SVG polygon is degenerate.")
    }
    let isCounterClockwise = area > 0.0
    for index in points.indices {
        let previous = points[(index + points.count - 1) % points.count]
        let current = points[index]
        let next = points[(index + 1) % points.count]
        let cross = (current.x - previous.x) * (next.y - current.y)
            - (current.y - previous.y) * (next.x - current.x)
        guard abs(cross) > areaTolerance else {
            throw ImportError.invalidData("SVG polygon has a degenerate corner.")
        }
        if isCounterClockwise, cross < -areaTolerance {
            throw ImportError.invalidData("Concave SVG polygons are not supported.")
        }
        if !isCounterClockwise, cross > areaTolerance {
            throw ImportError.invalidData("Concave SVG polygons are not supported.")
        }
    }
}

private func signedXYArea(of points: [Point3D]) -> Double {
    var twiceArea = 0.0
    for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        twiceArea += current.x * next.y - next.x * current.y
    }
    return twiceArea / 2.0
}
