def run(command)
  system(command) or raise "RAKE TASK FAILED: #{command}"
end

desc "Run unit tests for all OS X targets"
task :test do |t|
  run "xcodebuild -workspace Quick.xcworkspace -scheme Quick clean test"
  run "xcodebuild -workspace Quick.xcworkspace -scheme Nimble-OSX clean test"
end

namespace "templates" do
  install_dir = File.expand_path("~/Library/Developer/Xcode/Templates/File Templates/Quick")
  src_dir = File.expand_path("../Quick Templates", __FILE__)

  desc "Install Quick templates"
  task :install do
    if File.exists? install_dir
      raise "RAKE TASK FAILED: Quick templates are already installed at #{install_dir}"
    else
      mkdir_p install_dir
      cp_r src_dir, install_dir
    end
  end

  desc "Uninstall Quick templates"
  task :uninstall do
    rm_rf install_dir
  end
end

task default: [:test]

