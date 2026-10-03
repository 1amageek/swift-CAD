import Foundation
import CADCore
import CADIR

/// Admits only explicit source/role/target identity assignments, independent of business identifiers.
struct STEPSourceIdentityReader: STEPSourceIdentityReading {
    func read(fields: any STEPFieldReading, names: [Int: String], processingBudget: ExchangeProcessingBudget, limits: ExchangeResourceLimits,
              remainingWork: Int, remainingTextBytes: Int) throws -> STEPSourceIdentityResult {
        try processingBudget.check(format: .step)
        guard names.count <= limits.maximumEntities, names.count <= remainingWork else {
            throw AssemblyError.resourceLimitExceeded("STEP identity records/work")
        }
        var work = names.count, bytes = 0, values: [Int: UUID] = [:]
        func string(_ token: String) throws -> String {
            try processingBudget.check(format: .step)
            let result = try fields.decodedString(token, limits: STEPStringLimits(maximumInputBytes: limits.maximumBytes,
                maximumOutputBytes: remainingTextBytes - bytes, maximumWork: remainingWork - work))
            work += result.consumedWork; bytes += result.outputBytes
            return result.value
        }
        func args(_ id: Int, _ count: Int) throws -> [String] {
            let values = try fields.arguments(id, component: nil)
            guard values.count == count else { throw ImportError.invalidData("Malformed STEP source identity assignment.") }
            return values
        }
        for id in names.keys.sorted() where names[id]?.contains("IDENTIFICATION_ASSIGNMENT") == true {
            try processingBudget.check(format: .step)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP import retains only the bounded native assembly identity namespace.
            // Other identification assignments require persistent source ownership and lossless standard re-export before admission.
            guard names[id] == "APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT" else {
                throw AssemblyError.invalidSource("Unsupported STEP identification assignment subtype.")
            }
            let a = try args(id, 4), roleID = try fields.reference(a[1]), sourceID = try fields.reference(a[2])
            guard names[roleID] == "IDENTIFICATION_ROLE", names[sourceID] == "EXTERNAL_SOURCE" else {
                throw ImportError.invalidData("STEP identity requires a role and external source.")
            }
            let source = try args(sourceID, 1), role = try args(roleID, 2)
            guard source[0].hasPrefix("IDENTIFIER("), source[0].hasSuffix(")") else {
                throw AssemblyError.invalidSource("STEP identity source must be a typed IDENTIFIER.")
            }
            let sourceValue = try string(String(source[0].dropFirst(11).dropLast()))
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP import cannot preserve unrelated external identification namespaces.
            // Complete source ownership/transport for their assigned IDs, roles and sources is required before they can succeed.
            guard sourceValue == STEPSourceIdentityRole.namespace else {
                throw AssemblyError.invalidSource("Unsupported STEP identity namespace.")
            }
            let roleName = try string(role[0])
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP import retains only the native assembly identification roles without role descriptions.
            // Other roles/descriptions require an explicit persistent identification owner and faithful standard re-export.
            guard let kind = STEPSourceIdentityRole(rawValue: roleName), role[1] == "$" else {
                throw AssemblyError.invalidSource("Unsupported STEP identity role or role description.")
            }
            // A single reference is admitted without materializing an arbitrary target list.
            guard a[3].hasPrefix("("), a[3].hasSuffix(")") else {
                throw ImportError.invalidData("STEP identity requires a target set.")
            }
            let target = try fields.reference(String(a[3].dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines))
            guard kind.entityNames.contains(names[target] ?? "") else {
                throw AssemblyError.invalidSource("STEP identity role and single target do not match.")
            }
            let identifier = try string(a[0])
            guard let uuid = UUID(uuidString: identifier), uuid.uuidString.lowercased() == identifier.lowercased() else {
                throw AssemblyError.invalidSource("Malformed STEP native UUID assignment.")
            }
            guard values.updateValue(uuid, forKey: target) == nil else {
                throw AssemblyError.invalidSource("Competing STEP native UUID assignments.")
            }
        }
        return STEPSourceIdentityResult(values: values, consumedWork: work, textBytes: bytes)
    }
}
