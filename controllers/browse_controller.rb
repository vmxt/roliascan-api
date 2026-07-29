# frozen_string_literal: true

require_relative "../utils/browse_scraper"
require_relative "../utils/json_response"

class BrowseController
  SCRAPER = BrowseScraper.new

  def index(params = {})
    JsonResponse.ok(SCRAPER.browse(params))
  end
end
