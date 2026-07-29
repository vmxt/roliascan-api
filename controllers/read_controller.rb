# frozen_string_literal: true

require_relative "../utils/json_response"
require_relative "../utils/read_scraper"

class ReadController
  SCRAPER = ReadScraper.new

  def show(id, chapter_id)
    JsonResponse.ok(SCRAPER.read(id, chapter_id))
  end
end
