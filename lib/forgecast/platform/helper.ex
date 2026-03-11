defmodule Forgecast.Platform.Helper do
    @moduledoc """
    Shared utilities for platform integrations.
    """

    @spec rate_limit_info(map()) :: Forgecast.Platform.rate_info()
    def rate_limit_info(resp_headers) do
        remaining =
            get_header_int(resp_headers, "x-ratelimit-remaining") ||
            get_header_int(resp_headers, "ratelimit-remaining")

        reset_at =
            get_header_int(resp_headers, "x-ratelimit-reset") ||
            get_header_int(resp_headers, "ratelimit-reset") ||
            retry_after_to_reset(resp_headers)

        %{remaining: remaining, reset_at: reset_at}
    end

    @spec get_header_int(map(), String.t()) :: integer() | nil
    def get_header_int(headers, key) do
        case Map.get(headers, key) do
            [value | _] -> String.to_integer(value)
            _ -> nil
        end
    end

    @spec extract_message(term()) :: String.t() | term()
    def extract_message(body) when is_map(body), do: body["message"]
    def extract_message(body), do: body

    defp retry_after_to_reset(headers) do
        case get_header_int(headers, "retry-after") do
            nil -> nil
            seconds -> System.os_time(:second) + seconds
        end
    end
end
