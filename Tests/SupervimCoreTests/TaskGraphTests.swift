import XCTest

/// Locks the approved 15-task schedule into the task-master file.
/// Status vocabulary accepts both the current Zod enum (`blocked`) and the
/// older docs value (`review`); this snapshot itself uses only the overlap.
final class TaskGraphTests: XCTestCase {
    func testTaskMasterFileMatchesApprovedSchedule() throws {
        let url = repoRoot().appendingPathComponent(".taskmaster/tasks/tasks.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("missing .taskmaster/tasks/tasks.json")
            return
        }

        let data = try Data(contentsOf: url)
        let document: TasksDocument
        do {
            document = try JSONDecoder().decode(TasksDocument.self, from: data)
        } catch {
            XCTFail("tasks.json does not match the task-master task shape: \(error)")
            return
        }

        var problems: [String] = []
        var seen: [Int: TasksDocument.TaskItem] = [:]
        var parsedDependencies: [Int: [Int]] = [:]
        for task in document.master.tasks {
            if seen[task.id] != nil {
                problems.append("duplicate id \(task.id)")
            }
            seen[task.id] = task
        }

        let expectedIDs = Set(1...15)
        if Set(seen.keys) != expectedIDs {
            problems.append("ids are \(seen.keys.sorted()), expected 1...15")
        }

        for id in expectedIDs.sorted() {
            guard let task = seen[id] else { continue }
            problems.append(contentsOf: fieldProblems(task))
            parsedDependencies[id] = task.dependencies
            if task.dependencies != approvedDependencies[id] {
                problems.append("task \(id) dependencies \(task.dependencies) != \(approvedDependencies[id] ?? [])")
            }
            if task.status != approvedStatus[id] {
                problems.append("task \(id) status \(task.status) != \(approvedStatus[id] ?? "")")
            }
        }

        problems.append(contentsOf: cycleProblems(parsedDependencies))
        XCTAssertEqual(problems, [])
    }
}

private let approvedDependencies: [Int: [Int]] = [
    1: [],
    2: [1],
    3: [1],
    4: [1],
    5: [3],
    6: [1],
    7: [2, 3, 5],
    8: [1],
    9: [1],
    10: [4, 7, 8, 9],
    11: [7, 8, 9],
    12: [10],
    13: [6, 7],
    14: [13],
    15: [10, 11, 12, 13, 14],
]

private let approvedStatus: [Int: String] = {
    var status: [Int: String] = [:]
    for id in 1...15 {
        status[id] = id == 1 ? "in-progress" : "pending"
    }
    return status
}()

private let statusVocabulary: Set<String> = [
    "pending",
    "in-progress",
    "blocked",
    "done",
    "cancelled",
    "deferred",
    "review",
]

private let priorityVocabulary: Set<String> = ["low", "medium", "high", "critical"]

private struct TasksDocument: Decodable {
    struct Context: Decodable {
        var tasks: [TaskItem]
    }

    struct TaskItem: Decodable {
        var id: Int
        var title: String
        var description: String
        var status: String
        var dependencies: [Int]
        var priority: String
        var details: String
        var testStrategy: String
        var subtasks: [SubtaskItem]
    }

    struct SubtaskItem: Decodable {
        var id: Int
    }

    var master: Context
}

private func fieldProblems(_ task: TasksDocument.TaskItem) -> [String] {
    var problems: [String] = []
    let strings = [
        "title": task.title,
        "description": task.description,
        "details": task.details,
        "testStrategy": task.testStrategy,
    ]
    for (key, value) in strings.sorted(by: { $0.key < $1.key }) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("task \(task.id) \(key) must be a non-empty string")
        }
    }
    if task.title.count > 200 {
        problems.append("task \(task.id) title is longer than 200 characters")
    }
    if !statusVocabulary.contains(task.status) {
        problems.append("task \(task.id) status \(task.status) is outside the task-master vocabulary")
    }
    if !priorityVocabulary.contains(task.priority) {
        problems.append("task \(task.id) priority \(task.priority) is outside the task-master vocabulary")
    }
    if task.dependencies.contains(task.id) {
        problems.append("task \(task.id) depends on itself")
    }
    return problems
}

private func cycleProblems(_ dependencies: [Int: [Int]]) -> [String] {
    var problems: [String] = []
    var visiting: Set<Int> = []
    var visited: Set<Int> = []

    func walk(_ id: Int) {
        if visited.contains(id) || !problems.isEmpty { return }
        if visiting.contains(id) {
            problems.append("dependency cycle reaches task \(id)")
            return
        }
        visiting.insert(id)
        for prerequisite in dependencies[id] ?? [] {
            if dependencies[prerequisite] == nil {
                problems.append("task \(id) depends on missing task \(prerequisite)")
            } else {
                walk(prerequisite)
            }
        }
        visiting.remove(id)
        visited.insert(id)
    }

    for id in dependencies.keys.sorted() {
        walk(id)
    }
    return problems
}
