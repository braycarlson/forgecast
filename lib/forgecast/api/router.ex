defmodule Forgecast.Api.Router do
    @moduledoc """
    HTTP API serving trending data, filters, repo snapshots,
    GitHub OAuth authentication, and user preferences.
    """

    use Plug.Router
    use Plug.ErrorHandler
    require Logger

    plug Plug.Logger

    plug Plug.Static,
        at: "/",
        from: {:forgecast, "priv/static"},
        cache_control_for_etags: "public, max-age=31536000, immutable",
        only: ~w(assets favicon.ico favicon.svg favicon-96x96.png apple-touch-icon.png forgecast.svg site.webmanifest web-app-manifest-192x192.png web-app-manifest-512x512.png)

    plug :cors
    plug :match
    plug Plug.Parsers, parsers: [:json], json_decoder: Jason
    plug Forgecast.Auth.Plug
    plug :dispatch

    defp cors(conn, _opts) do
        origins = Application.get_env(:forgecast, :server)[:cors_origins] || ["http://localhost:5173"]
        opts = CORSPlug.init(origin: origins)
        CORSPlug.call(conn, opts)
    end

    @allowed_sort ~w(stars forks star_velocity name language score)

    # -- Public endpoints --

    get "/api/trending" do
        max_per_page = Application.get_env(:forgecast, :trending)[:max_per_page] || 100

        platform = conn.query_params["platform"]
        language = conn.query_params["language"]
        search = conn.query_params["search"]
        cursor = conn.query_params["cursor"]
        page = parse_int(conn.query_params["page"], 1) |> max(1)
        per_page = parse_int(conn.query_params["per_page"], 12) |> clamp(1, max_per_page)
        sort = parse_sort(conn.query_params["sort"])
        dir = parse_dir(conn.query_params["dir"])

        results = Forgecast.score(
            platform: platform,
            language: language,
            search: search,
            cursor: cursor,
            page: page,
            per_page: per_page,
            sort: sort,
            dir: dir
        )

        conn
        |> put_resp_header("cache-control", "public, max-age=30")
        |> send_json(200, results)
    end

    get "/api/filters" do
        filters = Forgecast.available_filters()

        conn
        |> put_resp_header("cache-control", "public, max-age=60")
        |> send_json(200, filters)
    end

    get "/api/og-image/:repo_id" do
        case Forgecast.Image.Cache.get_cached_image(parse_int(repo_id, 0)) do
            {:ok, path} ->
                conn
                |> put_resp_content_type("image/png")
                |> put_resp_header("cache-control", "public, max-age=604800, stale-while-revalidate=86400")
                |> send_file(200, path)

            :not_found ->
                send_resp(conn, 404, "")
        end
    end

    get "/api/repos" do
        platform = conn.query_params["platform"]
        language = conn.query_params["language"]

        repos = Forgecast.list_repos(platform: platform, language: language)
        send_json(conn, 200, repos)
    end

    get "/api/repos/:id/snapshots" do
        limit = parse_int(conn.query_params["limit"], 1000) |> clamp(1, 5000)
        snapshots = Forgecast.snapshots_for(id, limit: limit)
        send_json(conn, 200, snapshots)
    end

    get "/api/status" do
        status = Forgecast.status()
        send_json(conn, 200, status)
    end

    # -- Auth endpoints --

    get "/api/auth/github" do
        state = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
        url = Forgecast.Auth.authorize_url(state)

        conn
        |> put_resp_cookie("oauth_state", state,
            http_only: true,
            same_site: "Lax",
            max_age: 600,
            secure: secure_cookies?()
        )
        |> put_resp_header("location", url)
        |> send_resp(302, "")
    end

    get "/api/auth/github/callback" do
        conn = fetch_cookies(conn)
        code = conn.query_params["code"]
        state = conn.query_params["state"]
        cookie_state = conn.cookies["oauth_state"]

        cond do
            is_nil(code) ->
                send_json(conn, 400, %{error: "missing code"})

            is_nil(state) or state != cookie_state ->
                send_json(conn, 400, %{error: "invalid state"})

            true ->
                handle_oauth_callback(conn, code)
        end
    end

    get "/api/auth/me" do
        case conn.assigns[:current_user] do
            nil ->
                send_json(conn, 200, %{user: nil})

            user ->
                send_json(conn, 200, %{
                    user: %{
                        id: user.id,
                        username: user.username,
                        display_name: user.display_name,
                        avatar_url: user.avatar_url
                    }
                })
        end
    end

    post "/api/auth/logout" do
        conn = fetch_cookies(conn)

        case conn.cookies["forgecast_session"] do
            nil -> :ok
            token -> Forgecast.Auth.delete_session(token)
        end

        conn
        |> delete_resp_cookie("forgecast_session")
        |> delete_resp_cookie("oauth_state")
        |> send_json(200, %{ok: true})
    end

    # -- Preference endpoints (authenticated) --

    get "/api/preferences" do
        case require_user(conn) do
            {:ok, user} ->
                prefs = Forgecast.Preferences.all(user.id)
                send_json(conn, 200, prefs)

            :unauthorized ->
                send_json(conn, 401, %{error: "unauthorized"})
        end
    end

    get "/api/preferences/:key" do
        case require_user(conn) do
            {:ok, user} ->
                case Forgecast.Preferences.get(user.id, key) do
                    nil -> send_json(conn, 200, %{key: key, value: nil})
                    value -> send_json(conn, 200, %{key: key, value: value})
                end

            :unauthorized ->
                send_json(conn, 401, %{error: "unauthorized"})
        end
    end

    put "/api/preferences/:key" do
        case require_user(conn) do
            {:ok, user} ->
                value = conn.body_params["value"]

                if is_nil(value) do
                    send_json(conn, 400, %{error: "missing value"})
                else
                    case Forgecast.Preferences.put(user.id, key, value) do
                        {:ok, pref} ->
                            send_json(conn, 200, %{key: pref.key, value: pref.value})

                        {:error, changeset} ->
                            errors = format_errors(changeset)
                            send_json(conn, 422, %{errors: errors})
                    end
                end

            :unauthorized ->
                send_json(conn, 401, %{error: "unauthorized"})
        end
    end

    delete "/api/preferences/:key" do
        case require_user(conn) do
            {:ok, user} ->
                Forgecast.Preferences.delete(user.id, key)
                send_json(conn, 200, %{ok: true})

            :unauthorized ->
                send_json(conn, 401, %{error: "unauthorized"})
        end
    end

    # -- Catch-all --

    match _ do
        if String.starts_with?(conn.request_path, "/api/") do
            send_json(conn, 404, %{error: "not found"})
        else
            index_path =
                :forgecast
                |> Application.app_dir("priv/static/index.html")

            case File.read(index_path) do
                {:ok, html} ->
                    conn
                    |> put_resp_content_type("text/html")
                    |> send_resp(200, html)

                {:error, _} ->
                    send_json(conn, 404, %{error: "not found"})
            end
        end
    end

    @impl Plug.ErrorHandler
    def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
        Logger.error("Unhandled #{kind}: #{inspect(reason)}\n#{Exception.format_stacktrace(stack)}")
        send_json(conn, 500, %{error: "internal server error"})
    end

    # -- Helpers --

    defp handle_oauth_callback(conn, code) do
        frontend_url = frontend_url()

        with {:ok, github_user} <- Forgecast.Auth.exchange_code(code),
             {:ok, user} <- Forgecast.Auth.upsert_user(github_user),
             {:ok, session} <- Forgecast.Auth.create_session(user) do
            conn
            |> delete_resp_cookie("oauth_state")
            |> put_resp_cookie("forgecast_session", session.token,
                http_only: true,
                same_site: "Lax",
                max_age: 30 * 86_400,
                secure: secure_cookies?(),
                path: "/"
            )
            |> put_resp_header("location", frontend_url)
            |> send_resp(302, "")
        else
            {:error, reason} ->
                Logger.error("[Api.Router] OAuth callback failed: #{inspect(reason)}")

                conn
                |> delete_resp_cookie("oauth_state")
                |> put_resp_header("location", "#{frontend_url}?auth_error=true")
                |> send_resp(302, "")
        end
    end

    defp require_user(conn) do
        case conn.assigns[:current_user] do
            %Forgecast.Schema.User{} = user -> {:ok, user}
            _ -> :unauthorized
        end
    end

    defp format_errors(changeset) do
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
                opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
        end)
    end

    defp send_json(conn, status, data) do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, Jason.encode!(data))
    end

    defp parse_int(nil, default), do: default
    defp parse_int(val, default) do
        case Integer.parse(val) do
            {n, _} -> n
            :error -> default
        end
    end

    defp parse_sort(val) when val in @allowed_sort, do: String.to_existing_atom(val)
    defp parse_sort(_), do: nil

    defp parse_dir("asc"), do: :asc
    defp parse_dir("desc"), do: :desc
    defp parse_dir(_), do: nil

    defp clamp(val, lo, hi), do: val |> max(lo) |> min(hi)

    defp secure_cookies? do
        Application.get_env(:forgecast, :server)[:secure_cookies] || false
    end

    defp frontend_url do
        origins = Application.get_env(:forgecast, :server)[:cors_origins] || ["http://localhost:5173"]
        List.first(origins)
    end
end
