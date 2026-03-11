defmodule Forgecast.Poller.BudgetTest do
    use ExUnit.Case, async: false

    alias Forgecast.Poller.Budget

    setup do
        start_supervised!({Budget, limits: %{"test" => 3, "other" => 5}, name: Budget})
        :ok
    end

    test "allows requests within the limit" do
        assert :ok = Budget.request("test")
        assert :ok = Budget.request("test")
        assert :ok = Budget.request("test")
    end

    test "rejects requests after the limit is reached" do
        :ok = Budget.request("test")
        :ok = Budget.request("test")
        :ok = Budget.request("test")

        assert {:exhausted, seconds} = Budget.request("test")
        assert seconds > 0
    end

    test "tracks platforms independently" do
        :ok = Budget.request("test")
        :ok = Budget.request("test")
        :ok = Budget.request("test")

        assert {:exhausted, _} = Budget.request("test")
        assert :ok = Budget.request("other")
    end

    test "uses default limit for unknown platforms" do
        assert :ok = Budget.request("unknown")
    end

    test "reports status per platform" do
        :ok = Budget.request("test")
        :ok = Budget.request("test")

        status = Budget.status()

        assert status["test"].used == 2
        assert status["test"].limit == 3
        assert status["test"].remaining == 1

        assert status["other"].used == 0
        assert status["other"].limit == 5
        assert status["other"].remaining == 5
    end
end
