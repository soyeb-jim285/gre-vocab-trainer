import Foundation

/// JSON Schemas for the structured-output calls.
///
/// Two constraints shape all of these, both from OpenRouter's strict mode:
/// every object must set `additionalProperties: false` and list *every*
/// property in `required`; and numeric bounds (`minimum`/`maximum`) are not
/// carried reliably across providers, so ranges are enforced after decoding
/// instead. `enum` is supported, so ratings use it.
enum Schemas {

    static func responseFormat(name: String, schema: [String: Any]) -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": ["name": name, "strict": true, "schema": schema],
        ]
    }

    private static func object(_ properties: [String: Any]) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": properties.keys.sorted(),
            "additionalProperties": false,
        ]
    }

    private static var string: [String: Any] { ["type": "string"] }
    private static var integer: [String: Any] { ["type": "integer"] }
    private static var stringArray: [String: Any] { ["type": "array", "items": string] }

    static var grade: [String: Any] { object([
        "definition_score": integer,
        "definition_feedback": string,
        "sentence_score": integer,
        "sentence_feedback": string,
        "corrected_sentence": string,
        "overall_rating": ["type": "integer", "enum": [1, 2, 3, 4]],
        "missed_nuances": stringArray,
    ]) }

    static var deepDive: [String: Any] { object([
        "etymology": string,
        "mnemonic": string,
        "nuance": string,
        "confusable_with": stringArray,
    ]) }

    static var coach: [String: Any] { object([
        "summary": string,
        "focus_areas": stringArray,
        "encouragement": string,
    ]) }
}
