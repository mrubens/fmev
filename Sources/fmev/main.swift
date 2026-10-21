import Foundation
import FoundationModels

// A local server that speaks TypeSafe's System One HTTP API (POST /v1/systemone,
// GET /v1/models) and answers with Apple's on-device Foundation Models.

let usage = """
fmev \(fmevVersion): TypeSafe System One (Jev) API on Apple's on-device Foundation Model

Usage: fmev [--help | --version]

Starts a server on http://127.0.0.1:8787 with these endpoints:
  POST /v1/systemone   answer noul, choice and score questions about a state
  GET  /v1/models      list models (fmev; jev-latest is an alias)
  GET  /health         readiness check

Configure it with environment variables:
  FMEV_HOST, FMEV_PORT    listen address (default 127.0.0.1:8787)
  FMEV_API_KEY            require Authorization: Bearer <key>
  FMEV_CONCURRENCY        on-device generations in flight (4)
  FMEV_RUNNER_UP          1: ask for a runner-up so alternatives aren't split evenly (slower)

Requires an Apple Silicon Mac on macOS 27+ with Apple Intelligence turned on.
https://github.com/mrubens/fmev
"""

switch CommandLine.arguments.dropFirst().first {
case nil: break
case "-h", "--help": print(usage); exit(0)
case "-v", "--version": print("fmev \(fmevVersion)"); exit(0)
case let other?:
    FileHandle.standardError.write(Data("fmev: unknown argument '\(other)'; see fmev --help\n".utf8))
    exit(2)
}

let env = ProcessInfo.processInfo.environment
let host = env["FMEV_HOST"] ?? "127.0.0.1"
let port = UInt16(env["FMEV_PORT"] ?? "") ?? 8787
let apiKey = env["FMEV_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
let modelName = "fmev"

var config = EngineConfig()
if let v = env["FMEV_CONCURRENCY"].flatMap(Int.init) { config.concurrency = max(1, v) }
config.runnerUp = ["1", "true", "yes"].contains(env["FMEV_RUNNER_UP"]?.lowercased() ?? "")

let engine = Engine(config: config)
let models: [[String: Any]] = [
    ["name": modelName, "description": "Apple Foundation Models (on-device), probabilities from the model's stated confidence.", "release_date": "2026-09-15"],
    ["name": "jev-latest", "description": "Alias for \(modelName).", "release_date": "2026-09-15"],
]

func authorized(_ request: HTTPRequest) -> Bool {
    guard let apiKey else { return true }
    return request.headers["authorization"] == "Bearer \(apiKey)"
}

func handle(_ request: HTTPRequest) async -> HTTPResponse {
    let started = Date()
    let response = await route(request)
    let ms = Int(Date().timeIntervalSince(started) * 1000)
    print("\(request.method) \(request.path) -> \(response.status) (\(ms) ms)")
    return response
}

func route(_ request: HTTPRequest) async -> HTTPResponse {
    switch (request.method, request.path) {
    case ("GET", "/health"):
        return .json(engine.availabilityProblem == nil ? 200 : 503,
                     ["ok": engine.availabilityProblem == nil, "detail": engine.availabilityProblem ?? "ready"])
    case ("GET", "/v1/models"):
        guard authorized(request) else { return .json(401, ["detail": "Not authenticated"]) }
        return .json(200, ["models": models])
    case ("POST", "/v1/systemone"):
        guard authorized(request) else { return .json(401, ["detail": "Not authenticated"]) }
        if let problem = engine.availabilityProblem { return .json(503, ["detail": problem]) }
        do {
            let parsed = try parseSystemOneRequest(
                request.body, allowImages: request.headers["typesafe-danger-zone-images"] == "true")
            let (answers, usage) = try await engine.evaluate(parsed)
            return .json(200, [
                "model": modelName,
                "answers": answers,
                "usage": ["input_tokens": usage.input, "output_tokens": usage.output],
            ])
        } catch let failure as ValidationFailure {
            return .json(422, failure.body)
        } catch let error as EngineError {
            return .json(error.status, ["detail": error.detail])
        } catch {
            return .json(500, ["detail": error.localizedDescription])
        }
    case (_, "/v1/systemone"), (_, "/v1/models"):
        return .json(405, ["detail": "Method Not Allowed"])
    default:
        return .json(404, ["detail": "Not Found"])
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
if let problem = engine.availabilityProblem {
    print("warning: \(problem)")
} else {
    engine.prewarm()
}

let server = try HTTPServer(host: host, port: port) { await handle($0) }
server.start {
    print("fmev listening on http://\(host):\(port) (concurrency=\(config.concurrency)\(config.runnerUp ? ", runner-up on" : "")\(apiKey == nil ? "" : ", auth on"))")
}
dispatchMain()
