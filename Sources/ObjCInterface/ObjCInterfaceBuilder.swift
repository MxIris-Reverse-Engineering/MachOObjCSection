import Foundation
import FoundationToolbox
import MachOKit
import MachOObjCSection
import ObjCDeclarationRendering
import ObjCDump
import ObjCIndexing
import ObjCMetadataSource
import Semantic

/// Turns an indexed Mach-O into rendered Objective-C declarations.
///
/// This is the layer where ``ObjCGenerationOptions`` actually bites: the strip
/// switches are applied here, by building a filtered copy of the metadata
/// before handing it to the renderer, while the comment switches are passed
/// through to the renderer untouched. `printExportedDeclarationsOnly` is
/// applied here too, by the export verdicts the indexer read in `prepare()`.
///
/// ```swift
/// let indexer = ObjCInterfaceIndexer(machO: image, imagePath: image.imagePath)
/// try await indexer.prepare()
///
/// let builder = ObjCInterfaceBuilder(indexer: indexer, machO: image)
/// let declaration = builder.classInterface(named: "NSString", options: .default)
/// ```
///
/// `MachO` follows the indexer's — a `MachOFile` read off disk or a
/// `MachOImage` loaded in this process — and is inferred from the arguments.
/// One switch behaves differently between the two: `stripOverrides` works off
/// the superclass chain the indexer resolved, and in file mode that chain can
/// be shorter, so fewer inherited members get stripped. See
/// ``ObjCIndexing/ObjCInterfaceIndexer``.
public struct ObjCInterfaceBuilder<MachO: ObjCMetadataSource> {
    private let indexer: ObjCInterfaceIndexer<MachO>
    private let machO: MachO

    public init(indexer: ObjCInterfaceIndexer<MachO>, machO: MachO) {
        self.indexer = indexer
        self.machO = machO
    }

    // MARK: - Rendering Context

