defmodule Forgecast.Mirror do
    @moduledoc """
    Finds cross-platform mirrors for a set of repos by matching
    on canonical owner/repo-name. Returns a map of repo ID to
    a list of mirrors on other platforms.
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.Repository

    import Ecto.Query

    @type mirror :: %{platform: String.t(), url: String.t()}

    @spec for_repos([map()]) :: %{integer() => [mirror()]}
    def for_repos([]), do: %{}

    def for_repos(items) do
        canonicals =
            items
            |> Enum.map(fn item -> {item.id, canonical(item.owner, item.name)} end)

        canonical_values = Enum.map(canonicals, &elem(&1, 1)) |> Enum.uniq()

        candidates =
            from(r in Repository,
                where: fragment(
                    "lower(split_part(?, '/', 1)) || '/' || lower(split_part(?, '/', -1))",
                    r.name, r.name
                ) in ^canonical_values,
                select: %{
                    id: r.id,
                    platform: r.platform,
                    url: r.url,
                    name: r.name,
                    owner: r.owner
                }
            )
            |> Repo.all()
            |> Enum.group_by(fn c -> canonical(c.owner, c.name) end)

        canonicals
        |> Enum.map(fn {id, canon} ->
            item = Enum.find(items, &(&1.id == id))

            mirrors =
                candidates
                |> Map.get(canon, [])
                |> Enum.reject(fn c -> c.id == id end)
                |> Enum.filter(fn c -> c.platform != item.platform end)
                |> Enum.uniq_by(fn c -> c.platform end)
                |> Enum.map(fn c -> %{platform: c.platform, url: c.url} end)

            {id, mirrors}
        end)
        |> Map.new()
    end

    defp canonical(owner, name) do
        repo_part =
            name
            |> String.split("/")
            |> List.last()
            |> String.downcase()

        "#{String.downcase(owner)}/#{repo_part}"
    end
end
