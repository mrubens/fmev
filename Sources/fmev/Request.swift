import Foundation

/// A question from a TypeSafe System One request, after validation.
struct Question {
    enum Kind {
        /// Criteria descriptions for the yes (`true`) and no (`false`) outcomes.
        case noul(yes: Any?, no: Any?)
        /// Choice names with optional descriptions, in request order.
        case choice([(name: String, description: Any?)])
        /// Ordered level descriptions; level i scores i.
        case score([Any])
    }

    let id: String
    let instructions: Any?
    let kind: Kind
}

struct SystemOneRequest {
    let model: String
    let state: Any
    let questions: [Question]
}

/// FastAPI-style validation error, matching the hosted API's 422 body.
struct ValidationIssue {
    let loc: [Any]
    let msg: String
    let type: String

    var json: [String: Any] { ["loc": loc, "msg": msg, "type": type] }
}

struct ValidationFailure: Error {
    let issues: [ValidationIssue]
    var body: [String: Any] { ["detail": issues.map(\.json)] }
}

private func isStructured(_ value: Any) -> Bool {
    value is String || value is [String: Any] || value is [Any]
}

/// Parses and validates a POST /v1/systemone body against the hosted API's schema.
func parseSystemOneRequest(_ body: Data, allowImages: Bool) throws -> SystemOneRequest {
    var issues: [ValidationIssue] = []
    func fail(_ loc: [Any], _ msg: String, _ type: String) {
        issues.append(ValidationIssue(loc: ["body"] + loc, msg: msg, type: type))
    }

    guard let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]),
          let root = object as? [String: Any] else {
        throw ValidationFailure(issues: [ValidationIssue(loc: ["body"], msg: "JSON decode error", type: "json_invalid")])
    }

    let model = root["model"] as? String
    if root["model"] == nil { fail(["model"], "Field required", "missing") }
    else if model == nil { fail(["model"], "Input should be a valid string", "string_type") }

    let state = root["state"]
    if state == nil { fail(["state"], "Field required", "missing") }
    else if !isStructured(state!) { fail(["state"], "Input should be a string, object, or array", "union_type") }

    if root["assets"] != nil {
        fail(["assets"], "Image assets are not supported by the local Foundation Models backend", "unsupported")
    }

    var questions: [Question] = []
    if let raw = root["questions"] {
        if let dict = raw as? [String: Any], !dict.isEmpty {
            for id in dict.keys.sorted() {
                let loc: [Any] = ["questions", id]
                guard let q = dict[id] as? [String: Any] else {
                    fail(loc, "Input should be a valid dictionary", "dict_type"); continue
                }
                let instructions = q["instructions"].flatMap { $0 is NSNull ? nil : $0 }
                if let instructions, !isStructured(instructions) {
                    fail(loc + ["instructions"], "Input should be a string, object, or array", "union_type")
                }
                switch q["type"] as? String {
                case "noul":
                    var yes: Any?, no: Any?
                    if let c = q["criteria"], !(c is NSNull) {
                        if let c = c as? [String: Any] {
                            yes = c["true"]; no = c["false"]
                        } else {
                            fail(loc + ["noul", "criteria"], "Input should be a valid dictionary", "dict_type")
                        }
                    }
                    questions.append(Question(id: id, instructions: instructions, kind: .noul(yes: yes, no: no)))
                case "choice":
                    guard let c = q["criteria"] else { fail(loc + ["choice", "criteria"], "Field required", "missing"); continue }
                    guard let c = c as? [String: Any], (1...255).contains(c.count) else {
                        fail(loc + ["choice", "criteria"], "Criteria must be an object with 1 to 255 choices", "value_error"); continue
                    }
                    let options = c.keys.sorted().map { name -> (name: String, description: Any?) in
                        let d = c[name]!
                        return (name, d is NSNull ? nil : d)
                    }
                    questions.append(Question(id: id, instructions: instructions, kind: .choice(options)))
                case "score":
                    guard let c = q["criteria"] else { fail(loc + ["score", "criteria"], "Field required", "missing"); continue }
                    guard let c = c as? [Any], (1...10).contains(c.count), c.allSatisfy(isStructured) else {
                        fail(loc + ["score", "criteria"], "Criteria must be an array of 1 to 10 levels", "value_error"); continue
                    }
                    questions.append(Question(id: id, instructions: instructions, kind: .score(c)))
                case "box":
                    if !allowImages {
                        fail(loc + ["box"], "Box questions require the header TypeSafe-Danger-Zone-Images: true", "value_error")
                    } else {
                        fail(loc + ["box"], "Box questions are not supported by the local Foundation Models backend", "unsupported")
                    }
                case nil:
                    fail(loc + ["type"], "Unable to extract tag using discriminator 'type'", "union_tag_not_found")
                case let other?:
                    fail(loc, "Input tag '\(other)' found using 'type' does not match any of the expected tags: 'noul', 'choice', 'score', 'box'", "union_tag_invalid")
                }
            }
        } else {
            fail(["questions"], "Questions must be an object with at least 1 question", "value_error")
        }
    } else {
        fail(["questions"], "Field required", "missing")
    }

    if !issues.isEmpty { throw ValidationFailure(issues: issues) }
    return SystemOneRequest(model: model!, state: state!, questions: questions)
}
