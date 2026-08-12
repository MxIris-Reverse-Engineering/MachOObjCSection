import ArgumentParser

@main
struct ObjCSectionCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "objc-section",
        abstract: "Dump Objective-C declarations out of a Mach-O file or dyld shared cache.",
        version: BundledVersion.value,
        subcommands: [
            DumpCommand.self,
            InterfaceCommand.self,
        ],
        defaultSubcommand: DumpCommand.self
    )
}
