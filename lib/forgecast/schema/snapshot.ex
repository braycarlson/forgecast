defmodule Forgecast.Schema.Snapshot do
    @moduledoc """
    A point-in-time capture of a repository's star, fork, and issue counts.

    Stored in a TimescaleDB hypertable partitioned by inserted_at.
    Compressed after 7 days, dropped after 90 days by TimescaleDB
    retention policies.
    """

    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
        id: integer() | nil,
        stars: integer() | nil,
        forks: integer() | nil,
        open_issues: integer() | nil,
        repo_id: integer() | nil,
        repo: Forgecast.Schema.Repository.t() | Ecto.Association.NotLoaded.t(),
        inserted_at: DateTime.t() | nil
    }

    @primary_key false
    schema "snapshots" do
        field :id, :id, autogenerate: true, primary_key: true
        field :stars, :integer
        field :forks, :integer
        field :open_issues, :integer
        field :inserted_at, :utc_datetime, primary_key: true

        belongs_to :repo, Forgecast.Schema.Repository
    end

    def changeset(snapshot, attrs) do
        snapshot
        |> cast(attrs, [:stars, :forks, :open_issues, :repo_id])
        |> validate_required([:stars, :forks, :open_issues, :repo_id])
        |> foreign_key_constraint(:repo_id)
    end
end
