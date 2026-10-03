import Foundation

func stepAssemblyString(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
}
