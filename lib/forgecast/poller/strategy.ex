defmodule Forgecast.Poller.Strategy do
    @moduledoc """
    Defines discovery query strategies with configurable parameters.

    Each strategy is a struct carrying its own star threshold, date
    range, page limit, and cooldown duration. Strategies are grouped
    into named profiles that can be swapped via config:

        config :forgecast, :poller,
            profile: :discovery

    Available profiles:
      - :discovery  — max repo ingestion, low star floors, deep pagination
      - :trending   — focus on hot/rising repos with frequent re-checks
      - :balanced   — moderate discovery with steady monitoring (default)
      - :minimal    — light polling for development or low-resource deploys
    """

    @type t :: %__MODULE__{
        type: atom(),
        min_stars: non_neg_integer(),
        date_range: non_neg_integer(),
        page_limit: non_neg_integer(),
        cooldown_ms: non_neg_integer()
    }

    @enforce_keys [:type]

    defstruct [
        :type,
        min_stars: 50,
        date_range: 30,
        page_limit: 4,
        cooldown_ms: 1_800_000
    ]

    @spec profiles() :: %{atom() => map()}
    def profiles do
        %{
            discovery: %{
                discovery_ratio: %{initial: 0.95, normal: 0.7, mature: 0.5},
                strategies: [
                    %__MODULE__{type: :top_starred, min_stars: 5, date_range: 180, page_limit: 10, cooldown_ms: 600_000},
                    %__MODULE__{type: :recently_created, min_stars: 1, date_range: 14, page_limit: 10, cooldown_ms: 300_000},
                    %__MODULE__{type: :recently_pushed, min_stars: 2, date_range: 7, page_limit: 8, cooldown_ms: 300_000},
                    %__MODULE__{type: :rising, min_stars: 5, date_range: 60, page_limit: 10, cooldown_ms: 600_000}
                ]
            },
            trending: %{
                discovery_ratio: %{initial: 0.8, normal: 0.2, mature: 0.1},
                strategies: [
                    %__MODULE__{type: :top_starred, min_stars: 100, date_range: 30, page_limit: 4, cooldown_ms: 900_000},
                    %__MODULE__{type: :recently_created, min_stars: 20, date_range: 7, page_limit: 4, cooldown_ms: 600_000},
                    %__MODULE__{type: :recently_pushed, min_stars: 50, date_range: 3, page_limit: 4, cooldown_ms: 600_000},
                    %__MODULE__{type: :rising, min_stars: 25, date_range: 14, page_limit: 6, cooldown_ms: 600_000}
                ]
            },
            balanced: %{
                discovery_ratio: %{initial: 0.9, normal: 0.3, mature: 0.15},
                strategies: [
                    %__MODULE__{type: :top_starred, min_stars: 50, date_range: 90, page_limit: 4, cooldown_ms: 1_800_000},
                    %__MODULE__{type: :recently_created, min_stars: 5, date_range: 7, page_limit: 4, cooldown_ms: 1_200_000},
                    %__MODULE__{type: :recently_pushed, min_stars: 25, date_range: 3, page_limit: 4, cooldown_ms: 1_800_000},
                    %__MODULE__{type: :rising, min_stars: 20, date_range: 30, page_limit: 4, cooldown_ms: 1_800_000}
                ]
            },
            minimal: %{
                discovery_ratio: %{initial: 0.8, normal: 0.2, mature: 0.1},
                strategies: [
                    %__MODULE__{type: :top_starred, min_stars: 200, date_range: 90, page_limit: 2, cooldown_ms: 3_600_000},
                    %__MODULE__{type: :recently_created, min_stars: 50, date_range: 7, page_limit: 2, cooldown_ms: 3_600_000}
                ]
            }
        }
    end

    @spec profile() :: atom()
    def profile do
        Application.get_env(:forgecast, :poller, [])
        |> Keyword.get(:profile, :balanced)
    end

    @spec profile_config() :: map()
    def profile_config do
        profile_config(profile())
    end

    @spec profile_config(atom()) :: map()
    def profile_config(name) do
        Map.get(profiles(), name) || Map.fetch!(profiles(), :balanced)
    end

    @spec strategies() :: [t()]
    def strategies do
        profile_config().strategies
    end

    @spec discovery_ratio(non_neg_integer()) :: float()
    def discovery_ratio(repo_count) do
        ratios = profile_config().discovery_ratio

        cond do
            repo_count < 100 -> ratios.initial
            repo_count < 1000 -> ratios.normal
            true -> ratios.mature
        end
    end

    @spec count() :: non_neg_integer()
    def count, do: length(strategies())

    @spec at(non_neg_integer()) :: t()
    def at(index) do
        strats = strategies()
        Enum.at(strats, rem(index, length(strats)))
    end

    @spec available_profiles() :: [atom()]
    def available_profiles, do: Map.keys(profiles())
end
