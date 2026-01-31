defmodule ClaudeConductor.Sessions.JsonParser do
  @moduledoc """
  Parses streaming NDJSON (newline-delimited JSON) from Claude CLI.

  Handles buffering of partial lines across chunks and parsing
  complete JSON objects as they arrive.
  """

  require Logger

  @doc """
  Process a chunk of data from the CLI.

  Takes new data and the current buffer, returns parsed events
  and the new buffer containing any incomplete line.

  ## Parameters

  - `data` - New binary data from the Port
  - `buffer` - Previous incomplete line buffer (empty string initially)

  ## Returns

  `{new_buffer, [parsed_events]}`

  ## Example

      iex> JsonParser.process_chunk(~s|{"type":"msg"}\\n{"type"|, "")
      {~s|{"type"|, [%{"type" => "msg"}]}
  """
  def process_chunk(data, buffer) do
    full_data = buffer <> data

    case String.split(full_data, "\n") do
      [] ->
        {"", []}

      [single] ->
        # No newline yet, keep buffering
        {single, []}

      lines ->
        # Last element is incomplete (or empty if data ended with \n)
        {remaining, complete} = List.pop_at(lines, -1)
        events = parse_lines(complete)
        {remaining || "", events}
    end
  end

  @doc """
  Parse a single line of JSON.

  Returns the parsed map or nil on failure.
  """
  def parse_line(line) do
    line
    |> String.trim()
    |> parse_json()
  end

  # ─────────────────────────────────────────────────────────────
  # Private Functions
  # ─────────────────────────────────────────────────────────────

  defp parse_lines(lines) do
    lines
    |> Enum.reject(&empty_line?/1)
    |> Enum.map(&parse_json/1)
    |> Enum.reject(&is_nil/1)
  end

  defp empty_line?(line) do
    String.trim(line) == ""
  end

  defp parse_json(line) do
    case Jason.decode(line) do
      {:ok, json} ->
        json

      {:error, _reason} ->
        # Could be stderr output or other non-JSON content
        Logger.debug("Non-JSON CLI output: #{inspect(String.slice(line, 0, 100))}")
        nil
    end
  end
end
