import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLRequest/URLSession live here on Linux
#endif

/// The one seam between the client and the network, so tests can drive the
/// client without standing up a server or swapping in a URLProtocol.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
