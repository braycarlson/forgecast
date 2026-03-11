defmodule Forgecast.Poller.SafetyTest do
    @moduledoc """
    Integration tests that verify the polling system cannot exceed
    platform rate limits under any combination of responses. These
    tests simulate worst-case scenarios to ensure the app will not
    get banned or generate unexpected hosting costs.
    """

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

    defp mock_result do
        %Result{
            platform: "test",
            platform_id: "#{System.unique_integer([:positive])}",
            name: "owner/repo-#{System.unique_integer([:positive])}",
            owner: "owner",
            description: "test",
            language: "Elixir",
            stars: 10,
            forks: 1,
            open_issues: 0,
            topics: [],
            url: "https://example.com/owner/repo",
            avatar_url: nil,
            og_image_url: nil
        }
    end

    test "worker cannot exceed budget even when platform returns no rate info" do
        limit = 5
        start_supervised!({Budget, limits: %{"test" => limit}, name: Budget})

        call_count = :counters.new(1, [:atomics])

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            :counters.add(call_count, 1, 1)
            {:ok, [mock_result()], nil}
        end)

        start_supervised!({Worker, module: Forgecast.MockPlatform, platform: "test", languages: ["elixir"]})
        Process.sleep(8000)

        total = :counters.get(call_count, 1)
        assert total <= limit, "Made #{total} requests but budget was #{limit}"
    end

    test "worker cannot exceed budget when platform always succeeds fast" do
        limit = 10
        start_supervised!({Budget, limits: %{"test" => limit}, name: Budget})

        call_count = :counters.new(1, [:atomics])

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            :counters.add(call_count, 1, 1)
            {:ok, [mock_result()], %{remaining: 1000, reset_at: System.os_time(:second) + 1}}
        end)

        start_supervised!({Worker, module: Forgecast.MockPlatform, platform: "test", languages: ["elixir"]})
        Process.sleep(8000)

        total = :counters.get(call_count, 1)
        assert total <= limit, "Made #{total} requests but budget was #{limit}"
    end

    test "worker stops calling after budget is exhausted mid-session" do
        limit = 3
        start_supervised!({Budget, limits: %{"test" => limit}, name: Budget})

        call_count = :counters.new(1, [:atomics])

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            :counters.add(call_count, 1, 1)
            {:ok, [], %{remaining: 100, reset_at: System.os_time(:second) + 5}}
        end)

        start_supervised!({Worker, module: Forgecast.MockPlatform, platform: "test", languages: ["elixir"]})
        Process.sleep(5000)

        total = :counters.get(call_count, 1)
        assert total <= limit
    end

    test "worker recovers after rate limit without flooding" do
        limit = 20
        start_supervised!({Budget, limits: %{"test" => limit}, name: Budget})

        call_count = :counters.new(1, [:atomics])
        call_number = :counters.new(1, [:atomics])

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            n = :counters.add(call_number, 1, 1) || :counters.get(call_number, 1)
            :counters.add(call_count, 1, 1)

            if n <= 2 do
                {:rate_limited, %{remaining: 0, reset_at: System.os_time(:second) + 2}}
            else
                {:ok, [mock_result()], %{remaining: 50, reset_at: System.os_time(:second) + 60}}
            end
        end)

        start_supervised!({Worker, module: Forgecast.MockPlatform, platform: "test", languages: ["elixir"]})
        Process.sleep(6000)

        total = :counters.get(call_count, 1)
        assert total <= limit
        assert total >= 2, "Should have retried after rate limit cleared"
    end

    test "worker does not fire any requests with zero budget" do
        start_supervised!({Budget, limits: %{"test" => 0}, name: Budget})

        call_count = :counters.new(1, [:atomics])

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            :counters.add(call_count, 1, 1)
            {:ok, [], nil}
        end)

        start_supervised!({Worker, module: Forgecast.MockPlatform, platform: "test", languages: ["elixir"]})
        Process.sleep(3000)

        total = :counters.get(call_count, 1)
        assert total == 0, "Made #{total} requests with zero budget"
    end

    test "continuous errors cause increasing delays, not request floods" do
        limit = 50
        start_supervised!({Budget, limits: %{"test" => limit}, name: Budget})

        call_count = :counters.new(1, [:atomics])

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            :counters.add(call_count, 1, 1)
            {:error, :server_error}
        end)

        start_supervised!({Worker, module: Forgecast.MockPlatform, platform: "test", languages: ["elixir"]})
        Process.sleep(8000)

        total = :counters.get(call_count, 1)

        assert total <= 6,
            "Made #{total} error requests in 8s — backoff should limit to ~4-5"
    end

    test "mixed success and error responses stay within budget" do
        limit = 15
        start_supervised!({Budget, limits: %{"test" => limit}, name: Budget})

        call_count = :counters.new(1, [:atomics])

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            :counters.add(call_count, 1, 1)

            case :rand.uniform(3) do
                1 -> {:ok, [mock_result()], %{remaining: 20, reset_at: System.os_time(:second) + 30}}
                2 -> {:rate_limited, %{remaining: 0, reset_at: System.os_time(:second) + 3}}
                3 -> {:error, :timeout}
            end
        end)

        start_supervised!({Worker, module: Forgecast.MockPlatform, platform: "test", languages: ["elixir"]})
        Process.sleep(8000)

        total = :counters.get(call_count, 1)
        assert total <= limit, "Made #{total} requests but budget was #{limit}"
    end

    test "monitoring cycles also consume budget" do
        limit = 5
        start_supervised!({Budget, limits: %{"test" => limit}, name: Budget})

        for _ <- 1..110 do
            insert_repo!(%{platform: "test"})
        end

        repo = insert_repo!(%{
            platform: "test",
            name: "owner/overdue",
            next_check_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200)
        })

        insert_snapshot!(repo, %{stars: 100})

        call_count = :counters.new(1, [:atomics])

        Forgecast.MockPlatform
        |> stub(:search, fn _, _ ->
            :counters.add(call_count, 1, 1)
            {:ok, [mock_result()], %{remaining: 100, reset_at: System.os_time(:second) + 5}}
        end)
        |> stub(:fetch, fn _ ->
            :counters.add(call_count, 1, 1)
            {:ok, mock_result(), %{remaining: 100, reset_at: System.os_time(:second) + 5}}
        end)

        start_supervised!({Worker, module: Forgecast.MockPlatform, platform: "test", languages: ["elixir"]})
        Process.sleep(6000)

        total = :counters.get(call_count, 1)
        assert total <= limit, "Made #{total} total requests (discover + monitor) but budget was #{limit}"
    end

    test "default production budgets are conservative" do
        config = Application.get_env(:forgecast, :poller, [])
        budgets = Keyword.get(config, :budget, %{})

        github_budget = Map.get(budgets, "github", 150)
        gitlab_budget = Map.get(budgets, "gitlab", 200)
        codeberg_budget = Map.get(budgets, "codeberg", 200)

        assert github_budget <= 200,
            "GitHub budget #{github_budget}/hr is too aggressive (search limit is 30/min, core is 5000/hr)"

        assert gitlab_budget <= 300,
            "GitLab budget #{gitlab_budget}/hr is too aggressive"

        assert codeberg_budget <= 300,
            "Codeberg budget #{codeberg_budget}/hr is too aggressive"

        total = github_budget + gitlab_budget + codeberg_budget
        assert total <= 700,
            "Total hourly budget #{total} across all platforms is too high"
    end
end
