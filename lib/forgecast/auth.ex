defmodule Forgecast.Auth do
    @moduledoc """
    Handles GitHub OAuth flow, session management, and user
    upsert. Provides the core authentication logic consumed
    by the auth router and plug.
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.{User, Session}

    import Ecto.Query

    @github_authorize_url "https://github.com/login/oauth/authorize"
    @github_token_url "https://github.com/login/oauth/access_token"
    @github_user_url "https://api.github.com/user"

    @spec authorize_url(String.t()) :: String.t()
    def authorize_url(state) do
        config = github_config()

        params =
            URI.encode_query(%{
                client_id: config[:client_id],
                redirect_uri: config[:redirect_uri],
                scope: "read:user user:email",
                state: state
            })

        "#{@github_authorize_url}?#{params}"
    end

    @spec exchange_code(String.t()) :: {:ok, map()} | {:error, term()}
    def exchange_code(code) do
        config = github_config()

        body = %{
            client_id: config[:client_id],
            client_secret: config[:client_secret],
            code: code
        }

        case Req.post(@github_token_url,
            json: body,
            headers: [{"accept", "application/json"}]
        ) do
            {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}} ->
                fetch_github_user(token)

            {:ok, %Req.Response{body: body}} ->
                {:error, {:token_exchange_failed, body}}

            {:error, reason} ->
                {:error, reason}
        end
    end

    @spec upsert_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
    def upsert_user(github_user) do
        attrs = %{
            github_id: github_user["id"],
            username: github_user["login"],
            display_name: github_user["name"],
            avatar_url: github_user["avatar_url"],
            email: github_user["email"]
        }

        case Repo.get_by(User, github_id: attrs.github_id) do
            nil ->
                %User{}
                |> User.changeset(attrs)
                |> Repo.insert()

            existing ->
                existing
                |> User.changeset(attrs)
                |> Repo.update()
        end
    end

    @spec create_session(User.t()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
    def create_session(%User{} = user) do
        token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

        %Session{}
        |> Session.changeset(%{
            token: token,
            user_id: user.id,
            expires_at: Session.default_expiry()
        })
        |> Repo.insert()
    end

    @spec validate_session(String.t()) :: {:ok, User.t()} | :invalid
    def validate_session(token) when is_binary(token) do
        now = NaiveDateTime.utc_now()

        case Repo.one(
            from s in Session,
                join: u in assoc(s, :user),
                where: s.token == ^token,
                where: s.expires_at > ^now,
                select: u
        ) do
            nil -> :invalid
            user -> {:ok, user}
        end
    end

    def validate_session(_), do: :invalid

    @spec delete_session(String.t()) :: :ok
    def delete_session(token) when is_binary(token) do
        from(s in Session, where: s.token == ^token)
        |> Repo.delete_all()

        :ok
    end

    @spec cleanup_expired_sessions() :: non_neg_integer()
    def cleanup_expired_sessions do
        now = NaiveDateTime.utc_now()

        {count, _} =
            from(s in Session, where: s.expires_at <= ^now)
            |> Repo.delete_all()

        count
    end

    defp fetch_github_user(access_token) do
        case Req.get(@github_user_url,
            headers: [
                {"authorization", "Bearer #{access_token}"},
                {"accept", "application/vnd.github+json"},
                {"user-agent", "forgecast/0.1"}
            ]
        ) do
            {:ok, %Req.Response{status: 200, body: body}} ->
                {:ok, body}

            {:ok, %Req.Response{status: status, body: body}} ->
                {:error, {:github_user_failed, status, body}}

            {:error, reason} ->
                {:error, reason}
        end
    end

    defp github_config do
        Application.get_env(:forgecast, :github_oauth, [])
    end
end
