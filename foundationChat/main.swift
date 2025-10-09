import Foundation
import Darwin
import FoundationModels

let session = LanguageModelSession()

func enableRawMode() -> termios {
    var original = termios()
    tcgetattr(STDIN_FILENO, &original)
    
    var raw = original
    raw.c_iflag &= ~UInt(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
    raw.c_oflag &= ~UInt(OPOST)
    raw.c_cflag |= UInt(CS8)
    raw.c_lflag &= ~UInt(ECHO | ICANON | IEXTEN | ISIG)
    raw.c_cc.16 = 1
    raw.c_cc.17 = 0
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    
    return original
}

func disableRawMode(original: termios) {
    var mutableOriginal = original
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &mutableOriginal)
}

func readByte() -> UInt8? {
    var byte: UInt8 = 0
    let result = read(STDIN_FILENO, &byte, 1)
    return result > 0 ? byte : nil
}

func readEditableLine(prompt: String) -> String? {
    print(prompt, terminator: "")
    fflush(stdout)
    
    let originalTermios = enableRawMode()
    defer { disableRawMode(original: originalTermios) }
    
    var buffer: [Character] = []
    var cursorPos = 0
    
    while true {
        guard let byte = readByte() else { continue }
        
        if byte == 3 {
            print("\r\n", terminator: "")
            fflush(stdout)
            return nil
        } else if byte == 13 {
            print("\r\n", terminator: "")
            fflush(stdout)
            return String(buffer)
        } else if byte == 127 {
            if cursorPos > 0 {
                buffer.remove(at: cursorPos - 1)
                cursorPos -= 1
                redrawLine(prompt: prompt, buffer: buffer, cursorPos: &cursorPos)
            }
        } else if byte == 27 {
            guard let seq1 = readByte(), let seq2 = readByte() else { continue }
            if seq1 == 91 { // '['
                switch seq2 {
                case 68:
                    if cursorPos > 0 {
                        cursorPos -= 1
                        print("\u{1B}[D", terminator: "")
                        fflush(stdout)
                    }
                case 67:
                    if cursorPos < buffer.count {
                        cursorPos += 1
                        print("\u{1B}[C", terminator: "")
                        fflush(stdout)
                    }
                default: break
                }
            }
        } else if byte >= 32 && byte <= 126 {
            let char = Character(UnicodeScalar(byte))
            buffer.insert(char, at: cursorPos)
            cursorPos += 1
            redrawLine(prompt: prompt, buffer: buffer, cursorPos: &cursorPos)
        }
    }
}

func redrawLine(prompt: String, buffer: [Character], cursorPos: inout Int) {
    print("\r", terminator: "")
    print("\u{1B}[K", terminator: "")
    print(prompt + String(buffer), terminator: "")
    
    let offsetFromEnd = buffer.count - cursorPos
    if offsetFromEnd > 0 {
        print("\u{1B}[\(offsetFromEnd)D", terminator: "")
    }
    fflush(stdout)
}

func getFoundationResponse(input: String) async {
    do {
        let response = session.streamResponse(to: input)
        var printedCount = 0
        for try await partialResponse in response {
            let content = partialResponse.content
            let delta = content.dropFirst(printedCount)
            print(delta, terminator: "")
            printedCount = content.count
        }
        print()
    } catch {
        fputs("\n[Error] Failed to stream response: \(error)\n", stderr)
    }
}

while true {
    guard let input = readEditableLine(prompt: "> ") else { break }
    
    if input.lowercased() == "exit" || input.lowercased() == "quit" {
        break
    }
    
    let task = Task {
        await getFoundationResponse(input: input)
    }
    _ = await task.result
}
