# frozen_string_literal: true

module JsonResponse
  def self.ok(data = nil, **fields)
    payload = { success: true }
    payload[:data] = data unless data.nil?
    payload.merge!(fields)
    payload
  end

  def self.error(message, status: 500, details: nil)
    payload = {
      success: false,
      status: status,
      error: message
    }
    payload[:details] = details if details
    payload
  end
end
