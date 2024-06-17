Gem::Specification.new do |s|
  s.name        = "skyeel"
  s.version     = "0.4.0"
  s.summary     = "Cosplay being skypilot, except shitty"
  s.authors     = ["Tobi Lutke"]
  s.email       = "tobi@lutke.com"
  s.files       = ["skyeel.rb"]
  s.license     = "MIT"
  s.bindir      = "bin"
  s.executables = ['skyeel']
  s.require_paths = ["."]
  s.add_runtime_dependency "net-ssh"
  s.add_runtime_dependency "ed25519"
end
