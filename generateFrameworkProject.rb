require 'cocoapods'
require 'cocoapods-core'
require 'xcodeproj'

require_relative 'AddFrameworkProject/project_creater'
require_relative 'AddFrameworkProject/project_posepec_installer'

root_path = Pathname.new(__FILE__).realpath.dirname.dirname


podSpecFinder = Pod::Sandbox::PodspecFinder.new( root_path)
podspecs = podSpecFinder.podspecs
podspec = nil
podspecs.each_value do |value|
  podspec = value
end

if podspec.nil?
  raise '未找到podsepc文件'
end

project_creater = ProjectCreater.new(root_path.join('temp_project'), podspec.name)
project_creater.transform

project = Xcodeproj::Project.open(root_path.join('temp_project').join("#{podspec.name}.xcodeproj").to_s)

installer = Project_posepec_installer.new(root_path,  podspec,  project)
installer.install

project.save
