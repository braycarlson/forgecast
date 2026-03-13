defmodule Forgecast.Schema.Event do
    @moduledoc """
    A single star or fork event captured from a platform's event stream.

    Stored in a TimescaleDB hypertable partitioned by occurred_at.
    The repo_id FK is nullable because skeleton repos may not exist
    yet when events first arrive — the poller backfills it after
    ensure_skeleton_repos runs.
    """

    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
        id: integer() | nil,
        platform: String.t() | nil,
        platform_repo_id: String.t() | nil,
        repo_id: integer() | nil,
        repo_name: String.t() | nil,
        event_type: String.t() | nil,
        occurred_at: DateTime.t() | nil
    }

    @primary_key false
    schema "events" do
        field :id, :id, autogenerate: true, primary_key: true
        field :platform, :string
        field :platform_repo_id, :string
        field :repo_name, :string
        field :event_type, :string
        field :occurred_at, :utc_datetime, primary_key: true

        belongs_to :repo, Forgecast.Schema.Repository
    end

    def changeset(event, attrs) do
        event
        |> cast(attrs, [:platform, :platform_repo_id, :repo_id, :repo_name, :event_type, :occurred_at])
        |> validate_required([:platform, :platform_repo_id, :repo_name, :event_type, :occurred_at])
        |> validate_inclusion(:event_type, ["star", "fork"])
        |> foreign_key_constraint(:repo_id)
    end
end
