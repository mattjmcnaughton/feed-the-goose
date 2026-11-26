import GooseRig
import Testing

struct SceneCanvasTests {
	@Test func sceneMatchesThePrototype() {
		#expect(SceneCanvas.sceneSize.width == 340)
		#expect(SceneCanvas.sceneSize.height == 176)
	}
}
