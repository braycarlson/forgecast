defmodule Forgecast.Api.Plugs.Redirect do
    @moduledoc """
    Redirects www and fly.dev requests to the canonical URL.
    """

    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
        canonical = canonical_host()

        cond do
            is_nil(canonical) ->
                conn

            conn.host == canonical ->
                conn

            true ->
                qs = non_empty(conn.query_string)

                url =
                    URI.parse("#{conn.scheme}://#{canonical}")
                    |> Map.put(:path, conn.request_path)
                    |> Map.put(:query, qs)
                    |> URI.to_string()

                conn
                |> put_resp_header("location", url)
                |> send_resp(301, "")
                |> halt()
        end
    end

    defp canonical_host do
        case Application.get_env(:forgecast, :server)[:canonical_host] do
            nil -> nil
            host -> host
        end
    end

    defp non_empty(""), do: nil
    defp non_empty(qs), do: qs
end
