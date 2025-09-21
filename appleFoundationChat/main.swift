import FoundationModels

let session = LanguageModelSession()
var userWantsToContinue: Bool = true

while(userWantsToContinue){
    do {
        print("> ", terminator: "")
        if let query = readLine() {
            if (query.lowercased() == "quit" || query.lowercased() == "exit"){
                userWantsToContinue = false
            } else {
                let response = try await session.respond(to: query)
                print(response.content)
            }
        } else {
            print("No input received.")
        }
    } catch {
        print("Generation error: \(error)")
    }
}
