defmodule ClaudeConductor.Sessions.Provider do
  @moduledoc """
  Behaviour for LLM providers used by session execution.
  """

  @type completion :: %{
          required(:content) => String.t(),
          optional(:provider) => String.t(),
          optional(:model) => String.t(),
          optional(:request_id) => String.t(),
          optional(:usage) => map(),
          optional(:raw) => map()
        }

  @callback complete(String.t(), keyword()) :: {:ok, completion()} | {:error, term()}
end
