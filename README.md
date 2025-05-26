# swift-mini-testing

Messy exploration of a minimal testing system for Swift scripts (I used to rely heavyly on scripting for lightweight projects with no *Xcode*, so no *xctest*)

Supports:
- Test case definition via `@Test` property wrapper
- Async test support
- Lightweight test discovery using reflection
- Thread-local test context tracking
- Simple expectations and assertions with labeled output
- Manual test suite orchestration

## Usage

```swift
struct MyTest: TestCase {
    @Test var exampleTest = {
		    let result = try await sut.get()
        expect(result).toBe("expected result")
    }
}

MyTest().setup()
TestsSuite.run()
```
