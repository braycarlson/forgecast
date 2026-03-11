defmodule Forgecast.Poller.Strategy do
    @moduledoc """
    Defines discovery query strategies that surface different slices
    of the repository space on each polling cycle.

    Strategies rotate so that over a full cycle, the poller sees
    top-starred repos, recently created projects, actively pushed
    repositories, and rising newcomers.
    """

    @type t :: :top_starred | :recently_created | :recently_pushed | :rising

    @strategies [:top_starred, :recently_created, :recently_pushed, :rising]

    @spec all() :: [t()]
    def all, do: @strategies

    @spec count() :: non_neg_integer()
    def count, do: length(@strategies)

    @spec at(non_neg_integer()) :: t()
    def at(index), do: Enum.at(@strategies, rem(index, length(@strategies)))
end
