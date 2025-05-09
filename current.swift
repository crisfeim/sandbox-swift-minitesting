import Foundation


@propertyWrapper
class ThreadLocal<T> {
    private let key: String
    private let defaultValue: T
    
    init(key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }
    
    var wrappedValue: T {
        get {
            if let value = Thread.current.threadDictionary[key] as? T {
                return value
            }
            return defaultValue
        }
        set {
            Thread.current.threadDictionary[key] = newValue
        }
    }
}


enum Globals {
    @ThreadLocal(key: "currentTestName", defaultValue: nil) 
    static var currentTestName: String?
}

@propertyWrapper
struct Test {
    typealias Value = () async throws -> Void
    let id = UUID()
    var wrappedValue: Value
}

protocol Initiable {init()}
protocol StaticSelf: Initiable {}
extension StaticSelf {static var `self`: Self {Self()}}


protocol TestCase: StaticSelf {}

enum TestsSuite {
    fileprivate static var storage = [String: () async -> Void]()
    
    static func run() {
        Task {
            var count = storage.count {
                didSet {
                    if count == 0 {
                        CFRunLoopStop(CFRunLoopGetMain())
                    }
                }
            }
            await storage.asyncForEach { testCaseName, testCase in
                print(testCaseName)
                await testCase()
                print("\n")
                count -= 1
            }
        }
        CFRunLoopRun()
    }
}

extension TestCase {
    
    var caseName: String {String(describing: Self.self)}
    
    func setup() {
        TestsSuite.storage[header] = runTests
    }
    
    
    fileprivate var header: String {
        let title = "Running: \(caseName)"
        let string = Array(2...title.count).reduce("-") { f, _ in f + "-" }
        return title + "\n" + string
    }
    
    func getTests() -> [(label: String, test: () async throws -> Void)] {
        Mirror(reflecting: self).children.compactMap { child in
            if let label = child.label, label.hasPrefix("_"), let test = child.value as? Test {
                return (label: label, test: test.wrappedValue)
            } else {
                return nil
            }
        }
    }
    
    fileprivate func runTests() async {
    
        await getTests().asyncForEach { label, test in
            do {
                Globals.currentTestName = label
                try await test()
                Globals.currentTestName = nil
            } catch {
                fail(error.localizedDescription)
            }
        }
    }
}

extension Sequence {
    func asyncForEach(
        _ operation: (Element) async throws -> Void
    ) async rethrows {
        for element in self {
            try await operation(element)
        }
    }
}

// MARK: - Expectations & Assert
struct AssertExpectation<T: Equatable> {
    let value: T
    
    enum ToBe {
        case equalTo(T)
    }
    
    func toEqual(_ expectedValue: T, line: UInt = #line, functionName: String? = Globals.currentTestName) {
        assertEqual(value, expectedValue, line: line, functionName: functionName)
    }
    
    func toBe(_ toBeCase: ToBe, line: UInt = #line, functionName: String? = Globals.currentTestName, desc: String = "") {
        switch toBeCase {
            case .equalTo(let item): toBe(item, line: line, functionName: functionName, desc: desc)
        }
    }
    
    private func toBe(_ expectedValue: T, line: UInt = #line, functionName: String? = Globals.currentTestName, desc: String) {
        assertEqual(value, expectedValue, line: line, functionName: functionName, desc)
    }
    
    func notToBe(_ expectedValue: T?, line: UInt = #line, functionName: String? = Globals.currentTestName) {
        assert(value != expectedValue, line: line, functionName: functionName)
    }
    
    func toBe(_ expectedValue: T, line: UInt = #line, functionName: String? = Globals.currentTestName) {
        assertEqual(value, expectedValue, line: line, functionName: functionName)
    }
}

@discardableResult
func expect<T>(_ object: T) -> AssertExpectation<T> {
    .init(value: object)
}


func unwrap<T>(_ object: T?) throws -> T {
    guard let object else { throw NSError(domain: "Unable to unwrap value", code: 0) }
    return object
}

struct assert {
    @discardableResult
    init(_ condition: Bool, line: UInt = #line, functionName: String? = Globals.currentTestName, _ description: String = "") {
        let emoji = condition ? "✅" : "❌"
        let functionName = functionName ?? "Unknown test name"
        //let description = condition ? "" : description
        let description = description.isEmpty ? "" : "— \(description)"
        print(line.description + " " + emoji + " " + functionName + " " + description)
    }
}

