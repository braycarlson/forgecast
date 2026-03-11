defmodule Forgecast.Platform do
    @moduledoc """
    Behaviour defining the interface for platform integrations.

    Each platform must implement `search/2` for bulk discovery
    and `fetch/1` for single-repo monitoring updates.
    """

    alias Forgecast.Platform.Result

    @type rate_info :: %{remaining: integer() | nil, reset_at: integer() | nil}

    @callback search(String.t(), keyword()) ::
        {:ok, [Result.t()], rate_info() | nil}
        | {:not_modified, rate_info() | nil}
        | {:rate_limited, rate_info()}
        | {:error, term()}

    @callback fetch(Forgecast.Schema.Repository.t()) ::
        {:ok, Result.t(), rate_info() | nil}
        | {:not_modified, rate_info() | nil}
        | {:rate_limited, rate_info()}
        | {:error, term()}
end
