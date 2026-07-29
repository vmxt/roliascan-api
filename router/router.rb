# frozen_string_literal: true

require "rack/cors"
require "roda"

require_relative "../controllers/home_controller"
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

    response.status = 404
    JsonResponse.error("Endpoint not found", status: 404)
  end
end
