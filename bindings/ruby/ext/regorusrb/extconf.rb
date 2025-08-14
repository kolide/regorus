# bindings/ruby/ext/regorusrb/extconf.rb
require "rbconfig"
require "fileutils"
require "mkmf"
require "rb_sys/mkmf"

cpu = RbConfig::CONFIG["host_cpu"]
os  = RbConfig::CONFIG["host_os"]
musl = os =~ /musl|alpine/
arch =
  if os =~ /linux/
    if cpu =~ /aarch64|arm64/
      musl ? "aarch64-linux-musl" : "aarch64-linux"
    elsif cpu =~ /x86_64|amd64/
      musl ? "x86_64-linux-musl" : "x86_64-linux"
    end
  end

DLEXT   = RbConfig::CONFIG["DLEXT"]
dest_dir = File.expand_path("../../lib/regorus", __dir__)
dest_so  = File.join(dest_dir, "regorusrb.#{DLEXT}")
prebuilt = arch && File.expand_path("../../vendor/native/#{arch}/regorusrb.#{DLEXT}", __dir__)

if prebuilt && File.exist?(prebuilt)
  # Defer the copy to `make install` so it runs in all fresh-install flows
  File.write("Makefile", <<~MK)
        all:
        install:
    \tmkdir -p #{dest_dir}
    \tcp #{prebuilt} #{dest_so}
        clean:
    \t@true
  MK
else
  # Fallback: compile (e.g., dev on macOS, or if a prebuilt is missing)
  create_rust_makefile("regorus/regorusrb") do |r|
    r.auto_install_rust_toolchain = true
  end
end
