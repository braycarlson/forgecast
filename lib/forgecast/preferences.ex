defmodule Forgecast.Preferences do
    @moduledoc """
    CRUD operations for user preferences. Each preference is
    a key-value pair stored as JSONB, allowing flexible storage
    of lists, maps, or scalars.
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.Preferences

    import Ecto.Query

    @spec all(integer()) :: %{String.t() => term()}
    def all(user_id) do
        from(p in Preferences, where: p.user_id == ^user_id)
        |> Repo.all()
        |> Enum.map(fn p -> {p.key, p.value} end)
        |> Map.new()
    end

    @spec get(integer(), String.t()) :: term() | nil
    def get(user_id, key) do
        case Repo.get_by(Preferences, user_id: user_id, key: key) do
            nil -> nil
            pref -> pref.value
        end
    end

    @spec put(integer(), String.t(), term()) :: {:ok, Preferences.t()} | {:error, Ecto.Changeset.t()}
    def put(user_id, key, value) do
        case Repo.get_by(Preferences, user_id: user_id, key: key) do
            nil ->
                %Preferences{}
                |> Preferences.changeset(%{user_id: user_id, key: key, value: value})
                |> Repo.insert()

            existing ->
                existing
                |> Preferences.changeset(%{value: value})
                |> Repo.update()
        end
    end

    @spec delete(integer(), String.t()) :: :ok
    def delete(user_id, key) do
        from(p in Preferences,
            where: p.user_id == ^user_id and p.key == ^key
        )
        |> Repo.delete_all()

        :ok
    end
end
