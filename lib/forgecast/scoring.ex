defmodule Forgecast.Scoring do
    @moduledoc """
    Pure scoring functions for trending computation. Takes raw
    row data from the database and attaches velocity, score,
    and sort fields without any database or cache interaction.
    """

    @spec attach_scores(map(), number()) :: map()
    def attach_scores(row, window_hours) do
        # Event-based velocity (primary signal)
        ev_sv = row.event_stars / max(window_hours, 1)
        ev_fv = row.event_forks / max(window_hours, 1)

        # Snapshot-based velocity (fallback for non-GitHub platforms)
        hours = snapshot_window_hours(row.first_at, row.last_at)
        snap_sv = velocity(row.first_stars, row.last_stars, hours)
        snap_fv = velocity(row.first_forks, row.last_forks, hours)

        # Use whichever source gives a stronger signal
        sv = max(ev_sv, snap_sv)
        fv = max(ev_fv, snap_fv)

        stars = row.stars
        base = if stars > 0, do: :math.log2(stars), else: 0.0
        recency = recency_boost(row.inserted_at)
        score = sv * 10.0 + fv * 5.0 + base + recency

        row
        |> Map.put(:star_velocity, sv)
        |> Map.put(:fork_velocity, fv)
        |> Map.put(:score, score)
        |> Map.drop([
            :first_stars, :last_stars, :first_forks, :last_forks,
            :first_at, :last_at, :inserted_at,
            :event_stars, :event_forks
        ])
    end

    @spec sort(list(map()), atom() | nil, atom() | nil) :: list(map())
    def sort(items, nil, _), do: Enum.sort_by(items, & &1.score, :desc)

    def sort(items, field, dir) do
        direction = dir || :desc
        Enum.sort_by(items, &sort_key(&1, field), direction)
    end

    defp sort_key(item, :stars), do: item.stars
    defp sort_key(item, :forks), do: item.forks
    defp sort_key(item, :star_velocity), do: item.star_velocity
    defp sort_key(item, :score), do: item.score
    defp sort_key(item, :name), do: String.downcase(item.name || "")
    defp sort_key(item, :language), do: String.downcase(item.language || "")
    defp sort_key(item, _), do: item.score

    defp snapshot_window_hours(nil, _), do: 0.0
    defp snapshot_window_hours(_, nil), do: 0.0

    defp snapshot_window_hours(first_at, last_at) do
        NaiveDateTime.diff(last_at, first_at, :second) / 3600.0
    end

    defp velocity(_, _, hours) when hours <= 0, do: 0.0
    defp velocity(nil, _, _), do: 0.0
    defp velocity(_, nil, _), do: 0.0
    defp velocity(first, last, hours), do: (last - first) / hours

    defp recency_boost(nil), do: 0.0

    defp recency_boost(inserted_at) do
        days_old = div(NaiveDateTime.diff(NaiveDateTime.utc_now(), inserted_at, :second), 86_400)
        max(0.0, 5.0 - days_old * 0.05)
    end
end
