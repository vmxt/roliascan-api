# frozen_string_literal: true

require_relative "../utils/json_response"
require_relative "../utils/manga_scraper"

class MangaController
  SCRAPER = MangaScraper.new

  def show(id)
    JsonResponse.ok(SCRAPER.manga(id))
  end
end
