import Foundation
import Testing

@Test(.timeLimit(.minutes(1)))
func modelingOwnsTheSewingPortWhileKernelOwnsTheDefaultAdapter() throws {
    let packageRoot = try swiftCADPackageRoot()
    let modelingSources = packageRoot.appendingPathComponent("Sources/CADModeling")
    let kernelSources = packageRoot.appendingPathComponent("Sources/CADKernel")

    let modelingSource = try swiftSource(in: modelingSources)
    #expect(!modelingSource.contains("import CADKernel"))
    #expect(!modelingSource.contains("DefaultBRepSewer"))

    let sewingPort = modelingSources.appendingPathComponent("BRepSewing.swift")
    let defaultAdapter = kernelSources.appendingPathComponent("DefaultBRepSewer.swift")
    #expect(FileManager.default.fileExists(atPath: sewingPort.path))
    #expect(FileManager.default.fileExists(atPath: defaultAdapter.path))
}

@Test(.timeLimit(.minutes(1)))
func packageModulesOnlyImportTheirDeclaredResponsibilityLayers() throws {
    let packageRoot = try swiftCADPackageRoot()
    let packageModules: Set<String> = [
        "CADCore",
        "CADGeometry",
        "CADTopology",
        "CADIR",
        "CADModeling",
        "CADKernel",
        "CADUSD",
        "CADExchange",
        "SwiftCAD",
    ]
    let allowedDependencies: [String: Set<String>] = [
        "CADCore": [],
        "CADGeometry": ["CADCore"],
        "CADTopology": ["CADCore", "CADGeometry"],
        "CADIR": ["CADCore", "CADGeometry", "CADTopology"],
        "CADModeling": ["CADCore", "CADGeometry", "CADTopology", "CADIR"],
        "CADKernel": ["CADCore", "CADGeometry", "CADTopology", "CADIR", "CADModeling"],
        "CADUSD": ["CADCore", "CADIR"],
        "CADExchange": ["CADCore", "CADGeometry", "CADTopology", "CADIR", "CADKernel", "CADUSD"],
        "SwiftCAD": ["CADCore", "CADTopology", "CADIR", "CADModeling", "CADKernel", "CADExchange"],
    ]

    for module in packageModules.sorted() {
        let sourceDirectory = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent(module)
        let importedPackageModules = try swiftImports(in: sourceDirectory)
            .intersection(packageModules)
        let unexpectedImports = importedPackageModules
            .subtracting(allowedDependencies[module, default: []])
        #expect(
            unexpectedImports.isEmpty,
            "\(module) crosses its responsibility boundary through \(unexpectedImports.sorted())."
        )
    }
}

private func swiftCADPackageRoot() throws -> URL {
    var url = URL(fileURLWithPath: #filePath)
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    guard FileManager.default.fileExists(
        atPath: url.appendingPathComponent("Package.swift").path
    ) else {
        throw PackageResponsibilityBoundaryTestError.packageRootNotFound(url.path)
    }
    return url
}

private func swiftSource(in directory: URL) throws -> String {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw PackageResponsibilityBoundaryTestError.sourceDirectoryNotFound(directory.path)
    }
    var source = ""
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
        source += try String(contentsOf: fileURL, encoding: .utf8)
    }
    return source
}

private func swiftImports(in directory: URL) throws -> Set<String> {
    let source = try swiftSource(in: directory)
    return Set(source.split(separator: "\n").compactMap { line in
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 2, tokens[0] == "import" else { return nil }
        return String(tokens[1])
    })
}

private enum PackageResponsibilityBoundaryTestError: Error {
    case packageRootNotFound(String)
    case sourceDirectoryNotFound(String)
}
