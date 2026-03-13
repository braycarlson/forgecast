defmodule Forgecast.Scoring do
    @moduledoc """
    Pure scoring functions for trending computation. Used by the
    scoring worker to precompute scores stored on the repos table.
    """

    @spec compute(map()) :: %{score: float(), star_velocity: float(), fork_velocity: float()}
    def compute(params) do
        %{
            stars: stars,
            event_stars: event_stars,
            event_forks: event_forks,
            snap_star_velocity: snap_sv,
            snap_fork_velocity: snap_fv,
            window_hours: window_hours,
            inserted_at: inserted_at
        } = params

        ev_sv = event_stars / max(window_hours, 1)
        ev_fv = event_forks / max(window_hours, 1)

        sv = max(ev_sv, snap_sv)
        fv = max(ev_fv, snap_fv)

        base = if stars > 0, do: :math.log2(stars), else: 0.0
        recency = recency_boost(inserted_at)
        score = sv * 10.0 + fv * 5.0 + base + recency

        %{score: score, star_velocity: sv, fork_velocity: fv}
    end

    defp recency_boost(nil), do: 0.0

    defp recency_boost(inserted_at) do
        days_old = div(NaiveDateTime.diff(NaiveDateTime.utc_now(), inserted_at, :second), 86_400)
        max(0.0, 5.0 - days_old * 0.05)
    end
end
