require 'pathname'

class ProjectCreater
    def initialize(root, name)
      @project_path = Pathname.new(root).realpath
      @project_name = name
    end

    def transform
      puts "ProjectCreater-开始"
      prepare
      puts "ProjectCreater-开始重命名"
      rename
      puts "ProjectCreater-完成"
    end

    private
    def prepare
      xcodeproj_path = @project_path.join("#{@project_name}.xcodeproj").to_s
      if File.exist?(xcodeproj_path)
        `rm -rf #{xcodeproj_path}`
      end
    end

    def rename
      Dir.glob(File.join(@project_path.join("Podfile").to_s)).each do |file|
        content = File.read file
        content = content.gsub(/POD_NAME/, @project_name)
        File.open(file, 'w') { |f| f << content }
      end

      Dir.glob(@project_path.join('PROJECT.xcodeproj').to_s + '/**/*').each do |name|
        next if Dir.exist? name
        if File.extname(name) == '.xcuserstate'
          next
        end
        text = File.read name
        text = text.gsub("PROJECT",@project_name)
        File.open(name, "w") { |file| file.puts text }
      end

      scheme_path = @project_path.join("PROJECT.xcodeproj/xcshareddata/xcschemes/").to_s
      File.rename(scheme_path + "PROJECT.xcscheme", scheme_path +  @project_name + ".xcscheme")
      File.rename(@project_path.join("PROJECT.xcodeproj").to_s, @project_path.join(@project_name + ".xcodeproj").to_s)
    end
end