# frozen_string_literal: true

class CacheStore
  Entry = Struct.new(:value, :expires_at, keyword_init: true)

  def initialize(ttl:)
    @ttl = ttl
    @store = {}
    @mutex = Mutex.new
  end

  def fetch(key)
    now = monotonic_time

    @mutex.synchronize do
      entry = @store[key]
      return entry.value if entry && entry.expires_at > now
    end

    value = yield

    @mutex.synchronize do
      @store[key] = Entry.new(value: value, expires_at: now + @ttl)
    end

    value
  end

  private

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
