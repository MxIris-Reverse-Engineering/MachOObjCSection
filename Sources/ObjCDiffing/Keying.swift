/// Index a sequence by a derived `ObjCAPIKey`, first element wins. Shared by
/// the two-sided differ and the N-way evolution matrix so both resolve a
/// container key held twice identically; a container's members go through
/// `ObjCMemberSelection` instead.
///
/// On a key collision this keeps the first element and drops the rest — which
/// could hide a removal — so the drop is surfaced, not silent:
/// `ObjCAPISnapshot.keyCollisions()` scans every container axis by the same
/// rule, and the results ride on `ObjCAPIDiff.diagnostics` /
/// `ObjCAPIEvolution.keyCollisionsByVersion` and the reporters' warnings
/// section. The realistic source is an image group, whose images can each
/// hold a class or protocol of one name; one linked image holds no two
/// containers of one name.
func keyedFirstWins<Element>(_ elements: [Element], by key: (Element) -> ObjCAPIKey) -> [ObjCAPIKey: Element] {
    var result: [ObjCAPIKey: Element] = [:]
    result.reserveCapacity(elements.count)
    for element in elements {
        let elementKey = key(element)
        if result[elementKey] == nil {
            result[elementKey] = element
        }
    }
    return result
}
