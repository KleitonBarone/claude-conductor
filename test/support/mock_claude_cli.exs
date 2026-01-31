# Mock Claude CLI script for testing
# Outputs NDJSON similar to real Claude Code CLI
#
# Usage: elixir test/support/mock_claude_cli.exs [options]
#
# Options via environment variables:
#   MOCK_CLI_DELAY_MS - delay between messages (default: 10)
#   MOCK_CLI_EXIT_CODE - exit code (default: 0)
#   MOCK_CLI_FAIL - if "true", output error and exit 1

delay = String.to_integer(System.get_env("MOCK_CLI_DELAY_MS", "10"))
exit_code = String.to_integer(System.get_env("MOCK_CLI_EXIT_CODE", "0"))
should_fail = System.get_env("MOCK_CLI_FAIL") == "true"

if should_fail do
  IO.puts(:stderr, "Error: Mock CLI failure")
  System.halt(1)
end

# Simulate Claude CLI stream-json output
messages = [
  %{type: "system", session_id: "mock-session-123"},
  %{type: "message_start", message: %{role: "assistant"}},
  %{type: "content_block_start", index: 0, content_block: %{type: "text"}},
  %{type: "content_block_delta", index: 0, delta: %{type: "text_delta", text: "Hello"}},
  %{type: "content_block_delta", index: 0, delta: %{type: "text_delta", text: " from"}},
  %{type: "content_block_delta", index: 0, delta: %{type: "text_delta", text: " mock!"}},
  %{type: "content_block_stop", index: 0},
  %{type: "message_stop"},
  %{type: "assistant", content: [%{type: "text", text: "Hello from mock!"}]}
]

for msg <- messages do
  IO.puts(Jason.encode!(msg))
  Process.sleep(delay)
end

System.halt(exit_code)
