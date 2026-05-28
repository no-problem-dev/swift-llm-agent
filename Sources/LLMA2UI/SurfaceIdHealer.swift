import A2UICore

/// Rewrites `createSurface` IDs that collide with surfaces already managed by the host,
/// so a noisy LLM that reuses surface IDs doesn't crash the processor.
///
/// `updateComponents` / `updateDataModel` / `deleteSurface` are forwarded with the rewritten id.
internal enum SurfaceIdHealer {
    static func heal(_ messages: [ServerMessage], existing: Set<String>) -> [ServerMessage] {
        var renames: [String: String] = [:]
        var taken = existing
        return messages.map { rewrite($0, renames: &renames, taken: &taken) }
    }

    private static func rewrite(
        _ message: ServerMessage,
        renames: inout [String: String],
        taken: inout Set<String>
    ) -> ServerMessage {
        switch message {
        case .createSurface(let cs):
            let original = cs.surfaceId
            let resolved = renames[original]
                ?? (taken.contains(original) ? freshId(original, taken: taken) : original)
            if resolved != original {
                renames[original] = resolved
            }
            taken.insert(resolved)
            return .createSurface(CreateSurface(
                surfaceId: resolved,
                catalogId: cs.catalogId,
                theme: cs.theme,
                sendDataModel: cs.sendDataModel
            ))

        case .updateComponents(let uc):
            let resolved = renames[uc.surfaceId] ?? uc.surfaceId
            guard resolved != uc.surfaceId else {
                return message
            }
            return .updateComponents(UpdateComponents(surfaceId: resolved, components: uc.components))

        case .updateDataModel(let udm):
            let resolved = renames[udm.surfaceId] ?? udm.surfaceId
            guard resolved != udm.surfaceId else {
                return message
            }
            return .updateDataModel(UpdateDataModel(surfaceId: resolved, path: udm.path, value: udm.value))

        case .deleteSurface(let ds):
            let resolved = renames[ds.surfaceId] ?? ds.surfaceId
            guard resolved != ds.surfaceId else {
                return message
            }
            return .deleteSurface(DeleteSurface(surfaceId: resolved))
        }
    }

    private static func freshId(_ original: String, taken: Set<String>) -> String {
        var counter = 2
        while taken.contains("\(original)-\(counter)") {
            counter += 1
        }
        return "\(original)-\(counter)"
    }
}
