#if os(macOS)

import ObjCDeclarationRendering
import TypeIndexing

extension ObjCSwiftImportNotes {
    /// The notes the SDK's API notes give the Objective-C class `className`
    /// and its members: each `SwiftName` as `NS_SWIFT_NAME(...)`, each
    /// `SwiftPrivate` as `NS_REFINED_FOR_SWIFT`. Empty when they say nothing.
    ///
    /// Reads API notes only, so a `typeDatabase` indexed with a `moduleFilter`
    /// that selects no module is enough, and no sourcekitd work runs.
    @available(macOS 13.0, *)
    public init(apiNotesForClassNamed className: String, in typeDatabase: TypeDatabase) async {
        self.init(annotations: await typeDatabase.swiftImportAnnotations(forObjCClassNamed: className))
    }

    /// The same for the Objective-C protocol `protocolName`.
    @available(macOS 13.0, *)
    public init(apiNotesForProtocolNamed protocolName: String, in typeDatabase: TypeDatabase) async {
        self.init(annotations: await typeDatabase.swiftImportAnnotations(forObjCProtocolNamed: protocolName))
    }

    /// The notes `annotations` make; empty for `nil`.
    public init(annotations: ObjCContainerSwiftImportAnnotations?) {
        self.init()
        guard let annotations else { return }
        declarationNote = annotations.declaration.map(Note.init(annotation:))
        for (memberKey, memberAnnotation) in annotations.members {
            self[Member(memberKey)] = Note(annotation: memberAnnotation)
        }
    }
}

extension ObjCSwiftImportNotes.Note {
    /// The note an API notes annotation makes.
    public init(annotation: SwiftImportAnnotation) {
        self.init(isRefinedForSwift: annotation.isSwiftPrivate, swiftName: annotation.swiftName)
    }
}

extension ObjCSwiftImportNotes.Member {
    /// The member an API notes key names; the two key a member alike.
    public init(_ memberKey: ObjCMemberKey) {
        switch memberKey {
        case .method(let selector, let isClassMethod):
            self = .method(selector: selector, isClassMethod: isClassMethod)
        case .property(let name, let isClassProperty):
            self = .property(name: name, isClassProperty: isClassProperty)
        }
    }
}

#endif
