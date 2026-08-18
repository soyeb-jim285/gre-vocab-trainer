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

/// Pronunciation, on-device and free.
///
/// AVSpeechSynthesizer already ships every accent the app offers, so there is no
/// network call and no per-word cost. Where CMUdict gave us an IPA transcription
/// we hand it over, which rescues the rarer words the synthesiser guesses at.
@MainActor
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    func say(_ word: Word, accent: SpeechAccent, rate: Float = 0.42) {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance: AVSpeechUtterance
        if word.ipa.isEmpty {
            utterance = AVSpeechUtterance(string: word.word)
        } else {
            let attributed = NSMutableAttributedString(string: word.word)
            attributed.addAttribute(
                NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute),
                value: word.ipa,
                range: NSRange(location: 0, length: attributed.length)
            )
            utterance = AVSpeechUtterance(attributedString: attributed)
        }

        utterance.voice = AVSpeechSynthesisVoice(language: accent.languageCode)
        utterance.rate = rate
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
