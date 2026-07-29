# frozen_string_literal: true

require_relative "../utils/json_response"
require_relative "../utils/random_scraper"

class RandomController
  SCRAPER = RandomScraper.new

  def index
    JsonResponse.ok(SCRAPER.random)
  end
end
