@preconcurrency import Contacts
import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - ContactsToolKit

/// 連絡先を操作する ToolKit
///
/// Contacts framework を使用して、連絡先の検索・詳細取得・新規作成を提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     ContactsToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `search_contacts`: 名前・電話番号・メールアドレスで連絡先を検索
/// - `get_contact`: ID で連絡先の詳細情報を取得
/// - `create_contact`: 新しい連絡先を作成
public final class ContactsToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "contacts"

    private let contactStore: CNContactStore
    private let guard_: PermissionGuard

    // MARK: - Initialization

    /// ContactsToolKit を作成
    ///
    /// - Parameter contactStore: 使用する CNContactStore（デフォルトは新規インスタンス）
    public init(contactStore: CNContactStore = CNContactStore()) {
        self.contactStore = contactStore
        self.guard_ = PermissionGuard(
            provider: ContactsPermission(contactStore: contactStore)
        )
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            searchContactsTool,
            getContactTool,
            createContactTool,
        ]
    }

    // MARK: - search_contacts

    private var searchContactsTool: BuiltInTool {
        BuiltInTool(
            name: "search_contacts",
            description: "Search contacts by name, phone number, or email address. "
                + "Returns matching contacts with basic info (name, phone, email, organization). "
                + "Use get_contact with the contact ID for full details.",
            inputSchema: .object(
                properties: [
                    "query": .string(
                        description: "Search query — matches against name, phone number, or email address"
                    ),
                    "limit": .integer(
                        description: "Maximum number of contacts to return (default: 20, max: 100)"
                    ),
                ],
                required: ["query"]
            ),
            annotations: ToolAnnotations(
                title: "Search Contacts",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [contactStore, guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(SearchContactsInput.self, from: data)
            let limit = min(input.limit ?? 20, 100)
            let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !query.isEmpty else {
                return .error("Query must not be empty.")
            }

            let predicate = CNContact.predicateForContacts(matchingName: query)
            let keys = ContactsFetchKeys.summary

            do {
                var contacts = try contactStore.unifiedContacts(
                    matching: predicate,
                    keysToFetch: keys
                )

                // 名前でヒットしない場合、電話番号・メールでも検索
                if contacts.isEmpty {
                    let allPredicate = CNContact.predicateForContactsInContainer(
                        withIdentifier: contactStore.defaultContainerIdentifier()
                    )
                    let allContacts = try contactStore.unifiedContacts(
                        matching: allPredicate,
                        keysToFetch: keys
                    )
                    let lowered = query.lowercased()
                    contacts = allContacts.filter { contact in
                        contact.phoneNumbers.contains {
                            $0.value.stringValue.contains(lowered)
                        }
                        || contact.emailAddresses.contains {
                            ($0.value as String).lowercased().contains(lowered)
                        }
                    }
                }

                let result = Array(contacts.prefix(limit)).map { ContactInfo(from: $0) }
                return try .encoded(result)
            } catch {
                return .error("Failed to search contacts: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - get_contact

    private var getContactTool: BuiltInTool {
        BuiltInTool(
            name: "get_contact",
            description: "Get detailed information for a specific contact by ID. "
                + "Returns full details including address, birthday, and notes. "
                + "Use search_contacts first to find the contact ID.",
            inputSchema: .object(
                properties: [
                    "id": .string(description: "Contact identifier from search_contacts results"),
                ],
                required: ["id"]
            ),
            annotations: ToolAnnotations(
                title: "Get Contact",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [contactStore, guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(GetContactInput.self, from: data)
            let keys = ContactsFetchKeys.detail

            do {
                let predicate = CNContact.predicateForContacts(withIdentifiers: [input.id])
                let contacts = try contactStore.unifiedContacts(
                    matching: predicate,
                    keysToFetch: keys
                )

                guard let contact = contacts.first else {
                    return .error("Contact not found with ID: \(input.id)")
                }

                return try .encoded(ContactDetailInfo(from: contact))
            } catch {
                return .error("Failed to get contact: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - create_contact

    private var createContactTool: BuiltInTool {
        BuiltInTool(
            name: "create_contact",
            description: "Create a new contact. At least one of given_name, family_name, or organization_name is required. "
                + "Returns the created contact details including its ID.",
            inputSchema: .object(
                properties: [
                    "given_name": .string(description: "First name / given name"),
                    "family_name": .string(description: "Last name / family name"),
                    "organization_name": .string(description: "Company or organization name"),
                    "phone_numbers": .array(
                        description: "Phone numbers with optional labels",
                        items: .object(
                            properties: [
                                "label": .string(description: "Label: 'mobile', 'home', 'work', or custom (default: 'mobile')"),
                                "number": .string(description: "Phone number string"),
                            ],
                            required: ["number"]
                        )
                    ),
                    "email_addresses": .array(
                        description: "Email addresses",
                        items: .string()
                    ),
                    "note": .string(description: "Notes about the contact"),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Create Contact",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ) { [contactStore, guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(CreateContactInput.self, from: data)

            // 最低限の識別情報が必要
            let hasName = !(input.givenName?.isEmpty ?? true)
                || !(input.familyName?.isEmpty ?? true)
                || !(input.organizationName?.isEmpty ?? true)
            guard hasName else {
                return .error(
                    "At least one of given_name, family_name, or organization_name is required."
                )
            }

            let mutableContact = CNMutableContact()
            mutableContact.givenName = input.givenName ?? ""
            mutableContact.familyName = input.familyName ?? ""
            mutableContact.organizationName = input.organizationName ?? ""
            mutableContact.note = input.note ?? ""

            if let phones = input.phoneNumbers {
                mutableContact.phoneNumbers = phones.map { phone in
                    let label = Self.phoneLabel(from: phone.label)
                    return CNLabeledValue(
                        label: label,
                        value: CNPhoneNumber(stringValue: phone.number)
                    )
                }
            }

            if let emails = input.emailAddresses {
                mutableContact.emailAddresses = emails.map { email in
                    CNLabeledValue(label: CNLabelHome, value: email as NSString)
                }
            }

            let saveRequest = CNSaveRequest()
            saveRequest.add(mutableContact, toContainerWithIdentifier: nil)

            do {
                try contactStore.execute(saveRequest)
                // 保存後に詳細を取得して返す
                let predicate = CNContact.predicateForContacts(
                    withIdentifiers: [mutableContact.identifier]
                )
                let saved = try contactStore.unifiedContacts(
                    matching: predicate,
                    keysToFetch: ContactsFetchKeys.detail
                )
                if let contact = saved.first {
                    return try .encoded(ContactDetailInfo(from: contact))
                }
                // フォールバック: 保存したデータから直接構築
                return try .encoded(ContactDetailInfo(from: mutableContact as CNContact))
            } catch {
                return .error("Failed to create contact: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private static func phoneLabel(from string: String?) -> String {
        switch string?.lowercased() {
        case "mobile", "cell":
            return CNLabelPhoneNumberMobile
        case "home":
            return CNLabelHome
        case "work":
            return CNLabelWork
        case "main":
            return CNLabelPhoneNumberMain
        case .none:
            return CNLabelPhoneNumberMobile
        default:
            return string ?? CNLabelPhoneNumberMobile
        }
    }
}
