import Foundation
import Network

final class LocalHTTPServer {
    enum SaveResult {
        case saved
        case cancelled
        case failed(String)
    }

    private struct ResolvedResource {
        let fileURL: URL
        let requestedPath: String
        let contentEncoding: String?
    }

    private struct ParsedRequest {
        let method: String
        let rawPath: String
        let headers: [String: String]
        let body: Data
    }

    private let rootURL: URL
    private let saveHandler: ((Data, String) -> SaveResult)?
    private let queue = DispatchQueue(label: "com.local.ncmconverter.server")
    private var listener: NWListener?

    init(rootURL: URL, saveHandler: ((Data, String) -> SaveResult)? = nil) {
        self.rootURL = rootURL
        self.saveHandler = saveHandler
    }

    func start() throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        let readySemaphore = DispatchSemaphore(value: 0)
        var boundPort: UInt16 = 0
        var startupError: Error?

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                boundPort = listener.port?.rawValue ?? 0
                readySemaphore.signal()
            case .failed(let error):
                startupError = error
                readySemaphore.signal()
            default:
                break
            }
        }

        listener.start(queue: queue)
        readySemaphore.wait()

        if let startupError {
            throw startupError
        }

        return boundPort
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulatedData: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            var requestData = accumulatedData
            if let data, !data.isEmpty {
                requestData.append(data)
            }

            if requestData.count >= 512 * 1024 * 1024 {
                let response = self.buildResponse(
                    status: "413 Payload Too Large",
                    mimeType: "text/plain",
                    body: Data("Payload Too Large".utf8)
                )
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            if let expectedLength = self.expectedRequestLength(for: requestData) {
                if requestData.count < expectedLength && !isComplete {
                    self.receiveRequest(on: connection, accumulatedData: requestData)
                    return
                }
            } else if !isComplete {
                if requestData.count >= 64 * 1024 {
                    let response = self.buildResponse(
                        status: "413 Payload Too Large",
                        mimeType: "text/plain",
                        body: Data("Payload Too Large".utf8)
                    )
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                }

                self.receiveRequest(on: connection, accumulatedData: requestData)
                return
            }

            guard !requestData.isEmpty else {
                connection.cancel()
                return
            }

            let response = self.makeResponse(for: requestData)

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func expectedRequestLength(for requestData: Data) -> Int? {
        guard let headerRange = requestData.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = requestData.subdata(in: 0..<headerRange.upperBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return requestData.count
        }

        let contentLength = headerString
            .components(separatedBy: "\r\n")
            .dropFirst()
            .compactMap { line -> Int? in
                let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else {
                    return nil
                }

                return pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length"
                    ? Int(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines))
                    : nil
            }
            .first ?? 0

        return headerRange.upperBound + contentLength
    }

    private func makeResponse(for requestData: Data) -> Data {
        guard let request = parseRequest(from: requestData) else {
            return buildResponse(status: "400 Bad Request", mimeType: "text/plain", body: Data("Bad Request".utf8))
        }

        if request.method == "POST" {
            return makePostResponse(for: request)
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            return buildResponse(status: "405 Method Not Allowed", mimeType: "text/plain", body: Data())
        }

        guard let resource = resolvedResource(for: request.rawPath) else {
            return buildResponse(status: "404 Not Found", mimeType: "text/plain", body: Data("Not Found".utf8), omitBody: request.method == "HEAD")
        }

        do {
            let body = try Data(contentsOf: resource.fileURL, options: .mappedIfSafe)
            let mimeType = mimeType(for: URL(fileURLWithPath: resource.requestedPath).pathExtension)
            let cacheControl = cacheControl(for: resource.requestedPath)
            return buildResponse(
                status: "200 OK",
                mimeType: mimeType,
                body: body,
                omitBody: request.method == "HEAD",
                contentEncoding: resource.contentEncoding,
                cacheControl: cacheControl
            )
        } catch {
            return buildResponse(status: "500 Internal Server Error", mimeType: "text/plain", body: Data("Internal Error".utf8), omitBody: request.method == "HEAD")
        }
    }

    private func parseRequest(from requestData: Data) -> ParsedRequest? {
        guard let headerRange = requestData.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = requestData.subdata(in: 0..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else {
                continue
            }

            let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let body = Data(requestData.suffix(from: headerRange.upperBound))

        return ParsedRequest(
            method: String(parts[0]),
            rawPath: String(parts[1]),
            headers: headers,
            body: body
        )
    }

    private func makePostResponse(for request: ParsedRequest) -> Data {
        guard normalizedPath(from: request.rawPath) == "/__save__" else {
            return buildResponse(status: "404 Not Found", mimeType: "text/plain", body: Data("Not Found".utf8))
        }

        guard let saveHandler else {
            return jsonResponse(status: "501 Not Implemented", payload: [
                "status": "error",
                "message": "Save handler unavailable."
            ])
        }

        guard let suggestedFilename = suggestedFilename(from: request.rawPath) else {
            return jsonResponse(status: "400 Bad Request", payload: [
                "status": "error",
                "message": "Missing filename."
            ])
        }

        switch saveHandler(request.body, suggestedFilename) {
        case .saved:
            return jsonResponse(status: "200 OK", payload: ["status": "saved"])
        case .cancelled:
            return jsonResponse(status: "200 OK", payload: ["status": "cancelled"])
        case .failed(let message):
            return jsonResponse(status: "500 Internal Server Error", payload: [
                "status": "error",
                "message": message
            ])
        }
    }

    private func resolvedResource(for rawPath: String) -> ResolvedResource? {
        let cleanPath = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        let normalizedPath = cleanPath == "/" ? "/index.html" : cleanPath
        let relativePath = normalizedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if let exactURL = existingFileURL(for: relativePath) {
            return ResolvedResource(fileURL: exactURL, requestedPath: normalizedPath, contentEncoding: nil)
        }

        if let compressedURL = existingFileURL(for: "\(relativePath).gz") {
            return ResolvedResource(fileURL: compressedURL, requestedPath: normalizedPath, contentEncoding: "gzip")
        }

        return nil
    }

    private func existingFileURL(for relativePath: String) -> URL? {
        let candidate = rootURL.appendingPathComponent(relativePath)
        let standardized = candidate.standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        let allowedPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"

        guard standardized.path.hasPrefix(allowedPrefix) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }

        return standardized
    }

    private func buildResponse(
        status: String,
        mimeType: String,
        body: Data,
        omitBody: Bool = false,
        contentEncoding: String? = nil,
        cacheControl: String = "no-cache"
    ) -> Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Content-Type: \(mimeType)\r\n"
        if let contentEncoding {
            header += "Content-Encoding: \(contentEncoding)\r\n"
            header += "Vary: Accept-Encoding\r\n"
        }
        header += "Cache-Control: \(cacheControl)\r\n"
        header += "Connection: close\r\n\r\n"

        var response = Data(header.utf8)
        if !omitBody {
            response.append(body)
        }
        return response
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html":
            return "text/html; charset=utf-8"
        case "js", "mjs":
            return "text/javascript; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "json":
            return "application/json; charset=utf-8"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "svg":
            return "image/svg+xml"
        case "mask":
            return "application/octet-stream"
        default:
            return "application/octet-stream"
        }
    }

    private func cacheControl(for requestedPath: String) -> String {
        if requestedPath.hasPrefix("/assets/") || requestedPath.hasPrefix("/vendor/") || requestedPath.hasPrefix("/static/") {
            return "public, max-age=31536000, immutable"
        }

        return "no-cache"
    }

    private func normalizedPath(from rawPath: String) -> String {
        URLComponents(string: "http://127.0.0.1\(rawPath)")?.path ?? rawPath
    }

    private func suggestedFilename(from rawPath: String) -> String? {
        guard
            let components = URLComponents(string: "http://127.0.0.1\(rawPath)"),
            let fileName = components.queryItems?.first(where: { $0.name == "filename" })?.value,
            !fileName.isEmpty
        else {
            return nil
        }

        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        return fileName.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    private func jsonResponse(status: String, payload: [String: String]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{}".utf8)
        return buildResponse(
            status: status,
            mimeType: "application/json; charset=utf-8",
            body: body
        )
    }
}
