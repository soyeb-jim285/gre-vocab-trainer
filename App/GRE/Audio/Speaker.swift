import AVFoundation
import Foundation
import GRECore

enum SpeechAccent: String, CaseIterable, Identifiable, Sendable {
    case american, british, australian, indian

    var id: String { rawValue }

    var languageCode: String {
        switch self {
        case .american: "en-US"
        case .british: "en-GB"
        case .australian: "en-AU"
        case .indian: "en-IN"
        }
    }

    var label: String {
        switch self {
        case .american: "American"
        case .british: "British"
        case .australian: "Australian"
        case .indian: "Indian"
        }
    }
}

extension AVSpeechSynthesisVoiceQuality {
    /// Higher is better. Premium and enhanced voices are neural and sound close
    /// to a dictionary recording; the default compact voice does not.
    var rank: Int {
        switch self {
        case .premium: 3
        case .enhanced: 2
        default: 1
        }
    }

    var label: String {
        switch self {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Compact"
        }
    }
}

/// Which system voices are installed, and which one to use.
///
/// Voices are always resolved to a concrete identifier rather than looked up by
/// language. `AVSpeechSynthesisVoice(language:)` regressed in iOS 26 -- it
/// ignores the selected voice and hands back the system default -- so
/// language-based lookup would silently flatten the accent picker to one voice.
/// See FB20271264.
enum VoiceCatalog {

    static func voices(for accent: SpeechAccent) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.caseInsensitiveCompare(accent.languageCode) == .orderedSame }
            .sorted {
                $0.quality.rank != $1.quality.rank
                    ? $0.quality.rank > $1.quality.rank
                    : $0.name < $1.name          // stable within a quality tier
            }
    }

    /// Best installed voice for the accent: highest quality, then alphabetical.
    static func best(for accent: SpeechAccent) -> AVSpeechSynthesisVoice? {
        voices(for: accent).first
    }

    static func voice(identifier: String?, accent: SpeechAccent) -> AVSpeechSynthesisVoice? {
        // A pinned voice can vanish when the user deletes it in Settings, so fall
        // back rather than going silent.
        if let identifier, let pinned = AVSpeechSynthesisVoice(identifier: identifier) {
            return pinned
        }
        return best(for: accent)
    }

    /// True when nothing better than the compact voice is installed for this
    /// accent, which is what the Settings screen offers to fix.
    static func onlyCompactAvailable(for accent: SpeechAccent) -> Bool {
        let installed = voices(for: accent)
        return installed.isEmpty || installed.allSatisfy { $0.quality.rank <= 1 }
    }
}

/// Pronunciation, on-device and free.
@MainActor
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    func say(
        _ word: Word, accent: SpeechAccent, voiceIdentifier: String? = nil, rate: Float = 0.42
    ) {
        speak(text: word.word, ipa: word.ipa, accent: accent,
              voiceIdentifier: voiceIdentifier, rate: rate)
    }

    /// Used by the Settings preview so a voice can be auditioned before pinning.
    func sample(_ text: String, voice: AVSpeechSynthesisVoice, rate: Float = 0.42) {
        speak(text: text, ipa: "", accent: .american, explicitVoice: voice, rate: rate)
    }

    private func speak(
        text: String, ipa: String, accent: SpeechAccent,
        voiceIdentifier: String? = nil, explicitVoice: AVSpeechSynthesisVoice? = nil,
        rate: Float
    ) {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance: AVSpeechUtterance
        if ipa.isEmpty {
            utterance = AVSpeechUtterance(string: text)
        } else {
            // CMUdict gave us a transcription, which rescues the rarer words the
            // synthesiser would otherwise guess at.
            let attributed = NSMutableAttributedString(string: text)
            attributed.addAttribute(
                NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute),
                value: ipa,
                range: NSRange(location: 0, length: attributed.length)
            )
            utterance = AVSpeechUtterance(attributedString: attributed)
        }

        utterance.voice = explicitVoice
            ?? VoiceCatalog.voice(identifier: voiceIdentifier, accent: accent)
        utterance.rate = rate
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
