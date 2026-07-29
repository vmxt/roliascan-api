# frozen_string_literal: true

require_relative "../utils/home_scraper"
require_relative "../utils/json_response"

class HomeController
  SCRAPER = HomeScraper.new

  def index
    JsonResponse.ok(SCRAPER.home)
  end
end
