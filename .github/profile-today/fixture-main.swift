import Foundation

// Writes the perf tests' synthetic PaceForge documents (PerfFixtureBuilder grown to PerfRealCounts) as one JSON file, the
// file `-PaceForgeFixtureFile` reads. Usage: fixgen <PaceForgeRealShapes.json> <out.json>
let arguments = CommandLine.arguments
guard arguments.count == 3 else { FileHandle.standardError.write(Data("usage: fixgen shapes.json out.json\n".utf8)); exit(2) }
let data = try PerfFixtureBuilder.realSize(shapes: URL(fileURLWithPath: arguments[1]))
try data.write(to: URL(fileURLWithPath: arguments[2]))
print("fixture bytes \(data.count)")
