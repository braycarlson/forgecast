defmodule Forgecast.Schema.Session do
    @moduledoc """
    A database-backed session token tied to a user.
    """

    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
        id: integer() | nil,
        token: String.t() | nil,
        user_id: integer() | nil,
        user: Forgecast.Schema.User.t() | Ecto.Association.NotLoaded.t(),
        expires_at: NaiveDateTime.t() | nil,
        inserted_at: NaiveDateTime.t() | nil
    }

    @session_ttl_days 30

    schema "sessions" do
        field :token, :string
        field :expires_at, :naive_datetime

        belongs_to :user, Forgecast.Schema.User

        timestamps(updated_at: false)
    end

    def changeset(session, attrs) do
        session
        |> cast(attrs, [:token, :user_id, :expires_at])
        |> validate_required([:token, :user_id, :expires_at])
        |> unique_constraint(:token)
        |> foreign_key_constraint(:user_id)
    end

    @spec default_expiry() :: NaiveDateTime.t()
    def default_expiry do
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(@session_ttl_days * 86_400)
        |> NaiveDateTime.truncate(:second)
    end
end
