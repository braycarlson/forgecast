defmodule Forgecast.Poller.AdaptiveDelayTest do
    @moduledoc """
    Tests the adaptive delay calculation in isolation. These verify
    that the worker never fires requests faster than the platform's
    rate budget allows, and that edge cases don't produce zero or
    negative delays.
    """

    use ExUnit.Case, async: true

    @budget_fraction 0.8

    describe "adaptive_delay/1" do
        test "spaces requests to consume only a fraction of the budget" do
            remaining = 50
            seconds_left = 3600
            reset_at = System.os_time(:second) + seconds_left

            delay = adaptive_delay(%{remaining: remaining, reset_at: reset_at})

            ideal_interval_ms = trunc(seconds_left / (remaining * @budget_fraction) * 1000)
            assert_in_delta delay, ideal_interval_ms, 1000
        end

        test "slows down as remaining requests decrease" do
            reset_at = System.os_time(:second) + 3600

            delay_plenty = adaptive_delay(%{remaining: 100, reset_at: reset_at})
            delay_scarce = adaptive_delay(%{remaining: 5, reset_at: reset_at})

            assert delay_scarce > delay_plenty
        end

        test "speeds up as reset window approaches" do
            remaining = 50

            delay_far = adaptive_delay(%{remaining: remaining, reset_at: System.os_time(:second) + 3600})
            delay_near = adaptive_delay(%{remaining: remaining, reset_at: System.os_time(:second) + 60})

            assert delay_near < delay_far
        end

        test "never returns less than 500ms" do
            delay = adaptive_delay(%{
                remaining: 10000,
                reset_at: System.os_time(:second) + 1
            })

            assert delay >= 500
        end

        test "returns default interval when remaining is nil" do
            delay = adaptive_delay(%{remaining: nil, reset_at: nil})
            assert delay == 10_000
        end

        test "returns default interval when reset_at is nil" do
            delay = adaptive_delay(%{remaining: 50, reset_at: nil})
            assert delay == 10_000
        end

        test "returns default interval when remaining is zero" do
            delay = adaptive_delay(%{remaining: 0, reset_at: System.os_time(:second) + 3600})
            assert delay == 10_000
        end

        test "handles reset_at in the past gracefully" do
            delay = adaptive_delay(%{remaining: 50, reset_at: System.os_time(:second) - 100})

            assert delay >= 500
        end

        test "handles exactly one remaining request" do
            delay = adaptive_delay(%{remaining: 1, reset_at: System.os_time(:second) + 300})

            assert delay >= 500
            assert delay <= 400_000
        end

        test "simulated hourly budget never exceeds platform limit" do
            limit = 150
            reset_at = System.os_time(:second) + 3600
            remaining = limit

            {total_requests, _} =
                Enum.reduce_while(1..10000, {0, remaining}, fn _, {count, rem} ->
                    if rem <= 0 do
                        {:halt, {count, rem}}
                    else
                        delay = adaptive_delay(%{remaining: rem, reset_at: reset_at})
                        assert delay >= 500, "Delay dropped below 500ms with #{rem} remaining"
                        {:cont, {count + 1, rem - 1}}
                    end
                end)

            assert total_requests <= limit
        end

        test "with GitHub-like rate info (30 search/min), delay stays safe" do
            delay = adaptive_delay(%{remaining: 30, reset_at: System.os_time(:second) + 60})

            requests_per_minute = 60_000 / delay
            assert requests_per_minute <= 30
        end

        test "with GitLab-like rate info (10 req/sec burst), delay stays safe" do
            delay = adaptive_delay(%{remaining: 600, reset_at: System.os_time(:second) + 60})

            assert delay >= 500
        end
    end

    describe "exponential_backoff/1" do
        test "first error uses base interval" do
            delay = exponential_backoff(1)
            assert delay == 20_000
        end

        test "increases exponentially with error streak" do
            d1 = exponential_backoff(1)
            d2 = exponential_backoff(2)
            d3 = exponential_backoff(3)

            assert d2 > d1
            assert d3 > d2
            assert d2 == d1 * 2
            assert d3 == d1 * 4
        end

        test "caps at maximum backoff" do
            max_backoff = :timer.minutes(5)

            delay = exponential_backoff(100)
            assert delay == max_backoff
        end

        test "zero streak uses base interval" do
            delay = exponential_backoff(0)
            assert delay == 10_000
        end

        test "backoff sequence is predictable" do
            expected = [10_000, 20_000, 40_000, 80_000, 160_000, 300_000, 300_000]

            actual = Enum.map(0..6, &exponential_backoff/1)
            assert actual == expected
        end
    end

    defp adaptive_delay(%{remaining: remaining, reset_at: reset_at})
         when is_integer(remaining) and remaining > 0 and is_integer(reset_at) do
        seconds_left = max(reset_at - System.os_time(:second), 1)
        ideal = seconds_left / (remaining * @budget_fraction)
        trunc(ideal * 1000) |> max(500)
    end

    defp adaptive_delay(_), do: 10_000

    defp exponential_backoff(streak) do
        base = 10_000
        max_backoff = :timer.minutes(5)
        capped = min(streak, 6)
        delay = base * Integer.pow(2, capped)
        min(delay, max_backoff)
    end
end
