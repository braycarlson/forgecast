defmodule Forgecast.Platform.Gitlab do
    @moduledoc """
    GitLab platform integration via the REST v4 API.

    Uses conditional requests (ETags) for both search and fetch
    calls so that unchanged responses cost minimal overhead.
    """

    @behaviour Forgecast.Platform

    alias Forgecast.Platform.{ETag, Header, Helper, Result}
    alias Forgecast.Poller.Strategy

    @base_url "https://gitlab.com/api/v4"
    @search_etag_table :gitlab_search_etags
    @fetch_etag_table :gitlab_fetch_etags

    @language_map %{
        "python" => "Python",
        "rust" => "Rust",
        "go" => "Go",
        "elixir" => "Elixir",
        "typescript" => "TypeScript",
        "javascript" => "JavaScript",
        "zig" => "Zig",
        "c" => "C",
        "cpp" => "C++",
        "c-sharp" => "C#",
        "java" => "Java",
        "ruby" => "Ruby",
        "swift" => "Swift",
        "kotlin" => "Kotlin",
        "lua" => "Lua",
        "haskell" => "Haskell",
        "scala" => "Scala",
        "dart" => "Dart",
        "php" => "PHP",
        "r" => "R"
    }

    # Linguist names used by GitLab's with_programming_language filter.
    # This is the same as @language_map but used for query input rather
    # than normalizing output. Unmapped languages get title-cased as a
    # best-effort fallback since Linguist names are typically capitalized.
    @query_language_map @language_map

    @impl true
    @spec search(String.t(), keyword()) ::
        {:ok, [Result.t()], Forgecast.Platform.rate_info() | nil}
        | {:not_modified, Forgecast.Platform.rate_info() | nil}
        | {:rate_limited, Forgecast.Platform.rate_info()}
        | {:error, term()}
    def search(language, opts \\ []) do
        init_etag_cache()
        strategy = Keyword.get(opts, :strategy, %Strategy{type: :top_starred})
        page = Keyword.get(opts, :page, 1)
        url = build_url(language, strategy, page)

        search_key = {language, strategy.type, page}
        headers = ETag.conditional_headers(@search_etag_table, search_key, base_headers())

        case Req.get(url, headers: headers) do
            {:ok, %Req.Response{status: 200, headers: resp_headers, body: body}} ->
                ETag.store_etag(@search_etag_table, search_key, resp_headers)

                repos =
                    body
                    |> Enum.map(&parse_repo(&1, language))
                    |> Enum.sort_by(& &1.stars, :desc)

                {:ok, repos, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 304, headers: resp_headers}} ->
                {:not_modified, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 429, headers: resp_headers}} ->
                {:rate_limited, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: status, body: body}} ->
                {:error, {status, body}}

            {:error, reason} ->
                {:error, reason}
        end
    end

    @impl true
    @spec fetch(Forgecast.Schema.Repository.t()) ::
        {:ok, Result.t(), Forgecast.Platform.rate_info() | nil}
        | {:not_modified, Forgecast.Platform.rate_info() | nil}
        | {:rate_limited, Forgecast.Platform.rate_info()}
        | {:error, term()}
    def fetch(repo) do
        init_etag_cache()
        url = "#{@base_url}/projects/#{repo.platform_id}"
        headers = ETag.conditional_headers(@fetch_etag_table, repo.platform_id, base_headers())

        case Req.get(url, headers: headers) do
            {:ok, %Req.Response{status: 200, headers: resp_headers, body: body}} ->
                ETag.store_etag(@fetch_etag_table, repo.platform_id, resp_headers)
                lang = repo.language || "unknown"
                {:ok, parse_repo(body, lang), Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 304, headers: resp_headers}} ->
                {:not_modified, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 429, headers: resp_headers}} ->
                {:rate_limited, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 404, body: body}} ->
                {:error, {:not_found, body}}

            {:ok, %Req.Response{status: status, body: body}} ->
                {:error, {status, body}}

            {:error, reason} ->
                {:error, reason}
        end
    end

    defp build_url(language, %Strategy{} = strategy, page) do
        params = strategy_params(strategy)
        gl_language = query_language(language)

        base =
            "#{@base_url}/projects?with_programming_language=#{URI.encode_www_form(gl_language)}&per_page=25&page=#{page}"

        Enum.reduce(params, base, fn {key, value}, url ->
            "#{url}&#{key}=#{value}"
        end)
    end

    defp strategy_params(%Strategy{type: :top_starred, min_stars: min_stars}) do
        [order_by: "star_count", sort: "desc", min_access_level: 0] ++
            if(min_stars > 0, do: [stars_count_min: min_stars], else: [])
    end

    defp strategy_params(%Strategy{type: :recently_created, date_range: days}) do
        date = Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()
        [order_by: "created_at", sort: "desc", created_after: date]
    end

    defp strategy_params(%Strategy{type: :recently_pushed, date_range: days}) do
        date = Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()
        [order_by: "last_activity_at", sort: "desc", last_activity_after: date]
    end

    defp strategy_params(%Strategy{type: :rising, min_stars: min_stars, date_range: days}) do
        date = Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()
        [order_by: "star_count", sort: "desc", created_after: date] ++
            if(min_stars > 0, do: [stars_count_min: min_stars], else: [])
    end

    defp parse_repo(raw, language) do
        owner = raw["namespace"]["path"] || ""

        %Result{
            platform: "gitlab",
            platform_id: to_string(raw["id"]),
            name: raw["path_with_namespace"],
            owner: owner,
            description: raw["description"],
            language: normalize_language(language),
            stars: raw["star_count"] || 0,
            forks: raw["forks_count"] || 0,
            open_issues: raw["open_issues_count"] || 0,
            topics: raw["topics"] || [],
            url: raw["web_url"],
            avatar_url: raw["namespace"]["avatar_url"] || raw["avatar_url"],
            og_image_url: nil
        }
    end

    defp normalize_language(lang) when is_binary(lang) do
        Map.get(@language_map, String.downcase(lang), lang)
    end

    defp normalize_language(lang), do: lang

    defp query_language(lang) when is_binary(lang) do
        case Map.get(@query_language_map, String.downcase(lang)) do
            nil ->
                lang
                |> String.split("-")
                |> Enum.map_join("-", &String.capitalize/1)

            mapped ->
                mapped
        end
    end

    defp query_language(lang), do: lang

    defp init_etag_cache do
        ETag.init(@search_etag_table)
        ETag.init(@fetch_etag_table)
    end

    defp base_headers do
        Header.json_headers()
    end
end
