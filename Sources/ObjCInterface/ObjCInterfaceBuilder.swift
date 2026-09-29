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
/// through to the renderer untouched.
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
        let indexer = self.indexer
        return ObjCRenderingContext(
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
    /// renders for those options. `nil` when the indexed image has no such
    /// class.
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
        guard let classGroup = indexer.classGroup(forName: name),
              let currentClassInfo = classGroup.info.first
        else { return nil }

        let context = makeContext(
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )

        let strippedMembersByOption = strippedMembers(ofClass: currentClassInfo, superclassInfos: classGroup.info.dropFirst())

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

        return finalClassInfo.semanticString(using: context)
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

        var conformances = StrippedMembers()
        for protocolInfo in classInfo.protocols {
            conformances.classProperties.formUnion(protocolInfo.classProperties.map(\.name))
            conformances.properties.formUnion(protocolInfo.properties.map(\.name))
            conformances.classMethods.formUnion(protocolInfo.classMethods.map(\.name))
            conformances.methods.formUnion(protocolInfo.methods.map(\.name))
        }
        strippedMembersByOption[.stripProtocolConformance] = conformances

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

        var conformances = StrippedMembers()
        for inheritedProtocolInfo in protocolInfo.protocols {
            conformances.classProperties.formUnion(inheritedProtocolInfo.classProperties.map(\.name))
            conformances.properties.formUnion(inheritedProtocolInfo.properties.map(\.name))
            conformances.classMethods.formUnion(inheritedProtocolInfo.classMethods.map(\.name))
            conformances.methods.formUnion(inheritedProtocolInfo.methods.map(\.name))

            conformances.classProperties.formUnion(inheritedProtocolInfo.optionalClassProperties.map(\.name))
            conformances.properties.formUnion(inheritedProtocolInfo.optionalProperties.map(\.name))
            conformances.classMethods.formUnion(inheritedProtocolInfo.optionalClassMethods.map(\.name))
            conformances.methods.formUnion(inheritedProtocolInfo.optionalMethods.map(\.name))
        }
        strippedMembersByOption[.stripProtocolConformance] = conformances

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
    /// describe class or protocol members — so only the comment options apply.
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

        return categoryInfo.semanticString(using: context)
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
    /// it) and, unless read-only in practice, a `setName:` setter (unless `S`
    /// overrides it).
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
