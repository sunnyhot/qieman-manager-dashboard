import Foundation

@main
struct QiemanCLIMain {
    static func main() async {
        do {
            let command = try QiemanCommandLine(arguments: Array(CommandLine.arguments.dropFirst()))
            let payload = try await command.run()
            if let help = payload["help"] as? String {
                print(help)
            } else {
                let data = try QiemanCommandLine.JSONData(payload)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(2)
        }
    }
}
