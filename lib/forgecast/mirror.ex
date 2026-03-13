defmodule Forgecast.Mirror do
    @moduledoc """
    Finds cross-platform mirrors for a set of repos by matching
    on canonical owner/repo-name. Returns a map of repo ID to
    a list of mirrors on other platforms.

    Mirrors are precomputed during ingestion and stored as JSONB
    on the repos table so the trending read path never needs to
    join across the full table. The `refresh_for_canonicals/1`
    function updates the mirrors column for all repos matching
    a set of canonical names.
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.Repository

    import Ecto.Query

    @type mirror :: %{String.t() => String.t()}

    @spec canonical(String.t(), String.t()) :: String.t()
    def canonical(owner, name) do
        repo_part =
            name
            |> String.split("/")
            |> List.last()
            |> String.downcase()

        "#{String.downcase(owner)}/#{repo_part}"
    end

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
                |> Enum.map(fn c -> %{"platform" => c.platform, "url" => c.url} end)

            {id, mirrors}
        end)
        |> Map.new()
    end

    @spec refresh_for_canonicals([String.t()]) :: :ok
    def refresh_for_canonicals([]), do: :ok

    def refresh_for_canonicals(canonicals) do
        candidates =
            from(r in Repository,
                where: fragment(
                    "lower(split_part(?, '/', 1)) || '/' || lower(split_part(?, '/', -1))",
                    r.name, r.name
                ) in ^canonicals,
                select: %{id: r.id, platform: r.platform, url: r.url, name: r.name, owner: r.owner}
            )
            |> Repo.all()

        grouped = Enum.group_by(candidates, fn c -> canonical(c.owner, c.name) end)

        updates =
            Enum.flat_map(grouped, fn {_canon, repos} ->
                Enum.map(repos, fn repo ->
                    mirrors =
                        repos
                        |> Enum.reject(fn r -> r.id == repo.id end)
                        |> Enum.filter(fn r -> r.platform != repo.platform end)
                        |> Enum.uniq_by(fn r -> r.platform end)
                        |> Enum.map(fn r -> %{"platform" => r.platform, "url" => r.url} end)

                    {repo.id, mirrors}
                end)
            end)

        batch_update_mirrors(updates)
    end

    defp batch_update_mirrors([]), do: :ok

    defp batch_update_mirrors(updates) do
        {params, placeholders} =
            updates
            |> Enum.with_index()
            |> Enum.reduce({[], []}, fn {{id, mirrors}, idx}, {p_acc, f_acc} ->
                base = idx * 2
                placeholder = "($#{base + 1}::bigint, $#{base + 2}::jsonb)"
                {p_acc ++ [id, Jason.encode!(mirrors)], [placeholder | f_acc]}
            end)

        values_sql = placeholders |> Enum.reverse() |> Enum.join(", ")

        sql = """
        UPDATE repos AS r
        SET mirrors = v.mirrors
        FROM (VALUES #{values_sql}) AS v(id, mirrors)
        WHERE r.id = v.id
        """

        Repo.query!(sql, params)
        :ok
    end
end
