defmodule Forgecast.Repo do
    @moduledoc """
    Ecto repository backed by PostgreSQL.
    """

    use Ecto.Repo,
        otp_app: :forgecast,
        adapter: Ecto.Adapters.Postgres
end
