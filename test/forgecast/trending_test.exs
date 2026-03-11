defmodule Forgecast.TrendingTest do
    use Forgecast.DataCase

    test "repos with higher velocity rank higher" do
        fast = insert_repo!(%{name: "owner/fast", language: "Elixir"})
        slow = insert_repo!(%{name: "owner/slow", language: "Elixir"})

        two_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -7200) |> NaiveDateTime.truncate(:second)
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        insert_snapshot!(fast, %{stars: 100, inserted_at: two_hours_ago})
        insert_snapshot!(fast, %{stars: 200, inserted_at: now})

        insert_snapshot!(slow, %{stars: 500, inserted_at: two_hours_ago})
        insert_snapshot!(slow, %{stars: 505, inserted_at: now})

        %{items: items} = Forgecast.Trending.score(window: 24)

        names = Enum.map(items, & &1.name)
        fast_idx = Enum.find_index(names, &(&1 == "owner/fast"))
        slow_idx = Enum.find_index(names, &(&1 == "owner/slow"))

        assert fast_idx < slow_idx
    end

    test "filters by platform" do
        insert_repo!(%{platform: "github", name: "owner/gh-repo"})
        |> insert_snapshot!(%{stars: 100})

        insert_repo!(%{platform: "codeberg", name: "owner/cb-repo"})
        |> insert_snapshot!(%{stars: 100})

        %{items: items} = Forgecast.Trending.score(platform: "github")

        platforms = Enum.map(items, & &1.platform) |> Enum.uniq()
        assert platforms == ["github"]
    end

    test "filters by language" do
        insert_repo!(%{language: "Rust", name: "owner/rusty"})
        |> insert_snapshot!(%{stars: 100})

        insert_repo!(%{language: "Go", name: "owner/gopher"})
        |> insert_snapshot!(%{stars: 100})

        %{items: items} = Forgecast.Trending.score(language: "Rust")

        languages = Enum.map(items, & &1.language) |> Enum.uniq()
        assert languages == ["Rust"]
    end

    test "search matches name and description" do
        insert_repo!(%{name: "owner/cool-tool", description: "A cool tool"})
        |> insert_snapshot!(%{stars: 50})

        insert_repo!(%{name: "owner/boring", description: "Nothing special"})
        |> insert_snapshot!(%{stars: 50})

        %{items: items} = Forgecast.Trending.score(search: "cool")
        assert length(items) == 1
        assert hd(items).name == "owner/cool-tool"
    end

    test "pagination returns correct page" do
        for i <- 1..5 do
            insert_repo!(%{name: "owner/repo-#{i}"})
            |> insert_snapshot!(%{stars: 100 - i})
        end

        %{items: page1, total: total, total_pages: pages} =
            Forgecast.Trending.score(per_page: 2, page: 1)

        %{items: page2} = Forgecast.Trending.score(per_page: 2, page: 2)

        assert total == 5
        assert pages == 3
        assert length(page1) == 2
        assert length(page2) == 2

        page1_names = Enum.map(page1, & &1.name)
        page2_names = Enum.map(page2, & &1.name)
        assert MapSet.disjoint?(MapSet.new(page1_names), MapSet.new(page2_names))
    end

    test "excludes stale repos" do
        fresh = insert_repo!(%{
            name: "owner/fresh",
            last_seen_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        })
        insert_snapshot!(fresh, %{stars: 50})

        stale = insert_repo!(%{
            name: "owner/stale",
            last_seen_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -8 * 86400)
        })
        insert_snapshot!(stale, %{stars: 50})

        %{items: items} = Forgecast.Trending.score()

        names = Enum.map(items, & &1.name)
        assert "owner/fresh" in names
        refute "owner/stale" in names
    end
end
