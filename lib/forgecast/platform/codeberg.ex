defmodule Forgecast.Platform.Codeberg do
    @moduledoc """
    Codeberg platform integration via the Gitea-compatible REST API.

    Uses conditional requests (ETags) for both search and fetch
    calls so that unchanged responses cost minimal overhead.
    """

    @behaviour Forgecast.Platform

    alias Forgecast.Platform.{ETag, Header, Helper, Result}
    alias Forgecast.Poller.Strategy

    @base_url "https://codeberg.org/api/v1"
    @search_etag_table :codeberg_search_etags
    @fetch_etag_table :codeberg_fetch_etags

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
        {sort, order} = strategy_params(strategy)
        url = "#{@base_url}/repos/search?q=&language=#{language}&sort=#{sort}&order=#{order}&limit=25&page=#{page}"

        search_key = {language, strategy.type, page}
        headers = ETag.conditional_headers(@search_etag_table, search_key, base_headers())

        case Req.get(url, headers: headers) do
            {:ok, %Req.Response{status: 200, headers: resp_headers, body: body}} ->
                ETag.store_etag(@search_etag_table, search_key, resp_headers)
                repos = Enum.map(body["data"], &parse_repo/1)
                {:ok, repos, nil}

            {:ok, %Req.Response{status: 304, headers: resp_headers}} ->
                {:not_modified, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 429, headers: resp_headers}} ->
                {:rate_limited, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: status, body: body}} ->
                {:error, {status, Helper.extract_message(body)}}

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
        url = "#{@base_url}/repos/#{repo.name}"
        headers = ETag.conditional_headers(@fetch_etag_table, repo.name, base_headers())

        case Req.get(url, headers: headers) do
            {:ok, %Req.Response{status: 200, headers: resp_headers, body: body}} ->
                ETag.store_etag(@fetch_etag_table, repo.name, resp_headers)
                {:ok, parse_repo(body), nil}

            {:ok, %Req.Response{status: 304, headers: resp_headers}} ->
                {:not_modified, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 429, headers: resp_headers}} ->
                {:rate_limited, Helper.rate_limit_info(resp_headers)}

            {:ok, %Req.Response{status: 404, body: body}} ->
                {:error, {:not_found, Helper.extract_message(body)}}

            {:ok, %Req.Response{status: status, body: body}} ->
                {:error, {status, Helper.extract_message(body)}}

            {:error, reason} ->
                {:error, reason}
        end
    end

    defp strategy_params(%Strategy{type: :top_starred}), do: {"stars", "desc"}
    defp strategy_params(%Strategy{type: :recently_created}), do: {"created", "desc"}
    defp strategy_params(%Strategy{type: :recently_pushed}), do: {"updated", "desc"}
    defp strategy_params(%Strategy{type: :rising}), do: {"stars", "desc"}

    defp parse_repo(raw) do
        %Result{
            platform: "codeberg",
            platform_id: to_string(raw["id"]),
            name: raw["full_name"],
            owner: raw["owner"]["login"],
            description: raw["description"],
            language: raw["language"],
            stars: raw["stars_count"],
            forks: raw["forks_count"],
            open_issues: raw["open_issues_count"],
            topics: raw["topics"] || [],
            url: raw["html_url"],
            avatar_url: raw["owner"]["avatar_url"],
            og_image_url: nil
        }
    end

    defp init_etag_cache do
        ETag.init(@search_etag_table)
        ETag.init(@fetch_etag_table)
    end

    defp base_headers do
        Header.json_headers()
    end
end
