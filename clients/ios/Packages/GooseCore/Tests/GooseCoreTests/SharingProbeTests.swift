import GooseCore
import Testing

struct SharingProbeTests {
	@Test func readsBothGroupsFromInfoDictionary() throws {
		let probe = try #require(SharingProbe(infoDictionary: [
			"FTGAppGroup": "group.example",
			"FTGKeychainAccessGroup": "TEAM.example",
		]))
		#expect(probe.appGroup == "group.example")
		#expect(probe.keychainAccessGroup == "TEAM.example")
	}

	@Test func needsBothGroups() {
		#expect(SharingProbe(infoDictionary: ["FTGAppGroup": "group.example"]) == nil)
		#expect(SharingProbe(infoDictionary: ["FTGAppGroup": "group.example", "FTGKeychainAccessGroup": ""]) == nil)
		#expect(SharingProbe(infoDictionary: nil) == nil)
	}
}
