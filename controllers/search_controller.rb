# frozen_string_literal: true

require_relative "../utils/json_response"
require_relative "../utils/search_scraper"

class SearchController
  SCRAPER = SearchScraper.new

  def index(keyword:, limit: nil)
    JsonResponse.ok(SCRAPER.search(keyword, limit: limit))
  end
end
