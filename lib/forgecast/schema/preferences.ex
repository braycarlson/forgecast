defmodule Forgecast.Schema.Preferences do
    @moduledoc """
    A key-value preference stored per user. The value column
    is JSONB, so it can hold lists, maps, or scalars.

    Known keys:
      - "favorite_languages" -> ["rust", "zig", "c"]
      - "saved_filters"      -> [%{"name" => "...", "params" => %{...}}, ...]
      - "default_window"     -> 24
      - "default_sort"       -> "score"
      - "per_page"           -> 24
    """

    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
        id: integer() | nil,
        user_id: integer() | nil,
        user: Forgecast.Schema.User.t() | Ecto.Association.NotLoaded.t(),
        key: String.t() | nil,
        value: term(),
        inserted_at: NaiveDateTime.t() | nil,
        updated_at: NaiveDateTime.t() | nil
    }

    @allowed_keys ~w(favorite_languages saved_filters default_window default_sort per_page)

    schema "preferences" do
        field :key, :string
        field :value, Forgecast.Schema.Jsonb

        belongs_to :user, Forgecast.Schema.User

        timestamps()
    end

    def changeset(preference, attrs) do
        preference
        |> cast(attrs, [:user_id, :key, :value])
        |> validate_required([:user_id, :key, :value])
        |> validate_inclusion(:key, @allowed_keys)
        |> unique_constraint([:user_id, :key])
        |> foreign_key_constraint(:user_id)
    end

    def allowed_keys, do: @allowed_keys
end
