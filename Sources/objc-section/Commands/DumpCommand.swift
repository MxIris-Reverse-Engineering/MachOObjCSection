import ArgumentParser
import Foundation
import MachOKit
import Semantic

struct DumpCommand: AsyncParsableCommand, Sendable {
    static let configuration: CommandConfiguration = .init(
        commandName: "dump",
        abstract: "Dump every Objective-C declaration in a Mach-O file or dyld shared cache image."
    )

    @OptionGroup
    var machOOptions: MachOOptionGroup

    @OptionGroup(title: "Generation")
    var generationOptions: GenerationOptionGroup

    @OptionGroup(title: "Comment Templates")
    var transformerOptions: TransformerOptionGroup

    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "The kinds of declaration to dump. If not specified, all of them are dumped.")
    var sections: [ObjCSectionKind] = []

    @Option(name: .shortAndLong, help: "Only dump declarations whose name contains this text, case-insensitively.")
    var filter: String?

    @Option(name: .shortAndLong, help: "The output path for the dump. If not specified, the output is printed to stdout.", completion: .file())
    var outputPath: String?

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    @Flag(name: .shortAndLong, help: "Report indexing progress on stderr.")
    var verbose: Bool = false

    func run() async throws {
        let session = try await ObjCInterfaceSession.make(
            machOOptions: machOOptions,
            generationOptions: generationOptions,
            transformerOptions: transformerOptions,
            isVerbose: verbose
        )

        let kinds = sections.isEmpty ? ObjCSectionKind.allCases : sections
        var dumpedString = ""

        for kind in kinds {
            for name in session.names(of: kind) where matchesFilter(name) {
                guard let interface = session.interface(of: kind, named: name) else { continue }
                emit(interface, into: &dumpedString)
            }
        }

        if let outputPath {
            try dumpedString.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        }
    }

    private func matchesFilter(_ name: String) -> Bool {
        guard let filter, !filter.isEmpty else { return true }
        return name.range(of: filter, options: .caseInsensitive) != nil
    }

    private func emit(_ semanticString: SemanticString, into dumpedString: inout String) {
        if outputPath != nil {
            dumpedString.append(semanticString.string)
            dumpedString.append("\n\n")
        } else {
            semanticString.printColorfully(using: colorScheme)
            print("")
        }
    }
}
