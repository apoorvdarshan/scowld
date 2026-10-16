import XCTest

/// End-to-end journeys through the real app on a simulator.
///
/// Every launch passes `--ui-testing`: the Debug simulator build then never
/// reaches the network, the microphone, speech recognition or the camera, never
/// starts a live conversation, and shows no permission prompts. The 3D companion is left out (CI simulators
/// render it in software, far too slowly); its native bridge has unit tests.
/// `--ui-testing-reset` starts from a fresh install (preferences, saved chats
/// and provider keys); persistence checks relaunch without it.
final class ScowldUITests: XCTestCase {
    private static let freshStartArguments = ["--ui-testing-reset", "--ui-testing-onboarded", "--ui-testing-seed-chat"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launchApp(onboarded: Bool = true, seedChat: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if onboarded { app.launchArguments.append("--ui-testing-onboarded") }
        if seedChat { app.launchArguments.append("--ui-testing-seed-chat") }
        app.launch()
        return app
    }

    @MainActor
    private func relaunchPreservingData(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments.removeAll { Self.freshStartArguments.contains($0) }
        app.launch()
    }

    @MainActor
    private func openTab(_ name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Missing tab \(name)")
        tab.tap()
    }

    @MainActor
    private func waitUntil(_ element: XCUIElement, _ format: String, _ args: Any..., timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: format, argumentArray: args)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "\(element) never matched \(predicate)")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Could not scroll to \(element)")
    }

    @MainActor
    private func button(startingWith title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Any element (link, button or text) whose label starts with `title`.
    @MainActor
    private func element(startingWith title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Switches Live Voice to the user's own API key (new installs start with Premium).
    @MainActor
    private func useOwnKey(in app: XCUIApplication) {
        openTab("Settings", in: app)
        let ownKey = app.segmentedControls["settings.ai.mode"].buttons["Own API Key"]
        XCTAssertTrue(ownKey.waitForExistence(timeout: 10), "Missing the connection switch")
        ownKey.tap()
        XCTAssertTrue(app.buttons["settings.ai.provider"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        let placeholder = field.placeholderValue ?? ""
        let length = current == placeholder ? 0 : current.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: length) + text)
    }

    @MainActor
    private func choose(_ option: String, from picker: XCUIElement, in app: XCUIApplication) {
        picker.tap()
        let item = app.buttons[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing menu option \(option)")
        item.tap()
    }

    // MARK: - First run

    @MainActor
    func testFirstLaunchOnboardingRequiresAcceptingThePolicies() throws {
        let app = launchApp(onboarded: false)

        XCTAssertTrue(app.staticTexts["Welcome to Scowld"].waitForExistence(timeout: 20))
        let next = app.buttons["onboarding.continue"]
        let back = app.buttons["onboarding.back"]
        XCTAssertTrue(next.label.hasPrefix("Continue"))
        XCTAssertFalse(back.exists, "The first page has no Back button")
        XCTAssertFalse(app.tabBars.buttons["Chat"].exists, "Onboarding comes before the app")

        next.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        waitUntil(back, "exists == false")

        for _ in 0..<3 { next.tap() }
        waitUntil(next, "label BEGINSWITH %@", "Accept to Continue")
        XCTAssertFalse(next.isEnabled, "Continuing requires accepting the Privacy Policy and Terms")
        XCTAssertTrue(element(startingWith: "Privacy Policy", in: app).exists)
        XCTAssertTrue(element(startingWith: "Terms of Service", in: app).exists)

        let accept = app.buttons["onboarding.acceptLegal"]
        accept.tap()
        waitUntil(next, "label BEGINSWITH %@", "Start Scowld")
        XCTAssertTrue(next.isEnabled)
        accept.tap()
        waitUntil(next, "enabled == false")
        accept.tap()
        waitUntil(next, "enabled == true")
        next.tap()

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 20))
        relaunchPreservingData(app)
        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Welcome to Scowld"].exists, "Onboarding is shown only once")
    }

    // MARK: - Navigation

    @MainActor
    func testTabsOpenTheChatPastChatsSettingsAndAboutScreens() throws {
        let app = launchApp()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        for name in ["Chat", "Chats", "Settings", "About"] {
            XCTAssertTrue(tabs.buttons[name].exists, "Missing tab \(name)")
        }
        XCTAssertTrue(tabs.buttons["Chat"].isSelected)
        XCTAssertTrue(app.navigationBars["Scowld"].exists)

        let screens = [("Chats", "Chats"), ("Settings", "Settings"), ("About", "About"), ("Chat", "Scowld")]
        for (tab, title) in screens {
            tabs.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), "Tab \(tab) did not show \(title)")
            XCTAssertTrue(tabs.buttons[tab].isSelected)
        }
    }

    // MARK: - Companion screen

    @MainActor
    func testCompanionScreenComposerControls() throws {
        let app = launchApp()
        let live = app.buttons["chat.live"]
        XCTAssertTrue(live.waitForExistence(timeout: 20))
        XCTAssertEqual(live.label, "Start live conversation")
        XCTAssertFalse(app.textFields["chat.messageField"].exists, "Conversations are voice only")
        XCTAssertFalse(app.buttons["chat.send"].exists)
        let camera = app.buttons["chat.camera"]
        XCTAssertEqual(camera.label, "Turn on camera vision", "The camera is off until turned on")
        camera.tap()
        waitUntil(camera, "label == %@", "Turn off camera vision")
        camera.tap()
        waitUntil(camera, "label == %@", "Turn on camera vision")

        let handsFree = app.buttons["chat.handsFree"]
        XCTAssertEqual(handsFree.label, "Turn off hands-free mode", "Hands-free is on by default")
        handsFree.tap()
        waitUntil(handsFree, "label == %@", "Turn on hands-free mode")

        relaunchPreservingData(app)
        let restored = app.buttons["chat.handsFree"]
        XCTAssertTrue(restored.waitForExistence(timeout: 20))
        XCTAssertEqual(restored.label, "Turn on hands-free mode", "The hands-free choice is remembered")
    }

    @MainActor
    func testNewUsersAreOfferedPremiumOrTheirOwnKey() throws {
        let app = launchApp()
        // New users start with Scowld Premium; without a plan the chat offers it.
        let hint = app.buttons["chat.status"]
        XCTAssertTrue(hint.waitForExistence(timeout: 20), "Premium is offered before she is tapped")
        XCTAssertEqual(hint.label, "Start Scowld Premium to talk to Bella.")
        app.buttons["chat.live"].tap()
        let paywall = app.staticTexts["premium.title"]
        XCTAssertTrue(paywall.waitForExistence(timeout: 5), "The mic opens the plans")
        XCTAssertTrue(app.buttons["premium.plan.yearly"].exists)
        XCTAssertTrue(app.buttons["premium.plan.weekly"].exists)
        XCTAssertTrue(app.buttons["premium.restore"].exists)
        XCTAssertTrue(app.buttons["Terms"].exists)
        XCTAssertTrue(app.buttons["Privacy"].exists)
        XCTAssertFalse(app.buttons["premium.subscribe"].isEnabled, "No purchase without the store's prices")

        // Choosing your own key goes to Settings, where the key is added.
        let ownKey = app.buttons["premium.ownKey"]
        reveal(ownKey, in: app)
        ownKey.tap()
        let key = app.secureTextFields["settings.ai.apiKey"]
        reveal(key, in: app)
        key.tap()
        key.typeText("ui-test-key\n")
        let save = app.buttons["settings.ai.save"]
        reveal(save, in: app)
        save.tap()
        waitUntil(app.staticTexts["settings.ai.status"], "label == %@", "Saved")

        openTab("Chat", in: app)
        XCTAssertTrue(app.buttons["chat.live"].waitForExistence(timeout: 5))
        waitUntil(hint, "exists == false")
    }

    @MainActor
    func testWithoutAKeyTheChatPointsToSettings() throws {
        let app = launchApp()
        useOwnKey(in: app)
        openTab("Chat", in: app)
        let hint = app.buttons["chat.status"]
        XCTAssertTrue(hint.waitForExistence(timeout: 20), "A missing key is pointed out before she is tapped")
        XCTAssertEqual(hint.label, "Add your Gemini API key in Settings to talk to Bella.")
        hint.tap()
        XCTAssertTrue(app.secureTextFields["settings.ai.apiKey"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPremiumSettingsShowThePlanAndOpenThePlans() throws {
        let app = launchApp()
        openTab("Settings", in: app)
        let status = app.descendants(matching: .any)["settings.premium.status"]
        reveal(status, in: app)
        XCTAssertTrue(status.label.hasPrefix("No plan yet"))
        XCTAssertTrue(app.buttons["settings.premium.voice"].exists)
        XCTAssertEqual(app.buttons["settings.premium.voice"].value as? String, "Leda - Youthful")
        XCTAssertFalse(app.buttons["settings.ai.provider"].exists, "Premium has no provider or key to set")
        XCTAssertFalse(app.secureTextFields["settings.ai.apiKey"].exists)

        let minutes = app.buttons["settings.premium.minutes"]
        reveal(minutes, in: app)
        minutes.tap()
        XCTAssertTrue(app.buttons["premium.pack.20"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["premium.pack.150"].exists)
        app.buttons["Done"].tap()

        let plans = app.buttons["settings.premium.plans"]
        reveal(plans, in: app)
        plans.tap()
        XCTAssertTrue(app.staticTexts["premium.title"].waitForExistence(timeout: 5))
        app.buttons["premium.close"].tap()
        waitUntil(app.staticTexts["premium.title"], "exists == false")
    }

    @MainActor
    func testHomeTipsExplainTheWakePhrase() throws {
        let app = launchApp()
        let tips = app.buttons["chat.tips"]
        XCTAssertTrue(tips.waitForExistence(timeout: 20))
        tips.tap()

        let sheet = app.navigationBars["Home Tips"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Hands-free wake"].exists)
        XCTAssertTrue(app.staticTexts["Say \"Bella\" or \"hey Bella\". If you set a custom name, say that name or \"hey\" plus it."].exists)
        XCTAssertTrue(app.staticTexts["Live voice"].exists)
        sheet.buttons["Done"].tap()
        waitUntil(sheet, "exists == false")
    }

    // MARK: - Settings

    @MainActor
    func testCustomCharacterNameChangesTheWakePhrase() throws {
        let app = launchApp()
        openTab("Settings", in: app)

        let name = app.textFields["settings.character.name"]
        reveal(name, in: app)
        replaceText(in: name, with: "Nova")
        let save = app.buttons["Save Character"]
        reveal(save, in: app)
        waitUntil(save, "enabled == true")
        save.tap()
        waitUntil(save, "enabled == false")

        openTab("Chat", in: app)
        app.buttons["chat.tips"].tap()
        XCTAssertTrue(app.navigationBars["Home Tips"].waitForExistence(timeout: 10))
        let wakeText = "Say \"Nova\" or \"hey Nova\" while hands-free is on. \"Bella\" still works too."
        XCTAssertTrue(app.staticTexts[wakeText].exists)
        app.navigationBars["Home Tips"].buttons["Done"].tap()

        relaunchPreservingData(app)
        openTab("Settings", in: app)
        let restored = app.textFields["settings.character.name"]
        reveal(restored, in: app)
        XCTAssertEqual(restored.value as? String, "Nova")
    }

    @MainActor
    func testLiveProviderModelVoiceAndKeyAreSaved() throws {
        let app = launchApp()
        useOwnKey(in: app)

        let provider = app.buttons["settings.ai.provider"]
        reveal(provider, in: app)
        // Each choice menu is labeled with its title and reports the choice as its value.
        XCTAssertEqual(provider.label, "Provider")
        XCTAssertEqual(provider.value as? String, "Google Gemini Live", "Gemini is the default")
        XCTAssertFalse(app.staticTexts["Speech-to-Text"].exists, "There is no separate speech-to-text step")
        XCTAssertFalse(app.staticTexts["Text-to-Speech"].exists, "There is no separate text-to-speech step")

        choose("OpenAI Realtime", from: provider, in: app)
        waitUntil(provider, "value == %@", "OpenAI Realtime")
        let model = app.buttons["settings.ai.model"]
        waitUntil(model, "value == %@", "gpt-realtime-2.1-mini")
        choose("gpt-realtime-2.1", from: model, in: app)
        waitUntil(model, "value == %@", "gpt-realtime-2.1")
        let voice = app.buttons["settings.ai.voice"]
        waitUntil(voice, "value == %@", "Marin - Natural, warm")
        choose("Coral - Friendly", from: voice, in: app)
        waitUntil(voice, "value == %@", "Coral - Friendly")
        XCTAssertTrue(button(startingWith: "Get your OpenAI API key", in: app).exists)
        let preview = app.buttons["settings.ai.voicePreview"]
        XCTAssertFalse(preview.isEnabled, "A preview needs a key")

        let status = app.staticTexts["settings.ai.status"]
        XCTAssertEqual(status.label, "Add a key before chatting")
        let key = app.secureTextFields["settings.ai.apiKey"]
        XCTAssertEqual(key.placeholderValue, "OpenAI API key")
        key.tap()
        key.typeText("sk-ui-test-key\n") // Return also dismisses the keyboard covering Save.
        waitUntil(preview, "enabled == true")
        let save = app.buttons["settings.ai.save"]
        reveal(save, in: app)
        save.tap()
        waitUntil(status, "label == %@", "Saved")

        relaunchPreservingData(app)
        openTab("Settings", in: app)
        let restoredProvider = app.buttons["settings.ai.provider"]
        reveal(restoredProvider, in: app)
        XCTAssertEqual(restoredProvider.value as? String, "OpenAI Realtime")
        XCTAssertEqual(app.buttons["settings.ai.model"].value as? String, "gpt-realtime-2.1")
        XCTAssertEqual(app.buttons["settings.ai.voice"].value as? String, "Coral - Friendly")
        XCTAssertEqual(app.staticTexts["settings.ai.status"].label, "Key saved in Keychain")
    }

    @MainActor
    func testGrokVoiceExplainsThatItCannotSeeTheCamera() throws {
        let app = launchApp()
        useOwnKey(in: app)
        let provider = app.buttons["settings.ai.provider"]
        reveal(provider, in: app)
        choose("xAI Grok Voice", from: provider, in: app)
        waitUntil(provider, "value == %@", "xAI Grok Voice")
        XCTAssertEqual(app.buttons["settings.ai.model"].value as? String, "grok-voice-latest")
        XCTAssertEqual(app.buttons["settings.ai.voice"].value as? String, "Ara - Warm, friendly")
        XCTAssertTrue(app.staticTexts["Grok Voice can't see the camera. Choose Gemini or OpenAI for vision."].exists)
    }

    @MainActor
    func testCaptionPreferenceIsRemembered() throws {
        let app = launchApp()
        openTab("Settings", in: app)
        let captions = app.switches["settings.captions"]
        XCTAssertTrue(captions.waitForExistence(timeout: 10))
        XCTAssertEqual(captions.value as? String, "0")
        captions.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        waitUntil(captions, "value == %@", "1")

        relaunchPreservingData(app)
        openTab("Settings", in: app)
        let restored = app.switches["settings.captions"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.value as? String, "1")
    }

    // MARK: - Past chats

    @MainActor
    func testCreateRenameSwitchAndDeleteChats() throws {
        let app = launchApp()
        openTab("Chats", in: app)

        XCTAssertTrue(app.staticTexts["Chat 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Active chat"].exists)

        app.buttons["chats.newChat"].tap()
        XCTAssertTrue(app.staticTexts["Chat 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use Chat 1"].waitForExistence(timeout: 5), "A new chat becomes the active one")

        app.staticTexts["Chat 2"].swipeLeft()
        app.buttons["Rename"].tap()
        let alert = app.alerts["Rename Chat"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        replaceText(in: alert.textFields.firstMatch, with: "Road Trip")
        alert.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Road Trip"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Chat 2"].exists)

        app.buttons["Use Chat 1"].tap()
        XCTAssertTrue(app.buttons["Use Road Trip"].waitForExistence(timeout: 5))

        relaunchPreservingData(app)
        openTab("Chats", in: app)
        XCTAssertTrue(app.staticTexts["Road Trip"].waitForExistence(timeout: 10), "Chats are saved on device")
        XCTAssertTrue(app.buttons["Use Road Trip"].exists, "The active chat is remembered")

        app.staticTexts["Road Trip"].swipeLeft()
        app.buttons["Delete"].tap()
        waitUntil(app.staticTexts["Road Trip"], "exists == false")
        XCTAssertTrue(app.staticTexts["Chat 1"].exists)
    }

    @MainActor
    func testSavedChatTranscriptAndSwitchingFromItsDetail() throws {
        let app = launchApp(seedChat: true)
        openTab("Chats", in: app)

        let seeded = app.staticTexts["Weekend Plans"]
        XCTAssertTrue(seeded.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2 messages"].exists)
        XCTAssertTrue(app.buttons["Use Chat 1"].exists, "The seeded chat is active")

        seeded.tap()
        XCTAssertTrue(app.navigationBars["Weekend Plans"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Plan a picnic for Saturday"].exists)
        XCTAssertTrue(app.staticTexts["Pack sandwiches, lemonade, and a blanket."].exists)
        XCTAssertTrue(app.staticTexts["You"].exists)
        XCTAssertTrue(app.staticTexts["Bella"].exists)
        XCTAssertFalse(app.navigationBars["Weekend Plans"].buttons["Use"].exists, "The active chat has no Use button")
        app.navigationBars["Weekend Plans"].buttons.element(boundBy: 0).tap()

        app.staticTexts["Chat 1"].tap()
        XCTAssertTrue(app.staticTexts["No Messages Yet"].waitForExistence(timeout: 10))
        app.navigationBars["Chat 1"].buttons["Use"].tap()
        XCTAssertTrue(app.buttons["Use Weekend Plans"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Chats"].exists, "Use returns to the chat list")
    }

    // MARK: - About

    @MainActor
    func testAboutShowsTheVersionAndSupportLinks() throws {
        let app = launchApp()
        openTab("About", in: app)

        let version = app.staticTexts["about.version"]
        XCTAssertTrue(version.waitForExistence(timeout: 10))
        XCTAssertNotNil(version.label.range(of: #"^v[0-9]+(\.[0-9]+)+$"#, options: .regularExpression), version.label)

        // The About screen is one non-lazy scroll view, so every row is present without scrolling.
        for title in ["Check for Updates", "Rate Scowld", "Share Scowld", "Open Source on GitHub", "Star on GitHub",
                      "Report an Issue", "Request a Feature", "Small Tip", "Giant Tip",
                      "Contact", "Instagram", "Meet the Developer on X",
                      "Privacy Policy", "Terms of Service"] {
            XCTAssertTrue(button(startingWith: title, in: app).exists, "Missing About row \(title)")
        }
        // The tip jar's intro is an info row (static text), not a button.
        XCTAssertTrue(app.staticTexts["Leave a tip"].exists, "Missing the tip jar intro")
        let terms = button(startingWith: "Terms of Service", in: app)
        reveal(terms, in: app)
    }
}
