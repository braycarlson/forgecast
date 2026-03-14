alias Forgecast.Repo
alias Forgecast.Schema.{Repository, Snapshot}

count =
    case System.argv() do
        [n] -> String.to_integer(n)
        _ -> 10_000_000
    end

defmodule Seed do
    @repo_batch 2_500
    @snapshot_batch 12_000
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
        IO.puts("Seeding #{repo_count} repos with ~#{repo_count * @snapshots_per_repo} snapshots...\n")

        start = System.monotonic_time(:millisecond)

        IO.puts("Truncating existing data...")
        Repo.query!("TRUNCATE snapshots, events, repos RESTART IDENTITY CASCADE", [], timeout: :infinity)

        IO.puts("Dropping indexes...")
        drop_indexes()
        tune_session()

        IO.puts("Seeding repos...")
        repo_ms = timed(fn -> seed_repos(repo_count) end)
        IO.puts("Repos done in #{format_duration(repo_ms)}\n")

        IO.puts("Seeding snapshots...")
        snap_ms = timed(fn -> seed_snapshots(repo_count) end)
        IO.puts("Snapshots done in #{format_duration(snap_ms)}\n")

        IO.puts("Rebuilding indexes (this takes a while)...")
        idx_ms = timed(fn -> rebuild_indexes() end)
        IO.puts("Indexes rebuilt in #{format_duration(idx_ms)}\n")

        IO.puts("Analyzing tables...")
        Repo.query!("ANALYZE repos", [], timeout: :infinity)
        Repo.query!("ANALYZE snapshots", [], timeout: :infinity)

        total = System.monotonic_time(:millisecond) - start
        IO.puts("Done in #{format_duration(total)}")
    end

    defp seed_repos(repo_count) do
        1..repo_count
        |> Stream.chunk_every(@repo_batch)
        |> Stream.with_index(1)
        |> Stream.transform(fn -> nil end, fn {chunk, batch_num}, pending_task ->
            # Wait for the previous insert to finish
            if pending_task, do: Task.await(pending_task, :infinity)

            entries = generate_repo_entries(chunk)

            # Fire off insert in background, move on to generating next batch
            task = Task.async(fn ->
                Repo.insert_all(Repository, entries)
            end)

            done = min(batch_num * @repo_batch, repo_count)

            if rem(batch_num, 100) == 0 or done == repo_count do
                IO.puts("  #{done}/#{repo_count} repos")
            end

            {[batch_num], task}
        end, fn pending_task ->
            if pending_task, do: Task.await(pending_task, :infinity)
        end)
        |> Stream.run()
    end

    defp generate_repo_entries(chunk) do
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        default_check = NaiveDateTime.add(now, 3600)

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
                next_check_at: default_check,
                enriched_at: now,
                inserted_at: now,
                updated_at: now
            }
        end)
    end

    defp seed_snapshots(repo_count) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        ids_per_batch = div(@snapshot_batch, @snapshots_per_repo)
        total = repo_count * @snapshots_per_repo

        1..repo_count
        |> Stream.chunk_every(ids_per_batch)
        |> Stream.with_index(1)
        |> Stream.transform(fn -> nil end, fn {id_chunk, batch_num}, pending_task ->
            if pending_task, do: Task.await(pending_task, :infinity)

            entries = generate_snapshot_entries(id_chunk, now)

            task = Task.async(fn ->
                Repo.insert_all(Snapshot, entries)
            end)

            done = min(batch_num * @snapshot_batch, total)

            if rem(batch_num, 100) == 0 do
                IO.puts("  ~#{done}/#{total} snapshots")
            end

            {[batch_num], task}
        end, fn pending_task ->
            if pending_task, do: Task.await(pending_task, :infinity)
        end)
        |> Stream.run()
    end

    defp generate_snapshot_entries(id_chunk, now) do
        Enum.flat_map(id_chunk, fn repo_id ->
            stars = random_stars()
            forks = div(stars, 4 + :rand.uniform(8))
            issues = :rand.uniform(max(div(stars, 20), 1))

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
    end

    @repo_indexes [
        "repos_platform_platform_id_index",
        "repos_platform_index",
        "repos_language_index",
        "repos_next_check_at_index",
        "repos_last_seen_at_index",
        "repos_active_score_desc",
        "repos_active_platform_score",
        "repos_active_language_score",
        "repos_active_platform_language_score",
        "repos_active_stars_desc",
        "repos_active_star_velocity_desc",
        "repos_active_score_id_desc",
        "repos_active_stars_id_desc",
        "repos_active_star_velocity_id_desc",
        "repos_active_forks_id_desc",
        "repos_active_name_id_asc",
        "repos_active_language_id_asc",
        "repos_canonical_lookup",
        "repos_unenriched",
        "repos_og_image_refresh",
        "repos_score_updated_at",
        "repos_search_trgm",
        "repos_lower_name",
        "repos_lower_language",
    ]

    @snapshot_indexes [
        "snapshots_repo_id",
    ]

    defp drop_indexes do
        for idx <- @repo_indexes ++ @snapshot_indexes do
            Repo.query!("DROP INDEX IF EXISTS #{idx}", [], timeout: :infinity)
        end

        Repo.query!("""
            ALTER TABLE repos DROP CONSTRAINT IF EXISTS repos_platform_platform_id_index
        """, [], timeout: :infinity)
    end

    defp rebuild_indexes do
        IO.puts("  Rebuilding unique constraint...")
        Repo.query!("""
            ALTER TABLE repos ADD CONSTRAINT repos_platform_platform_id_index
            UNIQUE (platform, platform_id)
        """, [], timeout: :infinity)

        repo_ddl = [
            "CREATE INDEX repos_platform_index ON repos (platform)",
            "CREATE INDEX repos_language_index ON repos (language)",
            "CREATE INDEX repos_next_check_at_index ON repos (next_check_at)",
            "CREATE INDEX repos_last_seen_at_index ON repos (last_seen_at)",
            "CREATE INDEX repos_active_score_desc ON repos (score DESC) WHERE active = true",
            "CREATE INDEX repos_active_platform_score ON repos (platform, score DESC) WHERE active = true",
            "CREATE INDEX repos_active_language_score ON repos (language, score DESC) WHERE active = true",
            "CREATE INDEX repos_active_platform_language_score ON repos (platform, language, score DESC) WHERE active = true",
            "CREATE INDEX repos_active_stars_desc ON repos (stars DESC) WHERE active = true",
            "CREATE INDEX repos_active_star_velocity_desc ON repos (star_velocity DESC) WHERE active = true",
            "CREATE INDEX repos_active_score_id_desc ON repos (score DESC, id DESC) WHERE active = true",
            "CREATE INDEX repos_active_stars_id_desc ON repos (stars DESC, id DESC) WHERE active = true",
            "CREATE INDEX repos_active_star_velocity_id_desc ON repos (star_velocity DESC, id DESC) WHERE active = true",
            "CREATE INDEX repos_active_forks_id_desc ON repos (forks DESC, id DESC) WHERE active = true",
            "CREATE INDEX repos_active_name_id_asc ON repos (name ASC, id ASC) WHERE active = true",
            "CREATE INDEX repos_active_language_id_asc ON repos (language ASC, id ASC) WHERE active = true",
            "CREATE INDEX repos_canonical_lookup ON repos ((lower(split_part(name, '/', 1)) || '/' || lower(split_part(name, '/', -1))))",
            "CREATE INDEX repos_unenriched ON repos (enriched_at) WHERE enriched_at IS NULL",
            "CREATE INDEX repos_og_image_refresh ON repos (og_image_cached_at, stars) WHERE og_image_url IS NOT NULL",
            "CREATE INDEX repos_score_updated_at ON repos (score_updated_at ASC NULLS FIRST)",
            "CREATE INDEX repos_lower_name ON repos (lower(name))",
            "CREATE INDEX repos_lower_language ON repos (lower(language))",
        ]

        trgm_ddl = """
            CREATE INDEX repos_search_trgm ON repos USING gin (
                (lower(name) || ' ' ||
                 coalesce(lower(description), '') || ' ' ||
                 coalesce(lower(language), '') || ' ' ||
                 coalesce(lower(immutable_array_to_string(topics, ' ')), ''))
                gin_trgm_ops
            )
        """

        snapshot_ddl = [
            "CREATE INDEX snapshots_repo_id ON snapshots (repo_id, inserted_at DESC)",
        ]

        total = length(repo_ddl) + 1 + length(snapshot_ddl)

        (repo_ddl ++ [trgm_ddl] ++ snapshot_ddl)
        |> Enum.with_index(1)
        |> Enum.each(fn {ddl, i} ->
            IO.puts("  Index #{i}/#{total}...")
            Repo.query!(ddl, [], timeout: :infinity)
        end)
    end

    defp tune_session do
        Repo.query!("SET work_mem = '256MB'")
        Repo.query!("SET maintenance_work_mem = '512MB'")
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

    defp timed(fun) do
        start = System.monotonic_time(:millisecond)
        fun.()
        System.monotonic_time(:millisecond) - start
    end

    defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
    defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
    defp format_duration(ms), do: "#{div(ms, 60_000)}m #{rem(div(ms, 1000), 60)}s"
end

Seed.run(count)
