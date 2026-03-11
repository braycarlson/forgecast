defmodule Forgecast.Poller.StrategyTest do
    use ExUnit.Case, async: true

    alias Forgecast.Poller.Strategy

    test "all/0 returns all strategies" do
        strategies = Strategy.all()

        assert :top_starred in strategies
        assert :recently_created in strategies
        assert :recently_pushed in strategies
        assert :rising in strategies
    end

    test "count/0 matches the number of strategies" do
        assert Strategy.count() == length(Strategy.all())
    end

    test "at/1 returns the correct strategy by index" do
        strategies = Strategy.all()

        Enum.each(Enum.with_index(strategies), fn {strategy, index} ->
            assert Strategy.at(index) == strategy
        end)
    end

    test "at/1 wraps around when index exceeds count" do
        count = Strategy.count()
        first = Strategy.at(0)

        assert Strategy.at(count) == first
        assert Strategy.at(count * 3) == first
    end
end
