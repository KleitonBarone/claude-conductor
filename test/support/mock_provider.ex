defmodule ClaudeConductor.Sessions.MockProvider do
  @behaviour ClaudeConductor.Sessions.Provider

  @impl true
  def complete(prompt, _opts) do
    delay = String.to_integer(System.get_env("MOCK_LLM_DELAY_MS", "10"))
    should_fail = System.get_env("MOCK_LLM_FAIL") == "true"

    Process.sleep(delay)

    if should_fail do
      {:error, :mock_llm_failure}
    else
      {:ok,
       %{
         content: "Hello from mock!",
         provider: "mock",
         model: "mock-model",
         request_id: "mock-request-123",
         usage: %{
           "prompt_tokens" => 3,
           "completion_tokens" => 4,
           "total_tokens" => 7
         },
         raw: %{"echo_prompt" => prompt}
       }}
    end
  end
end
