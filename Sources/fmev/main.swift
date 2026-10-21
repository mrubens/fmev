import Foundation
import FoundationModels

// A local server that speaks TypeSafe's System One HTTP API (POST /v1/systemone,
// GET /v1/models) and answers with Apple's on-device Foundation Models.

let env = ProcessInfo.processInfo.environment
let host = env["FMEV_HOST"] ?? "127.0.0.1"
let port = UInt16(env["FMEV_PORT"] ?? "") ?? 8787
let apiKey = env["FMEV_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
let modelName = "fmev"

var config = EngineConfig()
if let v = env["FMEV_SAMPLES"].flatMap(Int.init) { config.samples = max(1, v) }
if let v = env["FMEV_TEMPERATURE"].flatMap(Double.init) { config.temperature = v }
if let v = env["FMEV_SMOOTHING"].flatMap(Double.init) { config.smoothing = max(0, v) }
if let v = env["FMEV_CONCURRENCY"].flatMap(Int.init) { config.concurrency = max(1, v) }
if env["FMEV_USE_CASE"] == "contentTagging" { config.useCase = .contentTagging }
if let v = env["FMEV_MODE"].flatMap(EngineConfig.Mode.init(rawValue:)) { config.mode = v }
if let v = env["FMEV_VERBAL_STYLE"].flatMap(EngineConfig.VerbalStyle.init(rawValue:)) { config.verbalStyle = v }
if let v = env["FMEV_EARLY_STOP"].flatMap(Int.init) { config.earlyStop = max(1, v) }

let engine = Engine(config: config)
let method = config.mode == .verbal
    ? "probabilities from the model's stated confidence (\(config.verbalStyle.rawValue))"
    : "probabilities estimated from up to \(config.samples) constrained samples (\(config.mode.rawValue))"
let models: [[String: Any]] = [
    ["name": modelName, "description": "Apple Foundation Models (on-device), \(method).", "release_date": "2026-09-15"],
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
            // Non-standard override for experimentation: X-FM-Samples: <n>
            let samples = request.headers["x-fm-samples"].flatMap(Int.init).map { min(max($0, 1), 64) } ?? config.samples
            let (answers, usage) = try await engine.evaluate(parsed, samples: samples)
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
    print("fmev listening on http://\(host):\(port) (mode=\(config.mode.rawValue)\(config.mode == .verbal ? "/" + config.verbalStyle.rawValue : ""), samples=\(config.samples), concurrency=\(config.concurrency)\(apiKey == nil ? "" : ", auth on"))")
}
dispatchMain()
