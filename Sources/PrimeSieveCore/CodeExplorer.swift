import Foundation

/// A documented excerpt read directly from the worker source shipped with the app.
/// Markers are comments in that same source, so the explorer cannot drift into a separate implementation.
public struct PrimeCodeSection: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let sourceLine: Int
    public let code: String
}

public enum PrimeCodeExplorer {
    public static func sections(for implementation: SieveImplementation, architecture: String = BenchmarkSession.architecture) throws -> [PrimeCodeSection] {
        if implementation.isBaseline { return try sections(for: implementation.language, architecture: architecture) }
        let url = implementation.languageID == "assembly"
            ? implementation.sourceURL.deletingLastPathComponent().appendingPathComponent("tuned_\(architecture).s") : implementation.sourceURL
        return try parse(String(contentsOf: url, encoding: .utf8))
    }

    /// Assembly exposes its calculation kernel rather than its timing and output harness.
    public static func sourceURL(for language: Language, architecture: String = BenchmarkSession.architecture) -> URL {
        if language.id == "assembly" {
            return language.sourceURL.deletingLastPathComponent().appendingPathComponent("sieve_\(architecture).s")
        }
        return language.sourceURL
    }

    public static func sections(for language: Language, architecture: String = BenchmarkSession.architecture) throws -> [PrimeCodeSection] {
        let url = sourceURL(for: language, architecture: architecture)
        return try parse(String(contentsOf: url, encoding: .utf8))
    }

    /// Only explicitly marked calculation regions are displayed. Malformed markers fail visibly.
    static func parse(_ source: String) throws -> [PrimeCodeSection] {
        var sections: [PrimeCodeSection] = []
        var title: String?
        var firstLine = 0
        var content: [String] = []
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            if let marker = line.range(of: "PRIME-BEGIN: ") {
                guard title == nil else { throw BenchmarkError.message("Nested code-explorer markers.") }
                title = String(line[marker.upperBound...]).replacingOccurrences(of: " *)", with: "")
                firstLine = index + 2
                content = []
            } else if line.contains("PRIME-END") {
                guard let heading = title, !content.isEmpty else { throw BenchmarkError.message("Incomplete code-explorer section.") }
                let nonempty = content.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                let indentation = nonempty.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
                let code = content.map { String($0.dropFirst(min(indentation, $0.count))) }.joined(separator: "\n")
                sections.append(.init(id: sections.count, title: heading, sourceLine: firstLine, code: code))
                title = nil
            } else if title != nil { content.append(line) }
        }
        guard title == nil, !sections.isEmpty else { throw BenchmarkError.message("Documented calculation code is unavailable.") }
        return sections
    }
}
