import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let blocks = parseBlocks(text)
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: String) -> some View {
        if block.hasPrefix("### ") {
            Text(String(block.dropFirst(4)))
                .font(.system(size: 15, weight: .semibold))
        } else if block.hasPrefix("## ") {
            Text(String(block.dropFirst(3)))
                .font(.system(size: 17, weight: .bold))
        } else if block.hasPrefix("# ") {
            Text(String(block.dropFirst(2)))
                .font(.system(size: 20, weight: .bold))
        } else if block.hasPrefix("```") {
            codeBlock(block)
        } else if block.hasPrefix("- ") || block.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("\u{2022}")
                    .font(.system(size: 13))
                Text(String(block.dropFirst(2)))
                    .font(.system(size: 13))
            }
        } else if block.hasPrefix("> ") {
            Text(String(block.dropFirst(2)))
                .font(.system(size: 13))
                .padding(.leading, 12)
                .overlay(
                    Rectangle()
                        .frame(width: 3)
                        .foregroundStyle(.secondary.opacity(0.3)),
                    alignment: .leading
                )
        } else {
            Text(block)
                .font(.system(size: 13))
        }
    }

    private func codeBlock(_ block: String) -> some View {
        let lines = block.components(separatedBy: "\n")
        let codeLines = lines.dropFirst().dropLast().joined(separator: "\n")
        return ScrollView(.horizontal, showsIndicators: false) {
            Text(codeLines)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Parsing

    private func parseBlocks(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [String] = []
        var currentCodeBlock: [String] = []
        var inCodeBlock = false

        for line in lines {
            if line.hasPrefix("```") && !inCodeBlock {
                inCodeBlock = true
                currentCodeBlock.append(line)
            } else if inCodeBlock {
                currentCodeBlock.append(line)
                if line.hasPrefix("```") || line.hasSuffix("```") {
                    blocks.append(currentCodeBlock.joined(separator: "\n"))
                    currentCodeBlock = []
                    inCodeBlock = false
                }
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            } else {
                blocks.append(line)
            }
        }

        if inCodeBlock {
            blocks.append(currentCodeBlock.joined(separator: "\n"))
        }

        return blocks
    }
}
