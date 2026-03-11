defmodule Forgecast.Platform.Header do
    @moduledoc """
    Shared HTTP header builders for platform integrations and
    internal subsystems. Centralizes the GitHub token injection
    and common accept/user-agent headers.
    """

    @spec github_headers() :: [{String.t(), String.t()}]
    def github_headers do
        base = [
            {"accept", "application/vnd.github+json"},
            {"user-agent", "forgecast/0.1"},
            {"x-github-api-version", "2022-11-28"}
        ]

        append_github_token(base)
    end

    @spec github_graphql_headers() :: [{String.t(), String.t()}]
    def github_graphql_headers do
        base = [
            {"content-type", "application/json"},
            {"user-agent", "forgecast/0.1"}
        ]

        append_github_token(base)
    end

    @spec json_headers() :: [{String.t(), String.t()}]
    def json_headers do
        [
            {"accept", "application/json"},
            {"user-agent", "forgecast/0.1"}
        ]
    end

    @spec download_headers() :: [{String.t(), String.t()}]
    def download_headers do
        [{"user-agent", "forgecast/0.1"}]
    end

    defp append_github_token(headers) do
        case Application.get_env(:forgecast, :github, [])[:token] do
            nil -> headers
            "" -> headers
            token -> [{"authorization", "Bearer #{token}"} | headers]
        end
    end
end