struct assertEqual {
    @discardableResult
    init<T: Equatable>(_ lhs: T, _ rhs: T, line: UInt = #line, functionName: String? = Globals.currentTestName, _ description: String = "") {
        let description = lhs != rhs ? "\(lhs) != \(rhs)" : description
        assert(lhs == rhs, line: line, functionName: functionName, description)
    }
}

struct assertNotNil {
    @discardableResult
    init<T>(_ object: T?, line: UInt = #line, functionName: String? = Globals.currentTestName, _ description: String = "") {
        assert(object != nil, line: line, functionName: functionName, description)
    }
}

struct fail {
    @discardableResult
    init(_ message: String = "", line: UInt = #line, functionName: String? = Globals.currentTestName, _ description: String = "") {
        print(line.description + " " + "❌" + " " + message)
    }
}

class Expectation {
    private let description: String
    private(set) var isFullfilled: Bool = false
    
    private let semaphore = DispatchSemaphore(value: 0)
    
    enum Error: Swift.Error {
        case timedOut(String)
    }
    
    init(description: String) {self.description = description}
    func fulfill() {
        isFullfilled = true
    }
    
    func wait(timeout: TimeInterval) throws(Error) {
        let startDate = Date()
        while Date().timeIntervalSince(startDate) < timeout {
            if isFullfilled {return}
            Thread.sleep(forTimeInterval: timeout / 10)
        }
        throw Error.timedOut(description)
    }
}

@discardableResult
func expectation(_ description: String) -> Expectation {
    .init(description: description)
}

func wait(for expectations: [Expectation], timeout: TimeInterval) throws(Expectation.Error) {
    let startDate = Date()
    while Date().timeIntervalSince(startDate) < timeout {
        // Return vs break:
        // Returns ends the execution of enclosing wait(for expectation:) and returns to the calling site
        // Breaks while leave the loop and continues execution inside wait(for expectation:) body, thus throwing NSError
        if expectations.allSatisfy({ $0.isFullfilled }) { return }
        // Prevents the while loop to execute fire too fast and consumie execisve resourceses
        Thread.sleep(forTimeInterval: timeout / 10)
    }
    throw Expectation.Error.timedOut("Test timed out")
}


// MARK: - Tests
struct MyTest: TestCase {
    
    @Test var myTest = {}
    
    @Test var test2 = {
        expect(await self.getInt()).toBe(0)
        expect(Globals.currentTestName).toBe("_test2")
        expect(1).toBe(2)
    }
    
    @Test var test3 = {
        expect(Globals.currentTestName).toBe("_test3")
        assert(true) 
        
        let group = DispatchGroup()
        let exp = expectation("wait to global queue to complete")
        DispatchQueue.global(qos: .background).async {
            assert(true)
            exp.fulfill()
        }
        // @todo: this will probably execute the wait function in a different thread...
        try exp.wait(timeout: 1)
    }
    
    func helper() {print("calling helper...")}
    
    func makeSUT() -> SUT {SUT()}
    struct SUT {}
    func getInt() async -> Int {0}
}

struct MyTest_2: TestCase {
    
    @Test var myTest = {}
    
    @Test var test2 = {
        await self.asyncFunction()
        expect(Globals.currentTestName).toBe("_test2")
        expect(1).toBe(2)
    }
    
    @Test var test3 = {
        expect(Globals.currentTestName).toBe("_test3")
        await self.asyncFunction()
        assert(true) 
        
        let group = DispatchGroup()
        let exp = expectation("wait to global queue to complete")
        DispatchQueue.global(qos: .background).async {
            assert(true)
            exp.fulfill()
        }
        // @todo: this will probably execute the wait function in a different thread...
        try exp.wait(timeout: 1)
    }
    
    func helper() {print("calling helper...")}
    
    func makeSUT() -> SUT {SUT()}
    struct SUT {}
    func asyncFunction() async {
        print("Async function called")
    }
}

infix operator ++
func ++ (lhs: String?, rhs: String) -> String {
    guard let lhs else { return rhs }
    return lhs + " " + rhs
}

func ++ (lhs: String, rhs: String?) -> String {
    guard let rhs else { return lhs }
    return lhs + " " + rhs
}

func runTest() {
    MyTest().setup()
    MyTest_2().setup()
    TestsSuite.run()
}

runTest()