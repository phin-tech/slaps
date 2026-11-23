import Testing
@testable import SlapsKit

@Test func emptySearchKeepsEverySectionAvailable() {
    #expect(SettingsSection.matching("") == SettingsSection.allCases)
    #expect(SettingsSection.matching("   ", in: [.general, .tabs]) == [.general, .tabs])
}

@Test func searchFindsByNameOrKeywordIgnoringCase() {
    #expect(SettingsSection.matching("TABS") == [.tabs])
    #expect(SettingsSection.matching("youtube") == [.video])
    #expect(SettingsSection.matching("cli") == [.commandLine])
    #expect(SettingsSection.matching("applescript") == [.otherApps])
    #expect(SettingsSection.matching("sharing") == [.alerts])
}

@Test func searchNeedsEveryWord() {
    #expect(SettingsSection.matching("full screen") == [.alerts])
    #expect(SettingsSection.matching("youtube battery").isEmpty)
}

@Test func searchOnlyLooksInSectionsThatAreThere() {
    // Battery is only on Macs with one, and Updates only outside the App Store.
    let available = SettingsSection.allCases.filter { $0 != .battery && $0 != .updates }
    #expect(SettingsSection.matching("low", in: available).isEmpty)
    #expect(SettingsSection.matching("beta", in: available).isEmpty)
    #expect(SettingsSection.matching("beta") == [.updates])
}

@Test func everySectionHasAFindableNameAndSymbol() {
    for section in SettingsSection.allCases {
        #expect(SettingsSection.matching(section.name).contains(section))
        #expect(!section.symbol.isEmpty && !section.summary.isEmpty)
    }
}
