class Peekaboo < Formula
  desc "Peekaboo MCP server for macOS desktop automation"
  homepage "https://github.com/openclaw/Peekaboo"
  url "https://github.com/openclaw/Peekaboo/releases/download/v3.0.0/peekaboo-mcp-macos-universal.tar.gz"
  sha256 "93aab577b150204faed58d031a376a1c9cf77a2280b346a09241912107b4d5ae"
  license "MIT"
  version "3.0.0"

  depends_on macos: :sequoia

  def install
    bin.install "peekaboo-mcp"
  end

  def caveats
    <<~EOS
      Peekaboo MCP requires Screen Recording and Accessibility permissions.

      Sanity check after install:
        peekaboo-mcp mcp serve
    EOS
  end

  test do
    assert_match "USAGE:", shell_output("#{bin}/peekaboo-mcp --help")
    assert_match "mcp", shell_output("#{bin}/peekaboo-mcp mcp --help")
  end
end
