import Foundation
import Network

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]  // lowercased names
    var body: Data

    /// Returns nil until the buffer holds a complete request.
    static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { return nil }
        let body = buffer[bodyStart..<buffer.index(bodyStart, offsetBy: length)]
        let path = String(requestLine[1]).components(separatedBy: "?")[0]
        return HTTPRequest(method: String(requestLine[0]), path: path, headers: headers, body: Data(body))
    }
}

struct HTTPResponse {
    var status: Int
    var body: Data
    var contentType = "application/json"

    static func json(_ status: Int, _ object: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: data)
    }

    func serialize() -> Data {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

final class HTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private let maxRequestBytes = 32 << 20

    init(host: String, port: UInt16, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params)
        self.handler = handler
    }

    func start(onReady: @escaping @Sendable () -> Void) {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: onReady()
            case .failed(let error):
                FileHandle.standardError.write(Data("listener failed: \(error)\n".utf8))
                exit(1)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.receive(connection, buffer: Data())
        }
        listener.start(queue: .global())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest.parse(buffer) {
                Task {
                    let response = await self.handler(request)
                    connection.send(content: response.serialize(), completion: .contentProcessed { _ in connection.cancel() })
                }
            } else if buffer.count > self.maxRequestBytes {
                let response = HTTPResponse.json(413, ["detail": "Request too large"])
                connection.send(content: response.serialize(), completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }
}
