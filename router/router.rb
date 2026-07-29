# frozen_string_literal: true

require "rack/cors"
require "roda"

require_relative "../controllers/home_controller"
require_relative "../controllers/browse_controller"
require_relative "../controllers/manga_controller"
require_relative "../controllers/read_controller"
require_relative "../controllers/random_controller"
require_relative "../controllers/search_controller"
require_relative "../utils/json_response"

class RoliascansAPI < Roda
  plugin :json
  plugin :default_headers, "Content-Type" => "application/json; charset=utf-8"

  use Rack::Cors do
    allow do
      origins(*ENV.fetch("CORS_ORIGINS", "*").split(",").map(&:strip))
      resource "*", headers: :any, methods: %i[get options]
    end
  end

  plugin :error_handler do |error|
    status = error.respond_to?(:status) ? error.status : 500
    response.status = status
    JsonResponse.error(error.message, status: status)
  end

  route do |r|
    r.root do
      JsonResponse.ok(message: "Welcome to Roliascans-API")
    end

    r.on "home" do
      r.get do
        HomeController.new.index
      end
    end

    r.on "browse" do
      r.get do
        BrowseController.new.index(r.params)
      end
    end

    r.on "manga", String do |id|
      r.get do
        MangaController.new.show(id)
      end
    end

    r.on "read", String, String do |id, chapter_id|
      r.get do
        ReadController.new.show(id, chapter_id)
      end
    end

    r.on "random" do
      r.get do
        response["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        response["Pragma"] = "no-cache"
        response["Expires"] = "0"
        RandomController.new.index
      end
    end

    r.on "search" do
      r.get String do |keyword|
        SearchController.new.index(keyword: keyword, limit: r.params["limit"])
      end

      r.get do
        keyword = r.params["keyword"] || r.params["q"] || r.params["query"]
        SearchController.new.index(keyword: keyword, limit: r.params["limit"])
      end
    end

    response.status = 404
    JsonResponse.error("Endpoint not found", status: 404)
  end
end
