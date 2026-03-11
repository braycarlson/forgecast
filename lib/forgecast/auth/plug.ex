defmodule Forgecast.Auth.Plug do
    @moduledoc """
    Plug that extracts the session token from the Authorization
    header or the session cookie and assigns the current user.

    Accepts both:
      - Authorization: Bearer <token>
      - Cookie: forgecast_session=<token>
    """

    import Plug.Conn

    @behaviour Plug

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, _opts) do
        token = extract_token(conn)

        case Forgecast.Auth.validate_session(token) do
            {:ok, user} ->
                assign(conn, :current_user, user)

            :invalid ->
                assign(conn, :current_user, nil)
        end
    end

    defp extract_token(conn) do
        case get_req_header(conn, "authorization") do
            ["Bearer " <> token] ->
                token

            _ ->
                conn = fetch_cookies(conn)
                conn.cookies["forgecast_session"]
        end
    end
end
