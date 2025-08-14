# bindings/ruby/ext/regorusrb/extconf.rb
require "rbconfig"
require "fileutils"
require "mkmf"
require "rb_sys/mkmf"

cfg    = RbConfig::CONFIG
cpu    = cfg["host_cpu"]
os     = cfg["host_os"]
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

dest_dir = File.expand_path("../../lib/regorus", __dir__)
dest_so  = File.join(dest_dir, "regorusrb.#{dllext}")
prebuilt = arch && File.expand_path("../../vendor/native/#{arch}/regorusrb.#{dllext}", __dir__)

force_compile = ENV["REGORUS_FORCE_COMPILE"] == "1"

def glibc_host_version
  v = `ldd --version 2>&1`.lines.first[/(\d+\.\d+)/, 1] rescue nil
  Gem::Version.new(v || "0")
end

def glibc_required_version(so_path)
  v = `strings #{so_path} 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1`[/GLIBC_(\d+\.\d+)/, 1] rescue nil
  Gem::Version.new(v || "0")
end

use_prebuilt = prebuilt && File.exist?(prebuilt) && !force_compile

# If we're on glibc Linux and the prebuilt requires a newer GLIBC than the host, compile instead.
if use_prebuilt && !musl && os =~ /linux/
  begin
    req = glibc_required_version(prebuilt)
    host = glibc_host_version
    use_prebuilt = false if req > host
  rescue
    # If detection fails, be conservative: keep use_prebuilt as-is
  end
end

if use_prebuilt
  # IMPORTANT: do the copy in `make install` so Bundler/Rubygems runs it in fresh installs.
  File.open("Makefile", "w") do |f|
    f.puts "all:"
    f.puts "install:"
    f.puts "\tmkdir -p #{dest_dir}"
    f.puts "\tcp #{prebuilt} #{dest_so}"
    f.puts "clean:"
    f.puts "\t@true"
  end
else
  # Fallback: compile (macOS, Windows, musl/glibc mismatch, or when prebuilt is missing)
  create_rust_makefile("regorus/regorusrb") do |r|
    r.auto_install_rust_toolchain = true
  end
end
