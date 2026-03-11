defmodule Forgecast.Image.Cache do
    @moduledoc """
    Downloads and caches OpenGraph preview images on the local
    filesystem. Images are stored on the Fly.io persistent volume
    and served directly from disk by the API endpoint.

    Refresh intervals are velocity-aware: hot repos (high star
    velocity) get refreshed more frequently than cold repos,
    keeping the embedded star/fork counts reasonably current
    without wasting API calls on dormant repositories.

    Repos with zero velocity that already have a cached image
    are skipped entirely to avoid unnecessary downloads, since
    the embedded star/fork counts won't have changed.

    Uses conditional requests (If-Modified-Since) so refreshes
    of unchanged images cost minimal bandwidth and avoid
    unnecessary disk writes.
    """

    require Logger

    alias Forgecast.Platform.Header
    alias Forgecast.Repo
    alias Forgecast.Schema.Repository
    alias Forgecast.Velocity

    import Ecto.Query

    @max_refresh_days 30
    @min_refresh_hours 6
    @etag_table :og_image_etags

    # -- Public API --

    @spec storage_dir() :: String.t()
    def storage_dir do
        Application.get_env(:forgecast, :og_image_dir, "/data/og_images")
    end

    @spec ensure_storage_dir() :: :ok | {:error, term()}
    def ensure_storage_dir do
        dir = storage_dir()

        case File.mkdir_p(dir) do
            :ok -> :ok
            {:error, reason} ->
                Logger.error("[Image.Cache] Failed to create storage dir #{dir}: #{inspect(reason)}")
                {:error, reason}
        end
    end

    @spec init_etag_cache() :: :ok
    def init_etag_cache do
        init_conditional_cache()
        :ok
    end

    @spec image_path(integer()) :: String.t()
    def image_path(repo_id) when is_integer(repo_id) do
        Path.join(storage_dir(), "#{repo_id}.png")
    end

    @spec image_path(String.t(), String.t()) :: String.t()
    def image_path(owner, name) do
        repo_name = name |> String.split("/") |> List.last()
        filename = "#{owner}_#{repo_name}.png" |> String.replace(~r/[^\w.-]/, "_")
        Path.join(storage_dir(), filename)
    end

    @spec get_cached_image(integer()) :: {:ok, String.t()} | :not_found
    def get_cached_image(repo_id) do
        case Repo.get(Repository, repo_id) do
            nil ->
                :not_found

            repo ->
                path = image_path(repo.owner, repo.name)

                if File.exists?(path) do
                    {:ok, path}
                else
                    legacy = image_path(repo_id)

                    if File.exists?(legacy) do
                        File.rename(legacy, path)
                        {:ok, path}
                    else
                        :not_found
                    end
                end
        end
    end

    @spec download_and_cache(Repository.t()) :: :ok | :not_modified | :skipped | {:error, term()}
    def download_and_cache(%Repository{} = repo) do
        url = og_image_url(repo)

        if url do
            path = image_path(repo.owner, repo.name)

            # Skip download entirely for dormant repos that already
            # have a cached image — the embedded counts haven't changed.
            if File.exists?(path) and dormant?(repo.id) do
                mark_cached(repo.id)
                :skipped
            else
                do_download(repo.id, url, path)
            end
        else
            {:error, :no_og_url}
        end
    end

    @spec download_and_cache(integer(), String.t()) :: :ok | :not_modified | :skipped | {:error, term()}
    def download_and_cache(repo_id, url) when is_integer(repo_id) and is_binary(url) do
        case Repo.get(Repository, repo_id) do
            nil ->
                {:error, :not_found}

            repo ->
                path = image_path(repo.owner, repo.name)

                if File.exists?(path) and dormant?(repo.id) do
                    mark_cached(repo.id)
                    :skipped
                else
                    do_download(repo.id, url, path)
                end
        end
    end

    @spec needs_refresh?(Repository.t()) :: boolean()
    def needs_refresh?(%Repository{og_image_url: nil}), do: false
    def needs_refresh?(%Repository{og_image_url: ""}), do: false
    def needs_refresh?(%Repository{og_image_cached_at: nil}), do: true

    def needs_refresh?(%Repository{} = repo) do
        refresh_seconds = refresh_interval_seconds(repo.id)
        cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -refresh_seconds)
        NaiveDateTime.compare(repo.og_image_cached_at, cutoff) == :lt
    end

    @spec repos_needing_cache(non_neg_integer()) :: [Repository.t()]
    def repos_needing_cache(limit \\ 50) do
        # Use the max refresh interval as a broad filter, then
        # refine in-memory with per-repo velocity checks
        max_cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -@max_refresh_days * 86_400)

        candidates =
            from(r in Repository,
                where: not is_nil(r.og_image_url),
                where: is_nil(r.og_image_cached_at) or r.og_image_cached_at < ^max_cutoff,
                order_by: [asc_nulls_first: r.og_image_cached_at, desc: r.stars],
                limit: ^(limit * 2)
            )
            |> Repo.all()

        # Also pick up hot repos that need more frequent refreshes
        hot_cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -@min_refresh_hours * 3600)

        hot_candidates =
            from(r in Repository,
                where: not is_nil(r.og_image_url),
                where: not is_nil(r.og_image_cached_at),
                where: r.og_image_cached_at >= ^max_cutoff,
                where: r.og_image_cached_at < ^hot_cutoff,
                order_by: [desc: r.stars],
                limit: ^limit
            )
            |> Repo.all()

        (candidates ++ hot_candidates)
        |> Enum.uniq_by(& &1.id)
        |> Enum.filter(&needs_refresh?/1)
        |> Enum.take(limit)
    end

    @spec mark_cached(integer()) :: {:ok, integer()}
    def mark_cached(repo_id) do
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        from(r in Repository, where: r.id == ^repo_id)
        |> Repo.update_all(set: [og_image_cached_at: now])

        {:ok, repo_id}
    end

    @spec refresh_interval_seconds(integer()) :: non_neg_integer()
    def refresh_interval_seconds(repo_id) do
        velocity = Velocity.star_velocity(repo_id)

        cond do
            # >10 stars/hour: refresh every 6 hours
            velocity > 10.0 -> @min_refresh_hours * 3600
            # >1 star/hour: refresh every 24 hours
            velocity > 1.0 -> 86_400
            # >0.1 stars/hour: refresh every 3 days
            velocity > 0.1 -> 3 * 86_400
            # >0 stars/hour: refresh every 7 days
            velocity > 0.0 -> 7 * 86_400
            # dormant: refresh every 30 days
            true -> @max_refresh_days * 86_400
        end
    end

    # -- Private --

    @spec dormant?(integer()) :: boolean()
    defp dormant?(repo_id) do
        Velocity.star_velocity(repo_id) == 0.0
    end

    defp do_download(repo_id, url, path) do
        ensure_storage_dir()
        tmp_path = path <> ".tmp"
        conditional_headers = build_conditional_headers(repo_id)

        result =
            try do
                Req.get(url,
                    headers: conditional_headers,
                    into: File.stream!(tmp_path),
                    receive_timeout: 15_000
                )
            rescue
                e -> {:error, e}
            end

        case result do
            {:ok, %Req.Response{status: 200, headers: resp_headers}} ->
                store_conditional_headers(repo_id, resp_headers)
                File.rename(tmp_path, path)
                mark_cached(repo_id)
                Logger.info("[Image.Cache] Cached image for repo #{repo_id}")
                :ok

            {:ok, %Req.Response{status: 304}} ->
                File.rm(tmp_path)
                mark_cached(repo_id)
                Logger.debug("[Image.Cache] Not modified for repo #{repo_id}")
                :not_modified

            {:ok, %Req.Response{status: status}} ->
                File.rm(tmp_path)
                Logger.warning("[Image.Cache] Failed to download image for repo #{repo_id}: HTTP #{status}")
                {:error, {:http_status, status}}

            {:error, reason} ->
                File.rm(tmp_path)
                Logger.warning("[Image.Cache] Failed to download image for repo #{repo_id}: #{inspect(reason)}")
                {:error, reason}
        end
    end

    # Image downloads use a richer conditional cache (etag + last-modified)
    # than the standard ETagCache, so we manage this table directly.

    defp init_conditional_cache do
        if :ets.whereis(@etag_table) == :undefined do
            :ets.new(@etag_table, [:set, :public, :named_table])
        end
    end

    defp build_conditional_headers(repo_id) do
        base = Header.download_headers()

        case :ets.whereis(@etag_table) do
            :undefined ->
                base

            _ ->
                case :ets.lookup(@etag_table, repo_id) do
                    [{_, %{etag: etag}}] when is_binary(etag) ->
                        [{"if-none-match", etag} | base]

                    [{_, %{last_modified: lm}}] when is_binary(lm) ->
                        [{"if-modified-since", lm} | base]

                    _ ->
                        base
                end
        end
    end

    defp store_conditional_headers(repo_id, resp_headers) do
        if :ets.whereis(@etag_table) != :undefined do
            etag =
                case Map.get(resp_headers, "etag") do
                    [val | _] -> val
                    _ -> nil
                end

            last_modified =
                case Map.get(resp_headers, "last-modified") do
                    [val | _] -> val
                    _ -> nil
                end

            if etag || last_modified do
                :ets.insert(@etag_table, {repo_id, %{etag: etag, last_modified: last_modified}})
            end
        end
    end

    defp og_image_url(%Repository{og_image_url: url}) when is_binary(url) and url != "", do: url

    defp og_image_url(%Repository{platform: "github", owner: owner, name: name}) do
        repo_name = name |> String.split("/") |> List.last()
        "https://opengraph.githubassets.com/1/#{owner}/#{repo_name}"
    end

    defp og_image_url(_), do: nil
end