    /// Builds the renderer context, wiring up the struct/union expansion rule:
    /// a named struct that this image also defines separately is referenced by
    /// name rather than expanded inline, so the declaration does not repeat a
    /// definition the caller can look up on its own.
    private func makeContext(
        options: ObjCGenerationOptions,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)?
    ) -> ObjCRenderingContext<MachO> {
        Self.makeContext(
            indexer: indexer,
            machO: machO,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )
    }

    /// The context ``makeContext(options:cTypeReplacements:ivarOffsetCommentBuilder:)``
    /// builds, for a renderer that holds no `ObjCInterfaceBuilder`.
    static func makeContext(
        indexer: ObjCInterfaceIndexer<MachO>,
        machO: MachO,
        options: ObjCGenerationOptions,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)?
    ) -> ObjCRenderingContext<MachO> {
        ObjCRenderingContext(
            machO: machO,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder,
            isExpandHandler: { name, isStruct in
                guard let name else { return true }
                return isStruct
                    ? !indexer.containsStruct(named: name)
                    : !indexer.containsUnion(named: name)
            }
        )
    }

    // MARK: - Class

    /// The rendered `@interface` for the class named `name`, or `nil` when the
    /// indexed image has no such class.
    ///
    /// With `printExportedDeclarationsOnly`, a class the image provably does
    /// not export renders as an empty string — `nil` keeps meaning there is
    /// no such class — and an exported one renders without the ivars whose
    /// offset variable is not exported. See
    /// ``ObjCIndexing/ObjCInterfaceIndexer/exportStatus(ofClassNamed:)``.
    ///
    /// A class the host supplied (``ObjCIndexing/ObjCSuppliedClass``) renders
    /// under a comment line saying why the image keeps no class object for
    /// it, whatever the options. Having no class object, it is never judged
    /// unexported.
    public func classInterface(
        named name: String,
        options: ObjCGenerationOptions = .default,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)? = nil
    ) -> SemanticString? {
        renderClassInterface(
            named: name,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder,
            marksOptionalContent: false
        )
    }

    /// The `@interface` for the class named `name` with everything any
    /// `ObjCGenerationOptions` could show — no member stripped, every comment
    /// added — and what the switches decide marked with `VisibilityRegion`s.
    ///
    /// Freezing it, separating the regions and projecting them with
    /// `ObjCGenerationOptions.isVisibilityOptionEnabled(_:)` gives, byte for
    /// byte, what `classInterface(named:options:cTypeReplacements:ivarOffsetCommentBuilder:)`
    /// renders for those options. `cTypeReplacements` and
    /// `ivarOffsetCommentBuilder` take effect as the text is rendered, so only
    /// the switches can differ between projections of one marked rendering;
    /// another replacement or offset comment needs a new one. `nil` when the
    /// indexed image has no such class.
    public func markedClassInterface(
        named name: String,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)? = nil
    ) -> SemanticString? {
        renderClassInterface(
            named: name,
            options: .default,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder,
            marksOptionalContent: true
        )
    }

    private func renderClassInterface(
        named name: String,
        options: ObjCGenerationOptions,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)?,
        marksOptionalContent: Bool
    ) -> SemanticString? {
        // A supplied class has no class object, so the indexer keeps it
        // apart; it renders as the others do.
        let classInfos: [ObjCClassInfo]
        let suppliedClassGroup: ObjCSuppliedClassGroup?
        if let classGroup = indexer.classGroup(forName: name) {
            classInfos = classGroup.info
            suppliedClassGroup = nil
        } else if let group = indexer.suppliedClassGroup(forName: name) {
            classInfos = group.info
            suppliedClassGroup = group
        } else {
            return nil
        }
        guard let currentClassInfo = classInfos.first else { return nil }

        // A supplied class has no verdict: it has no class object to judge.
        let isExcludedByExportFilter = indexer.exportStatus(ofClassNamed: name)?.isDefinitelyNotExported == true
        if isExcludedByExportFilter, !marksOptionalContent, options.printExportedDeclarationsOnly {
            return SemanticString()
        }

        let context = makeContext(
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )
        context.ivarNamesWithUnknownOffset = suppliedClassGroup?.ivarNamesWithUnknownOffset ?? []

        var strippedMembersByOption = strippedMembers(ofClass: currentClassInfo, superclassInfos: classInfos.dropFirst())
        if marksOptionalContent || options.printExportedDeclarationsOnly,
           let objcClass = indexer.classGroup(forName: name)?.objcClass {
            strippedMembersByOption[.printExportedDeclarationsOnly] = StrippedMembers(ivars: unexportedIvarNames(of: objcClass))
        }

        let finalClassInfo: ObjCClassInfo
        if marksOptionalContent {
            context.optionalContentMarking = Self.marking(for: strippedMembersByOption)
            finalClassInfo = currentClassInfo
        } else {
            let stripped = Self.union(of: strippedMembersByOption, enabledIn: options)
            finalClassInfo = ObjCClassInfo(
                name: currentClassInfo.name,
                version: currentClassInfo.version,
                imageName: currentClassInfo.imageName,
                instanceSize: currentClassInfo.instanceSize,
                superClassName: currentClassInfo.superClassName,
                protocols: currentClassInfo.protocols,
                ivars: currentClassInfo.ivars.removingAll { stripped.ivars.contains($0.name) },
                classProperties: currentClassInfo.classProperties.removingAll { stripped.classProperties.contains($0.name) },
                properties: currentClassInfo.properties.removingAll { stripped.properties.contains($0.name) },
                classMethods: currentClassInfo.classMethods.removingAll { stripped.classMethods.contains($0.name) },
                methods: currentClassInfo.methods.removingAll { stripped.methods.contains($0.name) }
            )
        }

        // IMP addresses are collected from the *unfiltered* metadata so that a
        // stripped accessor still contributes its address to the property it
        // belongs to.
        if marksOptionalContent || options.addPropertyAccessorAddressComments {
            for method in currentClassInfo.methods where method.imp != 0 {
                context.methodIMPs[method.name] = method.imp
            }
            for method in currentClassInfo.classMethods where method.imp != 0 {
                context.classMethodIMPs[method.name] = method.imp
            }
        }

        let declaration = finalClassInfo.semanticString(using: context)
        let rendering = suppliedClassGroup.map {
            Self.declaration(declaration, under: context.comment(.note($0.suppliedClass.kind.declarationComment)))
        } ?? declaration
        return isExcludedByExportFilter && marksOptionalContent ? Self.visibleWhileExportFilterIsOff(rendering) : rendering
    }

    @SemanticStringBuilder
    private static func declaration(_ declaration: SemanticString, under comment: SemanticString) -> SemanticString {
        comment
        BreakLine()
        declaration
    }

    /// `declaration` with every atom visible only while
    /// `printExportedDeclarationsOnly` is off: what a marked rendering makes
    /// of a declaration the plain one leaves out. Projected with the switch on
    /// it reads as nothing at all, not even a line break, as the plain
    /// rendering's empty string does; with it off, as the declaration itself.
    ///
    /// The atoms are marked in place rather than wrapped in a
    /// `VisibilityRegion`, which would add an element around the declaration
    /// that the plain rendering does not have.
    private static func visibleWhileExportFilterIsOff(_ declaration: SemanticString) -> SemanticString {
        var marked = declaration
        marked.markAtoms(from: 0, visibleUnder: .disabled(ObjCGenerationOptions.VisibilityOption.printExportedDeclarationsOnly.rawValue))
        return marked
    }

    /// The ivars of `objcClass` whose offset variable the image provably does
    /// not export, read for the one class being rendered: reading where an
    /// ivar keeps its offset takes another pass over the ivar list, which
    /// ``ObjCIndexing/ObjCInterfaceIndexer/prepare()`` does not pay for every
    /// class. Empty without export information, since no verdict is then
    /// definite.
    private func unexportedIvarNames(of objcClass: some ObjCClassProtocol) -> Set<String> {
        guard let exportIndex = indexer.exportIndex else { return [] }
        var unexportedIvarNames: Set<String> = []
        for (ivarName, offsetVariableOffset) in machO.objcIvarOffsetVariableOffsets(of: objcClass)
        where exportIndex.exportStatus(ofIvarOffsetVariableAt: offsetVariableOffset).isDefinitelyNotExported {
            unexportedIvarNames.insert(ivarName)
        }
        return unexportedIvarNames
    }

    /// The members each strip switch removes from a class, switch by switch,
    /// so that a plain rendering can take the union of the enabled ones and
    /// a marked rendering can tell every member which switches remove it.
    private func strippedMembers(
        ofClass classInfo: ObjCClassInfo,
        superclassInfos: some Sequence<ObjCClassInfo>
    ) -> [ObjCGenerationOptions.VisibilityOption: StrippedMembers] {
        var strippedMembersByOption: [ObjCGenerationOptions.VisibilityOption: StrippedMembers] = [:]

        strippedMembersByOption[.stripCtorMethod] = StrippedMembers(methods: [".cxx_construct"])
        strippedMembersByOption[.stripDtorMethod] = StrippedMembers(methods: [".cxx_destruct"])

        var overrides = StrippedMembers()
        for superclassInfo in superclassInfos {
            overrides.classProperties.formUnion(superclassInfo.classProperties.map(\.name))
            overrides.properties.formUnion(superclassInfo.properties.map(\.name))
            overrides.classMethods.formUnion(superclassInfo.classMethods.map(\.name))
            overrides.methods.formUnion(superclassInfo.methods.map(\.name))
        }
        strippedMembersByOption[.stripOverrides] = overrides

        strippedMembersByOption[.stripProtocolConformance] = Self.membersDeclared(byProtocolChainsOf: classInfo.protocols)

        var synthesizedMethods = StrippedMembers()
        var synthesizedIvarNames: Set<String> = []
        for property in classInfo.properties + classInfo.classProperties {
            collectAccessorSelectors(
                of: property,
                intoClassMethods: &synthesizedMethods.classMethods,
                intoMethods: &synthesizedMethods.methods
            )
            if !property.isClassProperty, let ivar = property.ivar {
                synthesizedIvarNames.insert(ivar)
            }
        }
        strippedMembersByOption[.stripSynthesizedMethods] = synthesizedMethods

        var synthesizedIvars = StrippedMembers()
        for ivar in classInfo.ivars where synthesizedIvarNames.contains(ivar.name) {
            synthesizedIvars.ivars.insert(ivar.name)
        }
        strippedMembersByOption[.stripSynthesizedIvars] = synthesizedIvars

        return strippedMembersByOption
    }

    // MARK: - Protocol

    /// The rendered `@protocol` for the protocol named `name`, or `nil` when
    /// the indexed image has no such protocol.
    public func protocolInterface(
        named name: String,
        options: ObjCGenerationOptions = .default,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)? = nil
    ) -> SemanticString? {
        renderProtocolInterface(
            named: name,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder,
            marksOptionalContent: false
        )
    }

    /// The `@protocol` for the protocol named `name`, marked the way
    /// `markedClassInterface(named:cTypeReplacements:ivarOffsetCommentBuilder:)`
    /// marks a class.
    public func markedProtocolInterface(
        named name: String,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)? = nil
    ) -> SemanticString? {
        renderProtocolInterface(
            named: name,
            options: .default,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder,
            marksOptionalContent: true
        )
    }

    private func renderProtocolInterface(
        named name: String,
        options: ObjCGenerationOptions,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)?,
        marksOptionalContent: Bool
    ) -> SemanticString? {
        guard let currentProtocolInfo = indexer.protocolGroup(forName: name)?.info else { return nil }

        let context = makeContext(
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )

        let strippedMembersByOption = strippedMembers(ofProtocol: currentProtocolInfo)

        if marksOptionalContent {
            context.optionalContentMarking = Self.marking(for: strippedMembersByOption)
            return currentProtocolInfo.semanticString(using: context)
        }

        let stripped = Self.union(of: strippedMembersByOption, enabledIn: options)
        let finalProtocolInfo = ObjCProtocolInfo(
            name: currentProtocolInfo.name,
            protocols: currentProtocolInfo.protocols,
            classProperties: currentProtocolInfo.classProperties.removingAll { stripped.classProperties.contains($0.name) },
            properties: currentProtocolInfo.properties.removingAll { stripped.properties.contains($0.name) },
            classMethods: currentProtocolInfo.classMethods.removingAll { stripped.classMethods.contains($0.name) },
            methods: currentProtocolInfo.methods.removingAll { stripped.methods.contains($0.name) },
            optionalClassProperties: currentProtocolInfo.optionalClassProperties.removingAll { stripped.classProperties.contains($0.name) },
            optionalProperties: currentProtocolInfo.optionalProperties.removingAll { stripped.properties.contains($0.name) },
            optionalClassMethods: currentProtocolInfo.optionalClassMethods.removingAll { stripped.classMethods.contains($0.name) },
            optionalMethods: currentProtocolInfo.optionalMethods.removingAll { stripped.methods.contains($0.name) }
        )

        return finalProtocolInfo.semanticString(using: context)
    }

    /// The members each strip switch removes from a protocol. Only four
    /// switches apply: a protocol has no ivars and no superclass.
    private func strippedMembers(ofProtocol protocolInfo: ObjCProtocolInfo) -> [ObjCGenerationOptions.VisibilityOption: StrippedMembers] {
        var strippedMembersByOption: [ObjCGenerationOptions.VisibilityOption: StrippedMembers] = [:]

        strippedMembersByOption[.stripCtorMethod] = StrippedMembers(methods: [".cxx_construct"])
        strippedMembersByOption[.stripDtorMethod] = StrippedMembers(methods: [".cxx_destruct"])

        strippedMembersByOption[.stripProtocolConformance] = Self.membersDeclared(byProtocolChainsOf: protocolInfo.protocols)

        var synthesizedMethods = StrippedMembers()
        let allProperties = protocolInfo.properties
            + protocolInfo.classProperties
            + protocolInfo.optionalProperties
            + protocolInfo.optionalClassProperties
        for property in allProperties {
            collectAccessorSelectors(
                of: property,
                intoClassMethods: &synthesizedMethods.classMethods,
                intoMethods: &synthesizedMethods.methods
            )
        }
        strippedMembersByOption[.stripSynthesizedMethods] = synthesizedMethods

        return strippedMembersByOption
    }

    // MARK: - Category

    /// The rendered `@interface` for the category identified by `uniqueName`
    /// (`ClassName(CategoryName)`), or `nil` when the indexed image has no
    /// such category.
    ///
    /// Categories carry no strip switches of their own — the switches all
    /// describe class or protocol members — so only the comment options
    /// apply, and `printExportedDeclarationsOnly`: a category on a class this
    /// image lists and provably does not export renders as an empty string.
    /// One on another image's class stays whole.
    public func categoryInterface(
        uniqueName: String,
        options: ObjCGenerationOptions = .default,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)? = nil
    ) -> SemanticString? {
        renderCategoryInterface(
            uniqueName: uniqueName,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder,
            marksOptionalContent: false
        )
    }

    /// The category identified by `uniqueName`, marked the way
    /// `markedClassInterface(named:cTypeReplacements:ivarOffsetCommentBuilder:)`
    /// marks a class — for a category, only its comments.
    public func markedCategoryInterface(
        uniqueName: String,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)? = nil
    ) -> SemanticString? {
        renderCategoryInterface(
            uniqueName: uniqueName,
            options: .default,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder,
            marksOptionalContent: true
        )
    }

    private func renderCategoryInterface(
        uniqueName: String,
        options: ObjCGenerationOptions,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)?,
        marksOptionalContent: Bool
    ) -> SemanticString? {
        guard let categoryInfo = indexer.categoryGroup(forName: uniqueName)?.info else { return nil }

        // A category on a class this image lists and provably does not export
        // goes with it, as MachOSwiftSection drops an extension of an
        // unexported type of its image. One on another image's class, whose
        // export this image cannot speak for, stays whole: its members have
        // no symbols to be judged by.
        let isExcludedByExportFilter = indexer.exportStatus(ofClassNamed: categoryInfo.className)?.isDefinitelyNotExported == true
        if isExcludedByExportFilter, !marksOptionalContent, options.printExportedDeclarationsOnly {
            return SemanticString()
        }

        let context = makeContext(
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )
        if marksOptionalContent {
            context.optionalContentMarking = ObjCOptionalContentMarking()
        }

        if marksOptionalContent || options.addPropertyAccessorAddressComments {
            for method in categoryInfo.methods where method.imp != 0 {
                context.methodIMPs[method.name] = method.imp
            }
            for method in categoryInfo.classMethods where method.imp != 0 {
                context.classMethodIMPs[method.name] = method.imp
            }
        }

        let declaration = categoryInfo.semanticString(using: context)
        return isExcludedByExportFilter && marksOptionalContent ? Self.visibleWhileExportFilterIsOff(declaration) : declaration
    }

    // MARK: - Stripped Members

    /// The members of one declaration a strip switch removes, list by list —
    /// by name, as the metadata lists are filtered.
    private struct StrippedMembers {
        var ivars: Set<String> = []
        var classProperties: Set<String> = []
        var properties: Set<String> = []
        var classMethods: Set<String> = []
        var methods: Set<String> = []
    }

    /// Every member the protocols in `protocolInfos` and all their ancestors
    /// declare — required and optional, instance and class. A hand-written
    /// header does not redeclare them in an adopting class or a derived
    /// protocol, which is what `stripProtocolConformance` reproduces
    /// (proposal 0012). Each protocol is visited once, however many paths
    /// reach it: `NSObject` typically sits under several.
    private static func membersDeclared(byProtocolChainsOf protocolInfos: [ObjCProtocolInfo]) -> StrippedMembers {
        var declaredMembers = StrippedMembers()
        var visitedProtocolNames: Set<String> = []
        var pendingProtocolInfos = protocolInfos
        while let protocolInfo = pendingProtocolInfos.popLast() {
            guard visitedProtocolNames.insert(protocolInfo.name).inserted else { continue }
            declaredMembers.classProperties.formUnion((protocolInfo.classProperties + protocolInfo.optionalClassProperties).map(\.name))
            declaredMembers.properties.formUnion((protocolInfo.properties + protocolInfo.optionalProperties).map(\.name))
            declaredMembers.classMethods.formUnion((protocolInfo.classMethods + protocolInfo.optionalClassMethods).map(\.name))
            declaredMembers.methods.formUnion((protocolInfo.methods + protocolInfo.optionalMethods).map(\.name))
            pendingProtocolInfos.append(contentsOf: protocolInfo.protocols)
        }
        return declaredMembers
    }

    /// What the enabled switches strip together.
    private static func union(
        of strippedMembersByOption: [ObjCGenerationOptions.VisibilityOption: StrippedMembers],
        enabledIn options: ObjCGenerationOptions
    ) -> StrippedMembers {
        var union = StrippedMembers()
        for (option, strippedMembers) in strippedMembersByOption where options.isEnabled(option) {
            union.ivars.formUnion(strippedMembers.ivars)
            union.classProperties.formUnion(strippedMembers.classProperties)
            union.properties.formUnion(strippedMembers.properties)
            union.classMethods.formUnion(strippedMembers.classMethods)
            union.methods.formUnion(strippedMembers.methods)
        }
        return union
    }

    /// Every member some switch strips, with the switches that do.
    private static func marking(for strippedMembersByOption: [ObjCGenerationOptions.VisibilityOption: StrippedMembers]) -> ObjCOptionalContentMarking {
        var marking = ObjCOptionalContentMarking()
        func record(_ names: Set<String>, as kind: ObjCOptionalContentMarking.MemberKind, strippedBy option: ObjCGenerationOptions.VisibilityOption) {
            for name in names {
                marking.strippingOptionsByMember[ObjCOptionalContentMarking.Member(kind: kind, name: name), default: []].insert(option)
            }
        }
        for (option, strippedMembers) in strippedMembersByOption {
            record(strippedMembers.ivars, as: .ivar, strippedBy: option)
            record(strippedMembers.classProperties, as: .classProperty, strippedBy: option)
            record(strippedMembers.properties, as: .property, strippedBy: option)
            record(strippedMembers.classMethods, as: .classMethod, strippedBy: option)
            record(strippedMembers.methods, as: .method, strippedBy: option)
        }
        return marking
    }

    // MARK: - C Struct / Union

    /// The rendered definition of the C `struct` named `name`, or `nil` when
    /// the indexed image's type encodings never mentioned it.
    public func structInterface(
        named name: String,
        options: ObjCGenerationOptions = .default,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)? = nil
    ) -> SemanticString? {
        indexer.structSemanticString(
            forName: name,
            context: makeContext(
                options: options,
                cTypeReplacements: cTypeReplacements,
                ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
            )
        )
    }

    /// The rendered definition of the C `union` named `name`, or `nil` when
    /// the indexed image's type encodings never mentioned it.
    public func unionInterface(
        named name: String,
        options: ObjCGenerationOptions = .default,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)? = nil
    ) -> SemanticString? {
        indexer.unionSemanticString(
            forName: name,
            context: makeContext(
                options: options,
                cTypeReplacements: cTypeReplacements,
                ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
            )
        )
    }

    // MARK: - Shared Stripping

    /// Records the selectors the compiler would synthesize for `property`, so
    /// that `stripSynthesizedMethods` can remove them.
    ///
    /// A property contributes its getter (its own name unless `G` overrides
    /// it) and, unless read-only, a `setName:` setter (unless `S` overrides
    /// it).
    private func collectAccessorSelectors(
        of property: ObjCPropertyInfo,
        intoClassMethods classMethods: inout Set<String>,
        intoMethods methods: inout Set<String>
    ) {
        let propertyName = property.name

        let getterName = property.customGetter ?? propertyName
        if property.isClassProperty {
            classMethods.insert(getterName)
        } else {
            methods.insert(getterName)
        }

        // A read-only property synthesizes no setter, so a `setFoo:` the class
        // declares beside it was written by hand and is no accessor to strip.
        // (A public read-only property redeclared read-write in a class
        // extension carries no `R` in the metadata: clang emits the extension's
        // attributes.)
        guard !property.attributes.contains(.readonly) else { return }

        // The trailing colon is not cosmetic: these names are matched against
        // `ObjCMethodInfo.name`, which holds the full selector. A setter takes
        // an argument, so its selector is `setFoo:` — building `setFoo` here
        // both failed to strip the real accessor and risked stripping an
        // unrelated zero-argument method that happened to be named that way.
        // `customSetter` already carries its own colon, as it comes straight
        // from the property's `S` attribute.
        let setterName = property.customSetter ?? "set\(propertyName.box.uppercasedFirst()):"
        if property.isClassProperty {
            classMethods.insert(setterName)
        } else {
            methods.insert(setterName)
        }
    }
}

extension ObjCSuppliedClass.Kind {
    /// Why the image keeps no class object for a supplied class, written above
    /// its `@interface`. Always rendered, with no switch to turn it off:
    /// without it a class the runtime makes reads like one the image lists.
    var declarationComment: String {
        switch self {
        case .genericSwiftClass:
            "Generic Swift class, instantiated at runtime"
        case .swiftClassWithResilientAncestry:
            "Swift class with resilient ancestry, registered through __objc_stublist"
        case .swiftClassWithGenericAncestry:
            "Swift class with generic ancestry, registered through __objc_stublist"
        }
    }
}
