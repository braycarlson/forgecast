defmodule Forgecast.Platform.Result do
    @moduledoc """
    Normalized result returned by all platform integrations.
    """

    @enforce_keys [:platform, :platform_id, :name, :owner, :url, :stars, :forks, :open_issues]

    @type t :: %__MODULE__{
        platform: String.t(),
        platform_id: String.t(),
        name: String.t(),
        owner: String.t(),
        description: String.t() | nil,
        language: String.t() | nil,
        url: String.t(),
        avatar_url: String.t() | nil,
        og_image_url: String.t() | nil,
        stars: non_neg_integer(),
        forks: non_neg_integer(),
        open_issues: non_neg_integer(),
        topics: [String.t()]
    }

    defstruct [
        :platform,
        :platform_id,
        :name,
        :owner,
        :description,
        :language,
        :url,
        :avatar_url,
        :og_image_url,
        stars: 0,
        forks: 0,
        open_issues: 0,
        topics: []
    ]
end
