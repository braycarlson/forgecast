alias Forgecast.Repo
alias Forgecast.Schema.{Repository, Snapshot}

import Ecto.Query

count =
    case System.argv() do
        [n] -> String.to_integer(n)
        _ -> 1_000_000
    end

defmodule Seed do
    @repo_batch 2_000
    @snapshot_batch 4_000
    @snapshots_per_repo 3

    @platform_weights [{0.70, "github"}, {0.90, "gitlab"}, {1.0, "codeberg"}]

    @languages [
        "Python", "Rust", "Go", "Elixir", "TypeScript", "JavaScript",
        "Zig", "C", "C++", "Java", "Ruby", "Swift", "Kotlin", "C#",
        "Lua", "Haskell", "Scala", "Dart", "PHP", "R"
    ]

    @adjectives ~w(fast tiny blazing hyper ultra mega super sharp bright dark slim lean raw bold pure deep swift keen wild free open next flux nova edge core zero apex)
    @nouns ~w(forge cast beam flow wave pulse spark drift shard prism vault crane forge delta agent proxy cache queue stack frame shell guard scope forge kernel render engine bridge router parser tracer linker)
    @topics ~w(ai ml cli api web iot gpu rpc orm dsl sdk oss dev ops sre nlp llm rag etl)

    def run(repo_count) do
        existing = Repo.aggregate(from(r in Repository), :count)
        IO.puts("Existing repos: #{existing}")
        IO.puts("Seeding #{repo_count} repos with ~#{repo_count * @snapshots_per_repo} snapshots...")

        start = System.monotonic_time(:millisecond)
        seed_repos(repo_count)
        repo_ms = System.monotonic_time(:millisecond) - start
        IO.puts("Repos seeded in #{div(repo_ms, 1000)}s")

        snap_start = System.monotonic_time(:millisecond)
        seed_snapshots()
        snap_ms = System.monotonic_time(:millisecond) - snap_start
        IO.puts("Snapshots seeded in #{div(snap_ms, 1000)}s")

        total = System.monotonic_time(:millisecond) - start
        IO.puts("Done in #{div(total, 1000)}s")
    end

    defp seed_repos(repo_count) do
        1..repo_count
        |> Stream.chunk_every(@repo_batch)
        |> Stream.with_index(1)
        |> Enum.each(fn {chunk, batch_num} ->
            now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

            entries =
                Enum.map(chunk, fn i ->
                    platform = pick_platform()
                    owner = random_owner()
                    name = random_name()
                    full_name = "#{owner}/#{name}"
                    stars = random_stars()

                    %{
                        platform: platform,
                        platform_id: "seed_#{platform}_#{i}",
                        name: full_name,
                        owner: owner,
                        description: random_description(),
                        language: Enum.random(@languages),
                        url: platform_url(platform, full_name),
                        topics: random_topics(),
                        avatar_url: "https://avatars.githubusercontent.com/u/#{:rand.uniform(100_000_000)}",
                        og_image_url: og_url(platform, full_name),
                        stars: stars,
                        forks: div(stars, 4 + :rand.uniform(8)),
                        open_issues: :rand.uniform(max(div(stars, 20), 1)),
                        score: 0.0,
                        star_velocity: 0.0,
                        fork_velocity: 0.0,
                        active: true,
                        mirrors: [],
                        last_seen_at: random_recent(now, 7),
                        next_check_at: NaiveDateTime.add(now, :rand.uniform(86_400)),
                        enriched_at: now,
                        inserted_at: now,
                        updated_at: now
                    }
                end)

            Repo.insert_all(Repository, entries,
                on_conflict: :nothing,
                conflict_target: [:platform, :platform_id]
            )

            if rem(batch_num, 20) == 0 do
                done = batch_num * @repo_batch
                IO.puts("  #{done}/#{repo_count} repos inserted")
            end
        end)
    end

    defp seed_snapshots do
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Stream.unfold(0, fn last_id ->
            batch =
                from(r in Repository,
                    where: r.id > ^last_id,
                    select: {r.id, r.stars, r.forks, r.open_issues},
                    order_by: r.id,
                    limit: ^@snapshot_batch
                )
                |> Repo.all()

            case batch do
                [] -> nil
                rows -> {rows, rows |> List.last() |> elem(0)}
            end
        end)
        |> Stream.with_index(1)
        |> Enum.each(fn {batch, batch_num} ->
            entries =
                Enum.flat_map(batch, fn {repo_id, stars, forks, issues} ->
                    Enum.map(1..@snapshots_per_repo, fn j ->
                        hours_ago = (@snapshots_per_repo - j) * 8 + :rand.uniform(4)
                        drift = :rand.uniform(max(div(stars, 100), 1))

                        %{
                            repo_id: repo_id,
                            stars: max(stars - drift * (@snapshots_per_repo - j), 0),
                            forks: forks,
                            open_issues: issues,
                            inserted_at: DateTime.add(now, -hours_ago * 3600)
                        }
                    end)
                end)

            Repo.insert_all(Snapshot, entries)

            if rem(batch_num, 20) == 0 do
                done = batch_num * @snapshot_batch
                IO.puts("  ~#{done} repos with snapshots")
            end
        end)
    end

    defp pick_platform do
        r = :rand.uniform()
        Enum.find_value(@platform_weights, fn {threshold, platform} -> if r <= threshold, do: platform end)
    end

    defp random_owner do
        prefix = Enum.random(@adjectives)
        suffix = Enum.random(@nouns)

        case :rand.uniform(3) do
            1 -> "#{prefix}#{suffix}"
            2 -> "#{prefix}-#{suffix}"
            3 -> "#{prefix}#{:rand.uniform(999)}"
        end
    end

    defp random_name do
        adj = Enum.random(@adjectives)
        noun = Enum.random(@nouns)

        case :rand.uniform(4) do
            1 -> "#{adj}-#{noun}"
            2 -> "#{adj}_#{noun}"
            3 -> "#{noun}-#{adj}"
            4 -> "#{adj}#{noun}"
        end
    end

    defp random_description do
        adj = Enum.random(@adjectives)
        noun = Enum.random(@nouns)
        topic = Enum.random(@topics)
        "A #{adj} #{noun} for #{topic} workloads"
    end

    defp random_topics do
        count = :rand.uniform(4) - 1
        Enum.take_random(@topics, count)
    end

    defp random_stars do
        case :rand.uniform(100) do
            n when n <= 50 -> :rand.uniform(100)
            n when n <= 80 -> 100 + :rand.uniform(1_000)
            n when n <= 95 -> 1_000 + :rand.uniform(10_000)
            _ -> 10_000 + :rand.uniform(200_000)
        end
    end

    defp random_recent(now, max_days) do
        seconds = :rand.uniform(max_days * 86_400)
        NaiveDateTime.add(now, -seconds)
    end

    defp platform_url("github", name), do: "https://github.com/#{name}"
    defp platform_url("gitlab", name), do: "https://gitlab.com/#{name}"
    defp platform_url("codeberg", name), do: "https://codeberg.org/#{name}"

    defp og_url("github", name), do: "https://opengraph.githubassets.com/1/#{name}"
    defp og_url(_, _), do: nil
end

Seed.run(count)
