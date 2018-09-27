# frozen_string_literal: true
module EnvTestHelper
  def with_env(key, value)
    old_env_id = ENV[key]

    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value.to_s
    end

    yield
  ensure
    ENV[key] = old_env_id
  end
end
