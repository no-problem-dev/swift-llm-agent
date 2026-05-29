import A2UICore
import Testing
@testable import LLMA2UIChat

@Suite("SurfaceAppendHealer")
struct SurfaceAppendHealerTests {

    private let catalog = "https://example.com/catalog.json"

    @Test("createSurface + 同ターン updateComponents は透過")
    func createPlusSameTurnUpdate() {
        let messages: [ServerMessage] = [
            .createSurface(.init(surfaceId: "s1", catalogId: catalog)),
            .updateComponents(.init(surfaceId: "s1", components: [])),
        ]
        let out = SurfaceAppendHealer.heal(messages, lockedIds: [], defaultCatalogId: catalog)
        #expect(out.count == 2)
        if case .createSurface(let cs) = out[0] {
            #expect(cs.surfaceId == "s1")
            #expect(cs.sendDataModel == false)   // 矯正されている
        } else {
            Issue.record("expected createSurface")
        }
        if case .updateComponents(let uc) = out[1] {
            #expect(uc.surfaceId == "s1")
        } else {
            Issue.record("expected updateComponents")
        }
    }

    @Test("過去 surface への updateComponents は createSurface 先行挿入で fork される")
    func updatePastSurfaceForks() {
        let messages: [ServerMessage] = [
            .updateComponents(.init(surfaceId: "past", components: [])),
        ]
        let out = SurfaceAppendHealer.heal(messages, lockedIds: ["past"], defaultCatalogId: catalog)
        #expect(out.count == 2)
        guard case .createSurface(let cs) = out[0] else {
            Issue.record("expected createSurface to be injected")
            return
        }
        #expect(cs.surfaceId == "past-2")
        #expect(cs.catalogId == catalog)
        #expect(cs.sendDataModel == false)
        if case .updateComponents(let uc) = out[1] {
            #expect(uc.surfaceId == "past-2")
        } else {
            Issue.record("expected updateComponents with forked id")
        }
    }

    @Test("既存と衝突する createSurface はリネームされる")
    func createCollisionRenamed() {
        let messages: [ServerMessage] = [
            .createSurface(.init(surfaceId: "s1", catalogId: catalog)),
        ]
        let out = SurfaceAppendHealer.heal(messages, lockedIds: ["s1"], defaultCatalogId: catalog)
        guard case .createSurface(let cs) = out[0] else {
            Issue.record("expected createSurface")
            return
        }
        #expect(cs.surfaceId == "s1-2")
    }

    @Test("sendDataModel=true は false に矯正される")
    func sendDataModelForcedFalse() {
        let messages: [ServerMessage] = [
            .createSurface(.init(surfaceId: "s1", catalogId: catalog, sendDataModel: true)),
        ]
        let out = SurfaceAppendHealer.heal(messages, lockedIds: [], defaultCatalogId: catalog)
        guard case .createSurface(let cs) = out[0] else {
            Issue.record("expected createSurface")
            return
        }
        #expect(cs.sendDataModel == false)
    }

    @Test("過去 surface への updateDataModel は drop")
    func updateDataModelPastDropped() {
        let messages: [ServerMessage] = [
            .updateDataModel(.init(surfaceId: "past", path: "/x", value: .string("v"))),
        ]
        let out = SurfaceAppendHealer.heal(messages, lockedIds: ["past"], defaultCatalogId: catalog)
        #expect(out.isEmpty)
    }

    @Test("同ターン surface への updateDataModel は通る")
    func updateDataModelSameTurnPasses() {
        let messages: [ServerMessage] = [
            .createSurface(.init(surfaceId: "s1", catalogId: catalog)),
            .updateDataModel(.init(surfaceId: "s1", path: "/x", value: .string("v"))),
        ]
        let out = SurfaceAppendHealer.heal(messages, lockedIds: [], defaultCatalogId: catalog)
        #expect(out.count == 2)
        if case .updateDataModel(let udm) = out[1] {
            #expect(udm.surfaceId == "s1")
        } else {
            Issue.record("expected updateDataModel")
        }
    }

    @Test("deleteSurface は常に drop")
    func deleteSurfaceDropped() {
        let messages: [ServerMessage] = [
            .deleteSurface(.init(surfaceId: "past")),
            .deleteSurface(.init(surfaceId: "any")),
        ]
        let out = SurfaceAppendHealer.heal(messages, lockedIds: ["past"], defaultCatalogId: catalog)
        #expect(out.isEmpty)
    }

    @Test("未知 id への updateComponents は drop")
    func unknownIdDropped() {
        let messages: [ServerMessage] = [
            .updateComponents(.init(surfaceId: "ghost", components: [])),
        ]
        let out = SurfaceAppendHealer.heal(messages, lockedIds: [], defaultCatalogId: catalog)
        #expect(out.isEmpty)
    }

    @Test("過去 surface への複数 update は単一 fork に集約される")
    func multipleUpdatesShareFork() {
        let messages: [ServerMessage] = [
            .updateComponents(.init(surfaceId: "past", components: [])),
            .updateDataModel(.init(surfaceId: "past", path: "/x", value: .int(1))),
        ]
        let out = SurfaceAppendHealer.heal(messages, lockedIds: ["past"], defaultCatalogId: catalog)
        // createSurface(past-2) + updateComponents(past-2) + updateDataModel(past-2)
        #expect(out.count == 3)
        if case .updateDataModel(let udm) = out[2] {
            #expect(udm.surfaceId == "past-2")
        } else {
            Issue.record("expected updateDataModel with forked id")
        }
    }
}
