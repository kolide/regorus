# frozen_string_literal: true

require_relative "regorus/version"

begin
  # Fast path: use the file that extconf copies during install
  require_relative "regorus/regorusrb"
rescue LoadError => orig
  # Fallback: load directly from vendor/native if the copy isn't present
  require "rbconfig"

  cfg    = RbConfig::CONFIG
  os     = cfg["host_os"]
  cpu    = cfg["host_cpu"]
  dllext = cfg["DLEXT"]
  musl   = !!(os =~ /musl|alpine/)

  arch =
    if os =~ /linux/
      if cpu =~ /aarch64|arm64/
        musl ? "aarch64-linux-musl" : "aarch64-linux"
      elsif cpu =~ /x86_64|amd64/
        musl ? "x86_64-linux-musl" : "x86_64-linux"
      end
    end

  if arch
    # regorus.rb lives in bindings/ruby/lib/, vendor/native is ../vendor/native
    prebuilt = File.expand_path("../vendor/native/#{arch}/regorusrb.#{dllext}", __dir__)
    if File.exist?(prebuilt)
      require prebuilt
    else
      raise orig
    end
  else
    # Non-Linux (e.g., macOS) → let the original error bubble (extconf compiles there)
    raise orig
  end
end

module Regorus
  class Engine; end
end
