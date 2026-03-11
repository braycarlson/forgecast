defmodule Forgecast.Schema.Event do
    @moduledoc """
    A single star or fork event captured from a platform's event stream.
    """

    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
        id: integer() | nil,
        platform: String.t() | nil,
        platform_repo_id: String.t() | nil,
        repo_name: String.t() | nil,
        event_type: String.t() | nil,
        occurred_at: NaiveDateTime.t() | nil
    }

    schema "events" do
        field :platform, :string
        field :platform_repo_id, :string
        field :repo_name, :string
        field :event_type, :string
        field :occurred_at, :naive_datetime
    end

    def changeset(event, attrs) do
        event
        |> cast(attrs, [:platform, :platform_repo_id, :repo_name, :event_type, :occurred_at])
        |> validate_required([:platform, :platform_repo_id, :repo_name, :event_type, :occurred_at])
        |> validate_inclusion(:event_type, ["star", "fork"])
    end
end
