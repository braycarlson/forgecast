defmodule Forgecast.Schema.User do
    @moduledoc """
    A user authenticated via GitHub OAuth.
    """

    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
        id: integer() | nil,
        github_id: integer() | nil,
        username: String.t() | nil,
        display_name: String.t() | nil,
        avatar_url: String.t() | nil,
        email: String.t() | nil,
        sessions: [Forgecast.Schema.Session.t()] | Ecto.Association.NotLoaded.t(),
        preferences: [Forgecast.Schema.Preferences.t()] | Ecto.Association.NotLoaded.t(),
        inserted_at: NaiveDateTime.t() | nil,
        updated_at: NaiveDateTime.t() | nil
    }

    schema "users" do
        field :github_id, :integer
        field :username, :string
        field :display_name, :string
        field :avatar_url, :string
        field :email, :string

        has_many :sessions, Forgecast.Schema.Session
        has_many :preferences, Forgecast.Schema.Preferences

        timestamps()
    end

    def changeset(user, attrs) do
        user
        |> cast(attrs, [:github_id, :username, :display_name, :avatar_url, :email])
        |> validate_required([:github_id, :username])
        |> unique_constraint(:github_id)
        |> unique_constraint(:username)
    end
end
