defmodule Forgecast.Schema.Repository do
    @moduledoc """
    A repository tracked from a specific platform.
    """

    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
        id: integer() | nil,
        platform: String.t() | nil,
        platform_id: String.t() | nil,
        name: String.t() | nil,
        owner: String.t() | nil,
        description: String.t() | nil,
        language: String.t() | nil,
        url: String.t() | nil,
        topics: [String.t()],
        avatar_url: String.t() | nil,
        og_image_url: String.t() | nil,
        stars: integer(),
        forks: integer(),
        open_issues: integer(),
        last_seen_at: NaiveDateTime.t() | nil,
        next_check_at: NaiveDateTime.t() | nil,
        enriched_at: NaiveDateTime.t() | nil,
        og_image_cached_at: NaiveDateTime.t() | nil,
        snapshots: [Forgecast.Schema.Snapshot.t()] | Ecto.Association.NotLoaded.t(),
        inserted_at: NaiveDateTime.t() | nil,
        updated_at: NaiveDateTime.t() | nil
    }

    schema "repos" do
        field :platform, :string
        field :platform_id, :string
        field :name, :string
        field :owner, :string
        field :description, :string
        field :language, :string
        field :url, :string
        field :topics, {:array, :string}, default: []
        field :avatar_url, :string
        field :og_image_url, :string
        field :stars, :integer, default: 0
        field :forks, :integer, default: 0
        field :open_issues, :integer, default: 0
        field :last_seen_at, :naive_datetime
        field :next_check_at, :naive_datetime
        field :enriched_at, :naive_datetime
        field :og_image_cached_at, :naive_datetime

        has_many :snapshots, Forgecast.Schema.Snapshot, foreign_key: :repo_id

        timestamps()
    end

    def changeset(repository, attrs) do
        repository
        |> cast(attrs, [
            :platform, :platform_id, :name, :owner, :description, :language,
            :url, :topics, :avatar_url, :og_image_url, :stars, :forks,
            :open_issues, :last_seen_at, :next_check_at, :enriched_at,
            :og_image_cached_at
        ])
        |> validate_required([:platform, :platform_id, :name, :owner, :url])
        |> unique_constraint([:platform, :platform_id])
    end
end
