//
//  HTMLFetching.swift
//  NivyBar
//

import Foundation

// MARK: - Protocol

protocol HTMLFetching: Sendable {
    func fetch(urlString: String) async throws -> String
    func fetchViaJina(urlString: String) async throws -> String
}

// MARK: - Default implementation

final class HTMLFetcher: HTMLFetching {

    private let timeout: TimeInterval

    init(timeout: TimeInterval = Configuration.Network.timeout) {
        self.timeout = timeout
    }

    nonisolated func fetch(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NivyBarError.invalidURL(urlString)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(Configuration.Network.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Configuration.Network.acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(Configuration.Network.acceptLanguageHeader, forHTTPHeaderField: "Accept-Language")
        request.setValue(Configuration.Network.cacheControlHeader, forHTTPHeaderField: "Cache-Control")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) {
                return html
            }
            throw NivyBarError.parseFailure("Could not decode response from \(urlString)")
        } catch let e as NivyBarError {
            throw e
        } catch {
            throw NivyBarError.networkFailure(error.localizedDescription)
        }
    }

    nonisolated func fetchViaJina(urlString: String) async throws -> String {
        let jinaURL = Configuration.Jina.baseURL + urlString
        guard let url = URL(string: jinaURL) else {
            throw NivyBarError.invalidURL(jinaURL)
        }
        var request = URLRequest(url: url, timeoutInterval: Configuration.Network.jinaTimeout)
        request.setValue(Configuration.Network.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Configuration.Network.acceptHeader, forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) {
                return html
            }
            throw NivyBarError.jinaFallbackFailed("Could not decode Jina response from \(urlString)")
        } catch let e as NivyBarError {
            throw e
        } catch {
            throw NivyBarError.networkFailure(error.localizedDescription)
        }
    }
}
