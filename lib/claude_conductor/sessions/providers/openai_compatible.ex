defmodule ClaudeConductor.Sessions.Providers.OpenAICompatible do
  @moduledoc """
  OpenAI-compatible chat completions provider.

  Expects a config map with:
  - `:api_base` (e.g. "https://api.openai.com/v1")
  - `:api_key`
  - `:model`
  - `:provider` (optional label)
  - `:timeout_ms` (optional)
  """

  @behaviour ClaudeConductor.Sessions.Provider

  @default_timeout_ms 60_000

  @impl true
  def complete(prompt, opts) when is_binary(prompt) do
    config = Keyword.fetch!(opts, :config)

    with {:ok, api_base} <- fetch_string(config, :api_base),
         {:ok, api_key} <- fetch_string(config, :api_key),
         {:ok, model} <- fetch_string(config, :model),
         {:ok, _} <- ensure_http_client_started(),
         {:ok, response} <- request_completion(api_base, api_key, model, prompt, config) do
      {:ok, normalize_response(response, config, model)}
    end
  end

  defp request_completion(api_base, api_key, model, prompt, config) do
    url = String.trim_trailing(api_base, "/") <> "/chat/completions"

    body =
      Jason.encode!(%{
        model: model,
        stream: false,
        messages: [
          %{role: "user", content: prompt}
        ]
      })

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"authorization", to_charlist("Bearer " <> api_key)}
    ]

    request = {to_charlist(url), headers, ~c"application/json", body}

    http_opts = [
      timeout: timeout_ms(config),
      connect_timeout: timeout_ms(config)
    ]

    case :httpc.request(:post, request, http_opts, body_format: :binary) do
      {:ok, {{_http, status, _reason_phrase}, _resp_headers, resp_body}}
      when status in 200..299 ->
        Jason.decode(resp_body)

      {:ok, {{_http, status, _reason_phrase}, _resp_headers, resp_body}} ->
        {:error, {:http_status, status, decode_error_body(resp_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_response(response, config, fallback_model) do
    provider = Map.get(config, :provider, "openai_compatible")
    request_id = Map.get(response, "id")
    model = Map.get(response, "model", fallback_model)
    usage = Map.get(response, "usage", %{})

    %{
      content: extract_content(response),
      provider: provider,
      model: model,
      request_id: request_id,
      usage: usage,
      raw: response
    }
  end

  defp extract_content(%{"choices" => [first | _]}) do
    message = Map.get(first, "message", %{})

    case Map.get(message, "content", "") do
      text when is_binary(text) ->
        text

      blocks when is_list(blocks) ->
        blocks
        |> Enum.map(&extract_content_block/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")

      _ ->
        ""
    end
  end

  defp extract_content(_), do: ""

  defp extract_content_block(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_content_block(%{"text" => text}) when is_binary(text), do: text
  defp extract_content_block(_), do: ""

  defp decode_error_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parsed
      {:error, _} -> body
    end
  end

  defp timeout_ms(config) do
    Map.get(config, :timeout_ms, @default_timeout_ms)
  end

  defp fetch_string(config, key) do
    case Map.get(config, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, {:missing_config, key}}
    end
  end

  defp ensure_http_client_started do
    with :ok <- ensure_started(:inets),
         :ok <- ensure_started(:ssl) do
      {:ok, :started}
    end
  end

  defp ensure_started(app) do
    case Application.ensure_all_started(app) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> {:error, {:app_start_failed, app, reason}}
    end
  end
end
