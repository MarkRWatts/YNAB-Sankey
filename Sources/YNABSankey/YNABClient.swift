import Foundation

// Thin read-only client for the YNAB API (https://api.ynab.com/v1), Personal
// Access Token auth. Amounts are milliunits throughout (1000 = one currency unit).

typealias Milliunits = Int64

struct YNABError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct YNABCurrencyFormat: Decodable, Hashable, Sendable {
    let isoCode: String
}

struct YNABBudgetSummary: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let lastModifiedOn: String?
    let currencyFormat: YNABCurrencyFormat?
}

struct YNABAccount: Decodable, Sendable {
    let id: String
    let name: String
    let onBudget: Bool
    let deleted: Bool
}

struct YNABCategory: Decodable, Sendable {
    let id: String
    let name: String
    let categoryGroupId: String
    let hidden: Bool
    let deleted: Bool
}

struct YNABCategoryGroup: Decodable, Sendable {
    let id: String
    let name: String
    let hidden: Bool
    let deleted: Bool
    let categories: [YNABCategory]
}

struct YNABSubtransaction: Decodable, Sendable {
    let id: String
    let amount: Milliunits
    let payeeName: String?
    let categoryId: String?
    let transferAccountId: String?
    let deleted: Bool
}

struct YNABTransaction: Decodable, Sendable {
    let id: String
    let date: String // "YYYY-MM-DD"
    let amount: Milliunits
    let payeeName: String?
    let accountId: String
    let categoryId: String?
    let transferAccountId: String?
    let deleted: Bool
    let subtransactions: [YNABSubtransaction]
}

private struct Envelope<T: Decodable>: Decodable { let data: T }

struct YNABClient: Sendable {
    let token: String
    private static let base = URL(string: "https://api.ynab.com/v1")!

    private func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        var request = URLRequest(url: Self.base.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw YNABError(message: "Couldn't reach YNAB — check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: break
        case 401: throw YNABError(message: "YNAB rejected the access token — it may be wrong or revoked.")
        case 429: throw YNABError(message: "YNAB's rate limit was hit — try again in a few minutes.")
        default: throw YNABError(message: "YNAB API error (\(status)).")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Envelope<T>.self, from: data).data
    }

    func budgets() async throws -> [YNABBudgetSummary] {
        struct Payload: Decodable { let budgets: [YNABBudgetSummary] }
        return try await get("budgets", as: Payload.self).budgets
    }

    func accounts(budgetId: String) async throws -> [YNABAccount] {
        struct Payload: Decodable { let accounts: [YNABAccount] }
        return try await get("budgets/\(budgetId)/accounts", as: Payload.self).accounts
    }

    func categoryGroups(budgetId: String) async throws -> [YNABCategoryGroup] {
        struct Payload: Decodable { let categoryGroups: [YNABCategoryGroup] }
        return try await get("budgets/\(budgetId)/categories", as: Payload.self).categoryGroups
    }

    /// The budget's entire transaction history — YNAB has no default date bound.
    func transactions(budgetId: String) async throws -> [YNABTransaction] {
        struct Payload: Decodable { let transactions: [YNABTransaction] }
        return try await get("budgets/\(budgetId)/transactions", as: Payload.self).transactions
    }
}
