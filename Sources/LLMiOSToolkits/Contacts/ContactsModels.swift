@preconcurrency import Contacts
import Foundation

// MARK: - Input Types

struct SearchContactsInput: Codable {
    var query: String
    var limit: Int?
}

struct GetContactInput: Codable {
    var id: String
}

struct CreateContactInput: Codable {
    var givenName: String?
    var familyName: String?
    var organizationName: String?
    var phoneNumbers: [PhoneNumberInput]?
    var emailAddresses: [String]?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case givenName = "given_name"
        case familyName = "family_name"
        case organizationName = "organization_name"
        case phoneNumbers = "phone_numbers"
        case emailAddresses = "email_addresses"
        case note
    }
}

struct PhoneNumberInput: Codable {
    var label: String?
    var number: String
}

// MARK: - Output Types

struct ContactInfo: Codable, Sendable {
    var id: String
    var givenName: String
    var familyName: String
    var organizationName: String?
    var phoneNumbers: [PhoneNumberInfo]
    var emailAddresses: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case givenName = "given_name"
        case familyName = "family_name"
        case organizationName = "organization_name"
        case phoneNumbers = "phone_numbers"
        case emailAddresses = "email_addresses"
    }
}

struct ContactDetailInfo: Codable, Sendable {
    var id: String
    var givenName: String
    var familyName: String
    var organizationName: String?
    var jobTitle: String?
    var phoneNumbers: [PhoneNumberInfo]
    var emailAddresses: [String]
    var postalAddresses: [PostalAddressInfo]
    var birthday: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case givenName = "given_name"
        case familyName = "family_name"
        case organizationName = "organization_name"
        case jobTitle = "job_title"
        case phoneNumbers = "phone_numbers"
        case emailAddresses = "email_addresses"
        case postalAddresses = "postal_addresses"
        case birthday, note
    }
}

struct PhoneNumberInfo: Codable, Sendable {
    var label: String?
    var number: String
}

struct PostalAddressInfo: Codable, Sendable {
    var label: String?
    var street: String
    var city: String
    var state: String
    var postalCode: String
    var country: String

    enum CodingKeys: String, CodingKey {
        case label, street, city, state
        case postalCode = "postal_code"
        case country
    }
}

// MARK: - CNContact Extensions

extension ContactInfo {
    init(from contact: CNContact) {
        self.id = contact.identifier
        self.givenName = contact.givenName
        self.familyName = contact.familyName
        self.organizationName = contact.organizationName.isEmpty ? nil : contact.organizationName
        self.phoneNumbers = contact.phoneNumbers.map { PhoneNumberInfo(from: $0) }
        self.emailAddresses = contact.emailAddresses.map { $0.value as String }
    }
}

extension ContactDetailInfo {
    init(from contact: CNContact) {
        self.id = contact.identifier
        self.givenName = contact.givenName
        self.familyName = contact.familyName
        self.organizationName = contact.organizationName.isEmpty ? nil : contact.organizationName
        self.jobTitle = contact.jobTitle.isEmpty ? nil : contact.jobTitle
        self.phoneNumbers = contact.phoneNumbers.map { PhoneNumberInfo(from: $0) }
        self.emailAddresses = contact.emailAddresses.map { $0.value as String }
        self.postalAddresses = contact.postalAddresses.map { PostalAddressInfo(from: $0) }
        self.birthday = contact.birthday.flatMap {
            Calendar.current.date(from: $0).map {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: $0)
            }
        }
        self.note = contact.note.isEmpty ? nil : contact.note
    }
}

extension PhoneNumberInfo {
    init(from labeled: CNLabeledValue<CNPhoneNumber>) {
        self.label = labeled.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) }
        self.number = labeled.value.stringValue
    }
}

extension PostalAddressInfo {
    init(from labeled: CNLabeledValue<CNPostalAddress>) {
        self.label = labeled.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) }
        let addr = labeled.value
        self.street = addr.street
        self.city = addr.city
        self.state = addr.state
        self.postalCode = addr.postalCode
        self.country = addr.country
    }
}

// MARK: - Fetch Key Sets

enum ContactsFetchKeys {
    /// search_contacts 用の最小限のキー
    static var summary: [CNKeyDescriptor] {
        [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
    }

    /// get_contact 用の詳細キー
    static var detail: [CNKeyDescriptor] {
        summary + [
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
        ]
    }
}
