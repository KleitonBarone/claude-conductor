defmodule ClaudeConductor.Sessions.JsonParserTest do
  use ExUnit.Case, async: true

  alias ClaudeConductor.Sessions.JsonParser

  describe "process_chunk/2" do
    test "parses complete JSON line" do
      {buffer, events} = JsonParser.process_chunk(~s({"type":"message"}\n), "")

      assert buffer == ""
      assert events == [%{"type" => "message"}]
    end

    test "buffers incomplete line" do
      {buffer, events} = JsonParser.process_chunk(~s({"type":"mess), "")

      assert buffer == ~s({"type":"mess)
      assert events == []
    end

    test "continues from previous buffer" do
      {buffer, events} = JsonParser.process_chunk(~s(age"}\n), ~s({"type":"mess))

      assert buffer == ""
      assert events == [%{"type" => "message"}]
    end

    test "parses multiple lines in one chunk" do
      data = ~s({"type":"a"}\n{"type":"b"}\n{"type":"c"}\n)
      {buffer, events} = JsonParser.process_chunk(data, "")

      assert buffer == ""

      assert events == [
               %{"type" => "a"},
               %{"type" => "b"},
               %{"type" => "c"}
             ]
    end

    test "handles multiple lines with incomplete last line" do
      data = ~s({"type":"a"}\n{"type":"b"}\n{"incomp)
      {buffer, events} = JsonParser.process_chunk(data, "")

      assert buffer == ~s({"incomp)

      assert events == [
               %{"type" => "a"},
               %{"type" => "b"}
             ]
    end

    test "skips empty lines" do
      data = ~s({"type":"a"}\n\n\n{"type":"b"}\n)
      {buffer, events} = JsonParser.process_chunk(data, "")

      assert buffer == ""

      assert events == [
               %{"type" => "a"},
               %{"type" => "b"}
             ]
    end

    test "skips malformed JSON lines" do
      data = ~s({"type":"a"}\nnot json\n{"type":"b"}\n)
      {buffer, events} = JsonParser.process_chunk(data, "")

      assert buffer == ""

      assert events == [
               %{"type" => "a"},
               %{"type" => "b"}
             ]
    end

    test "handles empty input" do
      {buffer, events} = JsonParser.process_chunk("", "")

      assert buffer == ""
      assert events == []
    end

    test "handles input with only newlines" do
      {buffer, events} = JsonParser.process_chunk("\n\n\n", "")

      assert buffer == ""
      assert events == []
    end

    test "parses complex nested JSON" do
      data = ~s({"type":"message","content":[{"type":"text","text":"hello"}]}\n)
      {buffer, events} = JsonParser.process_chunk(data, "")

      assert buffer == ""

      assert events == [
               %{
                 "type" => "message",
                 "content" => [%{"type" => "text", "text" => "hello"}]
               }
             ]
    end
  end

  describe "parse_line/1" do
    test "parses valid JSON" do
      assert JsonParser.parse_line(~s({"key":"value"})) == %{"key" => "value"}
    end

    test "returns nil for invalid JSON" do
      assert JsonParser.parse_line("not json") == nil
    end

    test "trims whitespace" do
      assert JsonParser.parse_line(~s(  {"key":"value"}  )) == %{"key" => "value"}
    end
  end
end
