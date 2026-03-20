import Foundation

enum InteractiveSkillCatalog {
    static func loadInteractiveSkills() -> [AgentSkillDefinition] {
        do {
            return try loadBundledSkills()
        } catch {
            assertionFailure("Failed to load bundled interactive skills: \(error)")
            return []
        }
    }

    static func loadBundledSkills() throws -> [AgentSkillDefinition] {
        guard let resourceRoot = Bundle.module.resourceURL?.appendingPathComponent("InteractiveSkills") else {
            throw CatalogError.missingResourceRoot
        }
        var skills = try SkillLoader.loadSkills(from: resourceRoot)
        skills.sort { $0.displayOrder < $1.displayOrder }
        return skills
    }
}

extension InteractiveSkillCatalog {
    enum CatalogError: Error, CustomStringConvertible {
        case missingResourceRoot

        var description: String {
            switch self {
            case .missingResourceRoot:
                "InteractiveSkills resource root not found in Bundle.module."
            }
        }
    }
}
