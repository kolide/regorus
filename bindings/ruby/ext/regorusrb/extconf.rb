# bindings/ruby/ext/regorusrb/extconf.rb
require "rbconfig"
require "fileutils"
require "mkmf"
require "rb_sys/mkmf"

def aarch64_linux?
  cpu = RbConfig::CONFIG["host_cpu"]
  os  = RbConfig::CONFIG["host_os"]
  (cpu =~ /aarch64|arm64/) && (os =~ /linux/)
end

DLEXT    = RbConfig::CONFIG["DLEXT"]             # "so" on Linux
# Prebuilt lives inside the repo (tracked), see step 2
PREBUILT = File.expand_path("../../vendor/native/aarch64-linux/regorusrb.#{DLEXT}", __dir__)

# Where Ruby will look for the extension when you `require "regorus/regorusrb"`
DEST_DIR = File.expand_path("../../../lib/regorus", __dir__)
DEST_SO  = File.join(DEST_DIR, "regorusrb.#{DLEXT}")

if aarch64_linux? && File.exist?(PREBUILT)
  # Use prebuilt: copy it into the gem's lib and emit a no-op Makefile
  FileUtils.mkdir_p(DEST_DIR)
  FileUtils.cp(PREBUILT, DEST_SO)

  File.write("Makefile", <<~MK)
    all:
    install:
    	@true
    clean:
    	@true
  MK
else
  # Fallback: compile from Rust source (dev on macOS, CI, etc.)
  create_rust_makefile("regorus/regorusrb") do |r|
    r.auto_install_rust_toolchain = true
  end
end
