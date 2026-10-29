import Foundation
import Testing
@testable import ObjCDiffing

/// What an evolution of one image per version writes: image groups add
/// optional fields and report lines, and none of them may show up here, so a
/// consumer of the single-image JSON or report sees no difference.
@Suite("Single-image evolution output")
struct SingleImageEvolutionOutputTests {
    /// Three versions touching every value the JSON carries: container and
    /// member events of each status, a compatibility override, provenance on
    /// one version, and an identity-key collision in another.
    private static func evolution() throws -> ObjCAPIEvolution {
        let firstVersion = ObjCAPISnapshot(
            classes: [
                Fixtures.containerSnapshot(key: "class:Gone", name: "Gone"),
                Fixtures.containerSnapshot(key: "class:Widget", name: "Widget", members: [
                    Fixtures.record(identity: "method:-run", payload: "enc:v16@0:8", signature: "- (void)run;"),
                    Fixtures.record(identity: "method:-stop", payload: "enc:v16@0:8", signature: "- (void)stop;"),
                ]),
            ],
            protocols: [
                Fixtures.containerSnapshot(key: "protocol:Proto", name: "Proto", kind: .protocol),
            ]
        )
        let widgetAfterChange = Fixtures.containerSnapshot(key: "class:Widget", name: "Widget", members: [
            Fixtures.record(identity: "method:-run", payload: "enc:@16@0:8", signature: "- (id)run;"),
        ])
        let protocolWithRequirement = Fixtures.containerSnapshot(key: "protocol:Proto", name: "Proto", kind: .protocol, members: [
            Fixtures.record(identity: "method:-required", payload: "enc:v16@0:8|optional:0", signature: "- (void)required;", isOptionalRequirement: false),
        ])
        let secondVersion = ObjCAPISnapshot(
            classes: [widgetAfterChange],
            protocols: [protocolWithRequirement],
            categories: [
                Fixtures.containerSnapshot(key: "category:NSObject(Extras)", name: "NSObject(Extras)", kind: .category, members: [
                    Fixtures.record(identity: "method:-extra", payload: "enc:v16@0:8", signature: "- (void)extra;"),
                    Fixtures.record(identity: "method:-extra", payload: "enc:@16@0:8", signature: "- (id)extra;"),
                ]),
            ]
        )
        let thirdVersion = ObjCAPISnapshot(
            classes: [Fixtures.containerSnapshot(key: "class:Gone", name: "Gone"), widgetAfterChange],
            protocols: [protocolWithRequirement]
        )
        return try ObjCAPIEvolutionBuilder().evolution(
            of: [firstVersion, secondVersion, thirdVersion],
            versions: [
                ObjCAPIVersionDescriptor(label: "1.0", provenance: ObjCAPIProvenance(label: "1.0", binaryPath: "/v1/Example")),
                ObjCAPIVersionDescriptor(label: "2.0"),
                ObjCAPIVersionDescriptor(label: "3.0"),
            ]
        )
    }

    /// The JSON with its keys sorted and its whitespace removed, so the
    /// comparison is about which keys and values the encoding holds.
    private static func normalizedJSON(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try #require(String(data: normalized, encoding: .utf8))
    }

    @Test("The JSON holds exactly the keys and values it held before image groups")
    func jsonIsUnchanged() throws {
        let encoded = try ObjCAPIJSON.encoder().encode(Self.evolution())
        let expected = """
        {
          "categories": [
            {
              "containerKind": {"category": {}},
              "events": [
                {"status": {"added": {}}, "versionIndex": 1},
                {"status": {"removed": {}}, "versionIndex": 2}
              ],
              "key": "category:NSObject(Extras)",
              "memberLineages": [],
              "name": "NSObject(Extras)",
              "presence": [false, true, false]
            }
          ],
          "classes": [
            {
              "containerKind": {"class": {}},
              "events": [
                {"status": {"removed": {}}, "versionIndex": 1},
                {"status": {"added": {}}, "versionIndex": 2}
              ],
              "key": "class:Gone",
              "memberLineages": [],
              "name": "Gone",
              "presence": [true, false, true]
            },
            {
              "containerKind": {"class": {}},
              "events": [],
              "key": "class:Widget",
              "memberLineages": [
                {
                  "events": [
                    {"newSignature": "- (id)run;", "oldSignature": "- (void)run;", "status": {"modified": {}}, "versionIndex": 1}
                  ],
                  "key": "method:-run",
                  "kind": {"instanceMethod": {}},
                  "presence": [true, true, true]
                },
                {
                  "events": [
                    {"oldSignature": "- (void)stop;", "status": {"removed": {}}, "versionIndex": 1}
                  ],
                  "key": "method:-stop",
                  "kind": {"instanceMethod": {}},
                  "presence": [true, false, false]
                }
              ],
              "name": "Widget",
              "presence": [true, true, true]
            }
          ],
          "keyCollisionsByVersion": [
            [],
            [{"containerName": "NSObject(Extras)", "droppedSignatures": ["- (id)extra;"], "key": "method:-extra", "keptSignature": "- (void)extra;"}],
            []
          ],
          "protocols": [
            {
              "containerKind": {"protocol": {}},
              "events": [],
              "key": "protocol:Proto",
              "memberLineages": [
                {
                  "events": [
                    {"compatibilityOverride": {"breaking": {}}, "newSignature": "- (void)required;", "status": {"added": {}}, "versionIndex": 1}
                  ],
                  "key": "method:-required",
                  "kind": {"instanceMethod": {}},
                  "presence": [false, true, true]
                }
              ],
              "name": "Proto",
              "presence": [true, true, true]
            }
          ],
          "versions": [
            {"label": "1.0", "provenance": {"binaryPath": "/v1/Example", "label": "1.0"}},
            {"label": "2.0"},
            {"label": "3.0"}
          ]
        }
        """
        #expect(try Self.normalizedJSON(encoded) == Self.normalizedJSON(Data(expected.utf8)))
    }

    @Test("The report reads as it did before image groups")
    func reportIsUnchanged() throws {
        let expected = """
        ObjC API evolution across 3 versions: 1.0 → 2.0 → 3.0

        Transitions:
          1.0 → 2.0: 2 added · 2 removed · 1 modified · API-breaking
          2.0 → 3.0: 1 added · 1 removed · API-breaking
        First API-breaking transition: 1.0 → 2.0

        Classes:
          [●○●] Gone
              - removed in 2.0
              + added in 3.0
          [●●●] Widget
              [●●●] - (id)run;
                  ~ modified in 2.0: - (void)run; → - (id)run;
              [●○○] - (void)stop;
                  - removed in 2.0

        Protocols:
          [●●●] Proto
              [○●●] - (void)required;
                  + added in 2.0

        Categories:
          [○●○] NSObject(Extras)
              + added in 2.0
              - removed in 3.0

        Warnings — identity-key collisions (only the kept record was compared):
          2.0 · NSObject(Extras) · kept: - (void)extra; · dropped: - (id)extra;
        """
        #expect(try ObjCAPIEvolutionReporter().report(Self.evolution()) == expected)
    }
}
