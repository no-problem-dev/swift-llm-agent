import Foundation

enum InteractiveSkillCatalog {
    private static let orderedSkillNames = [
        "morning",
        "journal",
        "plan",
        "research",
        "draft",
        "brainstorm",
        "decide",
        "learn",
        "next_action",
        "handoff_draft",
        "read_later_distill",
        "meeting_prep_light",
        "capture_to_tasks",
        "context_restart",
    ]

    static func loadInteractiveSkills() -> [AgentSkillDefinition] {
        do {
            return try loadBundledSkills()
        } catch {
            preconditionFailure("Failed to load bundled interactive skills: \(error)")
        }
    }

    static func loadBundledSkills() throws -> [AgentSkillDefinition] {
        guard let resourceRoot = Bundle.module.resourceURL?.appendingPathComponent("InteractiveSkills") else {
            throw CatalogError.missingResourceRoot
        }

        return try orderedSkillNames.map { name in
            let fileURL = resourceRoot
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("SKILL.md", isDirectory: false)

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw CatalogError.missingSkillFile(name: name, fileURL: fileURL)
            }

            let skill = try SkillLoader.loadSkill(from: fileURL)
            guard skill.name == name else {
                throw CatalogError.nameMismatch(expected: name, actual: skill.name, fileURL: fileURL)
            }
            return skill
        }
    }
}

extension InteractiveSkillCatalog {
    enum CatalogError: Error, CustomStringConvertible {
        case missingResourceRoot
        case missingSkillFile(name: String, fileURL: URL)
        case nameMismatch(expected: String, actual: String, fileURL: URL)

        var description: String {
            switch self {
            case .missingResourceRoot:
                "InteractiveSkills resource root not found in Bundle.module."
            case .missingSkillFile(let name, let fileURL):
                "Missing SKILL.md for '\(name)' at \(fileURL.path)."
            case .nameMismatch(let expected, let actual, let fileURL):
                "SKILL.md name mismatch at \(fileURL.path): expected '\(expected)', got '\(actual)'."
            }
        }
    }
}
