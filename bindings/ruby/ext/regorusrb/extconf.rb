# bindings/ruby/ext/regorusrb/extconf.rb
require "rbconfig"
require "fileutils"
require "mkmf"
require "rb_sys/mkmf"

cpu = RbConfig::CONFIG["host_cpu"]
os  = RbConfig::CONFIG["host_os"]
arch =
  if os =~ /linux/
    if cpu =~ /aarch64|arm64/
      "aarch64-linux"
    elsif cpu =~ /x86_64|amd64/
      "x86_64-linux"
    end
  end

DLEXT = RbConfig::CONFIG["DLEXT"]            # "so" on Linux
dest_dir = File.expand_path("../../lib/regorus", __dir__)
dest_so  = File.join(dest_dir, "regorusrb.#{DLEXT}")
prebuilt = arch && File.expand_path("../../vendor/native/#{arch}/regorusrb.#{DLEXT}", __dir__)

if prebuilt && File.exist?(prebuilt)
  # Use prebuilt, no-op Makefile so bundler is happy.
  FileUtils.mkdir_p(dest_dir)
  FileUtils.cp(prebuilt, dest_so)
  File.write("Makefile", "all:\ninstall:\n\t@true\nclean:\n\t@true\n")
else
  # Fallback: compile (dev/mac, or if a prebuilt is missing)
  create_rust_makefile("regorus/regorusrb") do |r|
    r.auto_install_rust_toolchain = true
  end
end
