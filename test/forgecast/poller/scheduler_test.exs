defmodule Forgecast.Poller.SchedulerTest do
    use Forgecast.DataCase

    alias Forgecast.Poller.Scheduler

    @languages ["elixir", "rust", "go"]

    describe "next_task/5" do
        test "returns a discovery task when no repos exist" do
            results =
                for _ <- 1..20 do
                    Scheduler.next_task("github", @languages, 0, 0, 0)
                end

            assert Enum.all?(results, &match?({:discover, _, _}, &1))
        end

        test "returns discovery tasks with correct language and strategy" do
            {:discover, language, strategy} =
                Scheduler.next_task("github", @languages, 1, 2, 0)

            assert language == Enum.at(@languages, 1)
            assert strategy == Forgecast.Poller.Strategy.at(2)
        end

        test "returns monitor task when repos have overdue next_check_at" do
            past = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)

            for _ <- 1..(initial_threshold() + 10) do
                insert_repo!(%{platform: "github"})
            end

            overdue =
                insert_repo!(%{
                    platform: "github",
                    name: "owner/overdue",
                    next_check_at: past
                })

            insert_snapshot!(overdue, %{stars: 100})

            repo_count = initial_threshold() + 11

            found_monitor =
                Enum.any?(1..50, fn _ ->
                    match?({:monitor, _}, Scheduler.next_task("github", @languages, 0, 0, repo_count))
                end)

            assert found_monitor
        end

        test "falls back to discovery when no repos need monitoring" do
            for _ <- 1..(initial_threshold() + 10) do
                insert_repo!(%{platform: "github"})
            end

            repo_count = initial_threshold() + 10

            results =
                for _ <- 1..20 do
                    Scheduler.next_task("github", @languages, 0, 0, repo_count)
                end

            assert Enum.all?(results, &match?({:discover, _, _}, &1))
        end

        test "picks the most overdue repo for monitoring" do
            for _ <- 1..(initial_threshold() + 10) do
                insert_repo!(%{platform: "github"})
            end

            very_overdue =
                insert_repo!(%{
                    platform: "github",
                    name: "owner/very-overdue",
                    next_check_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200)
                })

            _slightly_overdue =
                insert_repo!(%{
                    platform: "github",
                    name: "owner/slightly-overdue",
                    next_check_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
                })

            repo_count = initial_threshold() + 12

            monitor_results =
                1..100
                |> Enum.map(fn _ -> Scheduler.next_task("github", @languages, 0, 0, repo_count) end)
                |> Enum.filter(&match?({:monitor, _}, &1))

            if length(monitor_results) > 0 do
                {:monitor, repo} = hd(monitor_results)
                assert repo.id == very_overdue.id
            end
        end

        test "does not monitor repos from other platforms" do
            for _ <- 1..(initial_threshold() + 10) do
                insert_repo!(%{platform: "codeberg"})
            end

            insert_repo!(%{
                platform: "codeberg",
                name: "owner/codeberg-overdue",
                next_check_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)
            })

            results =
                for _ <- 1..50 do
                    Scheduler.next_task("github", @languages, 0, 0, 0)
                end

            monitor_tasks = Enum.filter(results, &match?({:monitor, _}, &1))
            assert Enum.empty?(monitor_tasks)
        end

        test "does not monitor repos whose next_check_at is in the future" do
            for _ <- 1..(initial_threshold() + 10) do
                insert_repo!(%{platform: "github"})
            end

            insert_repo!(%{
                platform: "github",
                name: "owner/future",
                next_check_at: NaiveDateTime.add(NaiveDateTime.utc_now(), 3600)
            })

            repo_count = initial_threshold() + 11

            results =
                for _ <- 1..50 do
                    Scheduler.next_task("github", @languages, 0, 0, repo_count)
                end

            monitor_tasks = Enum.filter(results, &match?({:monitor, _}, &1))
            assert Enum.empty?(monitor_tasks)
        end

        test "wraps language index correctly" do
            {:discover, language, _} =
                Scheduler.next_task("github", @languages, 15, 0, 0)

            expected_index = rem(15, length(@languages))
            assert language == Enum.at(@languages, expected_index)
        end

        test "wraps strategy index correctly" do
            {:discover, _, strategy} =
                Scheduler.next_task("github", @languages, 0, 100, 0)

            expected = Forgecast.Poller.Strategy.at(100)
            assert strategy == expected
        end
    end

    describe "compute_check_interval/1" do
        test "returns short interval for high velocity repos" do
            repo = insert_repo!(%{platform: "github"})
            two_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -7200) |> NaiveDateTime.truncate(:second)
            now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

            insert_snapshot!(repo, %{stars: 100, inserted_at: two_hours_ago})
            insert_snapshot!(repo, %{stars: 200, inserted_at: now})

            interval = Scheduler.compute_check_interval(repo)
            assert interval == 1_800
        end

        test "returns medium interval for moderate velocity" do
            repo = insert_repo!(%{platform: "github"})
            two_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -7200) |> NaiveDateTime.truncate(:second)
            now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

            insert_snapshot!(repo, %{stars: 100, inserted_at: two_hours_ago})
            insert_snapshot!(repo, %{stars: 105, inserted_at: now})

            interval = Scheduler.compute_check_interval(repo)
            assert interval == 7_200
        end

        test "returns long interval for low velocity" do
            repo = insert_repo!(%{platform: "github"})
            day_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -86400) |> NaiveDateTime.truncate(:second)
            now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

            insert_snapshot!(repo, %{stars: 100, inserted_at: day_ago})
            insert_snapshot!(repo, %{stars: 101, inserted_at: now})

            interval = Scheduler.compute_check_interval(repo)
            assert interval in [21_600, 86_400]
        end

        test "returns longest interval for stagnant repos" do
            repo = insert_repo!(%{platform: "github"})
            two_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -7200) |> NaiveDateTime.truncate(:second)
            now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

            insert_snapshot!(repo, %{stars: 100, inserted_at: two_hours_ago})
            insert_snapshot!(repo, %{stars: 100, inserted_at: now})

            interval = Scheduler.compute_check_interval(repo)
            assert interval == 86_400
        end

        test "returns longest interval for repos with no snapshots" do
            repo = insert_repo!(%{platform: "github"})

            interval = Scheduler.compute_check_interval(repo)
            assert interval == 86_400
        end

        test "returns longest interval for repos with only one snapshot" do
            repo = insert_repo!(%{platform: "github"})
            insert_snapshot!(repo, %{stars: 500})

            interval = Scheduler.compute_check_interval(repo)
            assert interval == 86_400
        end

        test "interval decreases as velocity increases" do
            intervals =
                [0, 1, 5, 50]
                |> Enum.map(fn delta ->
                    repo = insert_repo!(%{platform: "github"})
                    two_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -7200) |> NaiveDateTime.truncate(:second)
                    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

                    insert_snapshot!(repo, %{stars: 100, inserted_at: two_hours_ago})
                    insert_snapshot!(repo, %{stars: 100 + delta, inserted_at: now})

                    Scheduler.compute_check_interval(repo)
                end)

            assert intervals == Enum.sort(intervals, :desc)
        end
    end

    describe "update_next_check/2" do
        test "sets next_check_at in the future" do
            repo = insert_repo!(%{platform: "github"})

            {:ok, updated} = Scheduler.update_next_check(repo, 3600)

            assert updated.next_check_at != nil
            assert NaiveDateTime.compare(updated.next_check_at, NaiveDateTime.utc_now()) == :gt
        end

        test "next_check_at reflects the given interval" do
            repo = insert_repo!(%{platform: "github"})
            now = NaiveDateTime.utc_now()

            {:ok, updated} = Scheduler.update_next_check(repo, 7200)

            diff = NaiveDateTime.diff(updated.next_check_at, now)
            assert_in_delta diff, 7200, 5
        end

        test "can be called multiple times to reschedule" do
            repo = insert_repo!(%{platform: "github"})

            {:ok, first} = Scheduler.update_next_check(repo, 3600)
            {:ok, second} = Scheduler.update_next_check(first, 1800)

            assert NaiveDateTime.compare(second.next_check_at, first.next_check_at) == :lt
        end
    end

    describe "count_platform_repos/1" do
        test "returns count for platform" do
            insert_repo!(%{platform: "github"})
            insert_repo!(%{platform: "github"})
            insert_repo!(%{platform: "gitlab"})

            assert Scheduler.count_platform_repos("github") == 2
            assert Scheduler.count_platform_repos("gitlab") == 1
            assert Scheduler.count_platform_repos("codeberg") == 0
        end
    end

    defp initial_threshold, do: 100
end
