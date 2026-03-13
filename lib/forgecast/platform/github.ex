defmodule Forgecast.Platform.Github do
    @moduledoc """
    GitHub platform integration via the REST search API.

    Uses conditional requests (ETags) for both search and single-repo
    fetch calls so that unchanged responses return 304 and cost zero
    rate limit tokens on subsequent cycles.
    """

    @behaviour Forgecast.Platform

    alias Forgecast.Platform.{ETag, Header, Helper, Result}
    alias Forgecast.Poller.Strategy

    @base_url "https://api.github.com"
    @fetch_etag_table :github_fetch_etags
    @search_etag_table :github_search_etags

    @impl true
    @spec search(String.t(), keyword()) ::
        {:ok, [Result.t()], Forgecast.Platform.rate_info()}
        | {:not_modified, Forgecast.Platform.rate_info()}
        | {:rate_limited, Forgecast.Platform.rate_info()}
        | {:error, term()}
    def search(language, opts \\ []) do
        init_etag_cache()
        strategy = Keyword.get(opts, :strategy, %Strategy{type: :top_starred})
        page = Keyword.get(opts, :page, 1)
        {query, sort, order} = build_query(language, strategy)
        url = "#{@base_url}/search/repositories?q=#{URI.encode(query)}&sort=#{sort}&order=#{order}&per_page=25&page=#{page}"

        search_key = {language, strategy.type, page}
        headers = ETag.conditional_headers(@search_etag_table, search_key, base_headers())

        case Req.get(url, headers: headers) do
            {:ok, %Req.Response{status: 200, headers: resp_headers, body: body}} ->
                ETag.store_etag(@search_etag_table, search_key, resp_headers)
                repos = Enum.map(body["items"], &parse_repo/1)
                {:ok, repos, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 304, headers: resp_headers}} ->
                {:not_modified, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: status, headers: resp_headers}} when status in [403, 422, 429] ->
                {:rate_limited, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: status, body: body}} ->
                {:error, {status, Helper.extract_message(body)}}

            {:error, reason} ->
                {:error, reason}
        end
    end

    @impl true
    @spec fetch(Forgecast.Schema.Repository.t()) ::
        {:ok, Result.t(), Forgecast.Platform.rate_info()}
        | {:not_modified, Forgecast.Platform.rate_info()}
        | {:rate_limited, Forgecast.Platform.rate_info()}
        | {:error, term()}
    def fetch(repo) do
        init_etag_cache()
        url = "#{@base_url}/repos/#{repo.name}"
        headers = ETag.conditional_headers(@fetch_etag_table, repo.name, base_headers())

        case Req.get(url, headers: headers) do
            {:ok, %Req.Response{status: 200, headers: resp_headers, body: body}} ->
                ETag.store_etag(@fetch_etag_table, repo.name, resp_headers)
                {:ok, parse_repo(body), Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 304, headers: resp_headers}} ->
                {:not_modified, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: status, headers: resp_headers}} when status in [403, 429] ->
                {:rate_limited, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 404, body: body}} ->
                {:error, {:not_found, Helper.extract_message(body)}}

            {:ok, %Req.Response{status: status, body: body}} ->
                {:error, {status, Helper.extract_message(body)}}

            {:error, reason} ->
                {:error, reason}
        end
    end

    defp build_query(language, %Strategy{type: :top_starred, min_stars: min_stars, date_range: days}) do
        date = Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()
        {"language:#{language} pushed:>#{date} stars:>#{min_stars}", "stars", "desc"}
    end

    defp build_query(language, %Strategy{type: :recently_created, min_stars: min_stars, date_range: days}) do
        date = Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()
        {"language:#{language} created:>#{date} stars:>#{min_stars}", "stars", "desc"}
    end

    defp build_query(language, %Strategy{type: :recently_pushed, min_stars: min_stars, date_range: days}) do
        date = Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()
        {"language:#{language} pushed:>#{date} stars:>#{min_stars}", "stars", "desc"}
    end

    defp build_query(language, %Strategy{type: :rising, min_stars: min_stars, date_range: days}) do
        date = Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()
        {"language:#{language} created:>#{date} stars:>#{min_stars}", "stars", "desc"}
    end

    defp parse_repo(raw) do
        owner = raw["owner"]["login"]
        name = raw["name"]

        %Result{
            platform: "github",
            platform_id: to_string(raw["id"]),
            name: raw["full_name"],
            owner: owner,
            description: raw["description"],
            language: raw["language"],
            stars: raw["stargazers_count"],
            forks: raw["forks_count"],
            open_issues: raw["open_issues_count"],
            topics: raw["topics"] || [],
            url: raw["html_url"],
            avatar_url: raw["owner"]["avatar_url"],
            og_image_url: "https://opengraph.githubassets.com/1/#{owner}/#{name}"
        }
    end

    defp init_etag_cache do
        ETag.init(@fetch_etag_table)
        ETag.init(@search_etag_table)
    end

    defp base_headers do
        Header.github_headers()
    end
end
