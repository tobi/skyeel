task :install do
  sh "gem build skyeel.gemspec --output=/tmp/skyeel.gem"
  sh "gem install /tmp/skyeel.gem"
  sh "rm /tmp/skyeel.gem"
end
