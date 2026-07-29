# frozen_string_literal: true

module Config
  BASE_URL = ENV.fetch("ROLIASCAN_BASE_URL", "https://roliascan.com").sub(%r{/+\z}, "")
  CACHE_TTL = Integer(ENV.fetch("CACHE_TTL_SECONDS", "300"), exception: false) || 300
  CONNECT_TIMEOUT = Integer(ENV.fetch("CONNECT_TIMEOUT_SECONDS", "8"), exception: false) || 8
  REQUEST_TIMEOUT = Integer(ENV.fetch("REQUEST_TIMEOUT_SECONDS", "12"), exception: false) || 12
  HOME_LIMIT = Integer(ENV.fetch("HOME_LIMIT", "15"), exception: false) || 15
end
