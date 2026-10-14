import XCTest
@testable import Scowld

@MainActor
final class EmotionEngineTests: XCTestCase {
    func testLeadingTagSetsEmotionAndIsRemovedFromText() {
        let engine = EmotionEngine()
        let (emotion, text) = engine.parseResponse("[happy] That's wonderful to hear!")
        XCTAssertEqual(emotion, .happy)
        XCTAssertEqual(text, "That's wonderful to hear!")
    }

    func testEveryDocumentedEmotionTagIsRecognized() {
        let engine = EmotionEngine()
        for emotion in Emotion.allCases {
            let (parsed, text) = engine.parseResponse("[\(emotion.rawValue)] Reply")
            XCTAssertEqual(parsed, emotion)
            XCTAssertEqual(text, "Reply")
        }
    }

    func testTagsAreCaseInsensitive() {
        let engine = EmotionEngine()
        XCTAssertEqual(engine.parseResponse("[EXCITED] Let's go").emotion, .excited)
        XCTAssertEqual(engine.parseResponse("[Thinking] Hmm").emotion, .thinking)
    }

    func testUnknownTagFallsBackToNeutralButIsStillStripped() {
        let engine = EmotionEngine()
        let (emotion, text) = engine.parseResponse("[sleepy] Good night")
        XCTAssertEqual(emotion, .neutral)
        XCTAssertEqual(text, "Good night")
    }

    func testTextWithoutLeadingTagIsUnchanged() {
        let engine = EmotionEngine()
        let reply = "No tag here [happy] in the middle"
        let (emotion, text) = engine.parseResponse(reply)
        XCTAssertEqual(emotion, .neutral)
        XCTAssertEqual(text, reply)
    }

    func testSetEmotionUpdatesCurrentEmotionOnlyWhenItChanges() {
        let engine = EmotionEngine()
        engine.setEmotion(.sad)
        XCTAssertEqual(engine.currentEmotion, .sad)
        XCTAssertTrue(engine.isTransitioning)

        engine.isTransitioning = false
        engine.setEmotion(.sad)
        XCTAssertFalse(engine.isTransitioning, "Setting the same emotion must not restart the transition")
    }
}

@MainActor
final class CharacterManagerTests: XCTestCase {
    func testProcessAIResponseStripsTagAndUpdatesEmotion() {
        let manager = CharacterManager()
        let text = manager.processAIResponse("[surprised] Wow, really?")
        XCTAssertEqual(text, "Wow, really?")
        XCTAssertEqual(manager.emotion, .surprised)
        XCTAssertEqual(manager.emotionEngine.currentEmotion, .surprised)
    }

    func testGesturesFollowReplyContent() {
        let cases: [(String, String?)] = [
            ("[neutral] Hello there", "wave"),
            ("[neutral] Hmm, let me think", "think"),
            ("[neutral] Sorry about that", "sad"),
            ("[neutral] Yes, of course", "nod"),
            ("[neutral] No, not really", "shake"),
            ("[happy] Great job", "happy"),
            ("[neutral] The weather is mild", nil),
        ]
        for (reply, gesture) in cases {
            let manager = CharacterManager()
            _ = manager.processAIResponse(reply)
            XCTAssertEqual(manager.pendingGesture, gesture, reply)
        }
    }

    func testHappyAndExcitedRepliesBounce() {
        let excited = CharacterManager()
        _ = excited.processAIResponse("[excited] Amazing")
        XCTAssertEqual(excited.bodyBounce, 1)

        let calm = CharacterManager()
        _ = calm.processAIResponse("[neutral] Okay")
        XCTAssertEqual(calm.bodyBounce, 0)
    }

    func testSpeechAmplitudeDrivesSmoothedMouthOpenness() {
        let manager = CharacterManager()
        manager.updateFromSpeechAmplitude(1)
        XCTAssertEqual(manager.mouthOpenness, 0.3, accuracy: 0.0001)
        manager.updateFromSpeechAmplitude(1)
        XCTAssertEqual(manager.mouthOpenness, 0.51, accuracy: 0.0001)
    }
}

@MainActor
final class LipSyncEngineTests: XCTestCase {
    func testAmplitudeIsSmoothedAndClampedToUnitRange() {
        let engine = LipSyncEngine()
        engine.updateFromAmplitude(5)
        XCTAssertLessThanOrEqual(engine.mouthOpenness, 1)
        for _ in 0..<50 { engine.updateFromAmplitude(5) }
        XCTAssertEqual(engine.mouthOpenness, 1, accuracy: 0.0001)

        for _ in 0..<50 { engine.updateFromAmplitude(-3) }
        XCTAssertEqual(engine.mouthOpenness, 0, accuracy: 0.0001)
    }

    func testResetClosesTheMouth() {
        let engine = LipSyncEngine()
        engine.updateFromAmplitude(0.8)
        XCTAssertGreaterThan(engine.mouthOpenness, 0)
        engine.reset()
        XCTAssertEqual(engine.mouthOpenness, 0)
    }
}
