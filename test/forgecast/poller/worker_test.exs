defmodule Forgecast.Poller.WorkerTest do
    use Forgecast.DataCase, async: false

    import Mox

    alias Forgecast.Poller.{Budget, Worker}
    alias Forgecast.Platform.Result

    setup :set_mox_global

    @moduletag :slow

    setup do
        start_supervised!(Forgecast.Poller.Registry)
        :ok
    end

    defp start_budget(limits \\ %{"test" => 100}) do
        start_supervised!({Budget, limits: limits, name: Budget})
    end

    defp start_worker(opts \\ []) do
        defaults = [
            module: Forgecast.MockPlatform,
            platform: "test",
            languages: ["elixir"]
        ]

        start_supervised!({Worker, Keyword.merge(defaults, opts)})
    end

    defp mock_result(attrs \\ %{}) do
        defaults = %{
            platform: "test",
            platform_id: "#{System.unique_integer([:positive])}",
            name: "owner/repo-#{System.unique_integer([:positive])}",
            owner: "owner",
            description: "A test repo",
            language: "Elixir",
            stars: 42,
            forks: 5,
            open_issues: 3,
            topics: [],
            url: "https://example.com/owner/repo",
            avatar_url: nil,
            og_image_url: nil
        }

        struct!(Result, Map.merge(defaults, attrs))
    end

    test "completes a discovery cycle and ingests repos" do
        start_budget()
        result = mock_result()

        Forgecast.MockPlatform
        |> expect(:search, fn "elixir", _opts ->
            {:ok, [result], %{remaining: 50, reset_at: System.os_time(:second) + 3600}}
        end)

        start_worker()
        Process.sleep(2000)

        status = Worker.status("test")
        assert status.total_discovered >= 1
        assert status.total_ingested >= 1
        assert status.error_streak == 0
    end

    test "handles rate limiting gracefully" do
        start_budget()

        Forgecast.MockPlatform
        |> expect(:search, fn "elixir", _opts ->
            {:rate_limited, %{remaining: 0, reset_at: System.os_time(:second) + 5}}
        end)

        start_worker()
        Process.sleep(2000)

        status = Worker.status("test")
        assert status.error_streak == 0
    end

    test "handles errors with backoff" do
        start_budget()

        Forgecast.MockPlatform
        |> expect(:search, fn "elixir", _opts ->
            {:error, :timeout}
        end)

        start_worker()
        Process.sleep(2000)

        status = Worker.status("test")
        assert status.error_streak >= 1
    end

    test "stops when budget is exhausted" do
        start_budget(%{"test" => 0})

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            {:ok, [], nil}
        end)

        start_worker()
        Process.sleep(2000)

        status = Worker.status("test")
        assert status.total_ingested == 0
    end

    test "completes a monitoring cycle for overdue repos" do
        start_budget()

        repo = insert_repo!(%{
            platform: "test",
            name: "owner/monitored",
            next_check_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)
        })

        insert_snapshot!(repo, %{stars: 100})

        for _ <- 1..110 do
            insert_repo!(%{platform: "test"})
        end

        result = mock_result(%{
            platform: "test",
            platform_id: repo.platform_id,
            name: repo.name,
            owner: repo.owner,
            url: repo.url,
            stars: 105,
            forks: 5,
            open_issues: 3
        })

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            {:ok, [mock_result()], %{remaining: 50, reset_at: System.os_time(:second) + 3600}}
        end)
        |> stub(:fetch, fn _repo ->
            {:ok, result, %{remaining: 50, reset_at: System.os_time(:second) + 3600}}
        end)

        start_worker()
        Process.sleep(3000)

        status = Worker.status("test")
        assert status.total_ingested >= 1
    end

    test "advances through languages and strategies" do
        start_budget()
        call_count = :counters.new(1, [:atomics])

        Forgecast.MockPlatform
        |> stub(:search, fn _language, _opts ->
            :counters.add(call_count, 1, 1)
            {:ok, [], %{remaining: 100, reset_at: System.os_time(:second) + 5}}
        end)

        start_worker(languages: ["elixir", "rust", "go"])
        Process.sleep(5000)

        status = Worker.status("test")
        total_calls = :counters.get(call_count, 1)

        assert total_calls >= 3
        assert status.language_index > 0 or status.strategy_index > 0
    end
end
