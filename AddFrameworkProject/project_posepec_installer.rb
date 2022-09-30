class Project_posepec_installer

  attr_reader :podspec

  attr_reader :project

  attr_reader :root_path

  attr_reader :fileAccessor
  attr_reader :file_accessors

  def initialize(absolute_path, podspec, project)
    @root_path = absolute_path
    @podspec = podspec
    @project = project

    @refs_by_absolute_path = {}
    @variant_groups_by_path_and_name = {}
  end

  def install
    puts "AddFiles-开始"
    prepare
    puts "AddFiles-添加源文件引用"
    add_source_files
    puts "AddFiles-添加头文件引用"
    add_header_file
    puts "AddFiles-添加资源文件引用"
    add_resources
    puts "AddFiles-添加frameworks文件引用"
    add_vendored_frameworks
    puts "AddFiles-添加libraries文件引用"
    add_vendored_libraries
    # puts "AddFiles-添加resource_bundles文件"
    # add_resource_bundles
    puts "AddFiles-添加pch文件"
    add_prefix_header_file
    puts "AddFiles-修改spec文件"
    modify_spec_file
    puts "AddFiles-完成"
  end

  def prepare
    consumer = Pod::Specification::Consumer.new(@podspec,Pod::Platform.ios)
    @fileAccessor = Pod::Sandbox::FileAccessor.new(Pod::Sandbox::PathList.new(@root_path),consumer)

    @file_accessors = []
    @file_accessors << @fileAccessor

    subspec = @podspec.subspecs
    @podspec.subspecs.each do |subspec|
      consumer = Pod::Specification::Consumer.new(subspec,Pod::Platform.ios)
      file_accessor = Pod::Sandbox::FileAccessor.new(Pod::Sandbox::PathList.new(@root_path),consumer)
      @file_accessors << file_accessor
    end

    @target = @project.targets[0]

    puts "AddFiles-清空文件引用"
    @target.source_build_phase.clear
    @target.headers_build_phase.clear
    @target.frameworks_build_phase.clear
    @target.resources_build_phase.clear
    @target.copy_files_build_phases.each do |phase|
      phase.clear
    end
    clear_group
  end

  def add_source_files
    add_file_accessors_paths_to_group(:source_files)

    @file_accessors.each do |file_accessor|
      header_files = file_accessor.headers
      # source_files = file_accessor.arc_source_files - file_accessor.headers
      other_source_files = file_accessor.source_files.reject { |sf| Pod::Sandbox::FileAccessor::SOURCE_FILE_EXTENSIONS.include?(sf.extname) }
      # source_files = source_files - other_source_files
      # source_file_refs =  file_refs_for_path source_files

      {
          true => file_accessor.arc_source_files,
          false => file_accessor.non_arc_source_files
      }.each do |arc, files|
        source_files = files - header_files - other_source_files
        source_file_refs =  file_refs_for_path source_files
        if arc
          @target.add_file_references(source_file_refs)
        else
          @target.add_file_references(source_file_refs,"-fno-objc-arc")
        end

      end

      other_source_files_refs = file_refs_for_path other_source_files
      @target.add_file_references(other_source_files_refs)
    end
  end

  def add_header_file
    headers = @fileAccessor.headers
    public_headers = @fileAccessor.public_headers(true)
    private_headers = @fileAccessor.private_headers
    headers_refs = file_refs_for_path headers

    @target.add_file_references(headers_refs) do |build_file|
      file_ref = build_file.file_ref
      acl = if public_headers.include?(file_ref.real_path)
              'Public'
            elsif private_headers.include?(file_ref.real_path)
              'Private'
            else
              'Project'
            end

      build_file.settings ||= {}
      build_file.settings['ATTRIBUTES'] = [acl]
    end
  end

  def add_resources
    add_file_accessors_paths_to_group(:resources)

    target = @project.targets[0]

    resources_files = @fileAccessor.resources

    no_xcassets_files = resources_files.select do |rf|
      File.extname(rf.realpath) != '.xcassets'
    end

    resources_file_refs = file_refs_for_path no_xcassets_files

    target.add_resources(resources_file_refs)

    xcassets_files = resources_files.select do |rf|
      File.extname(rf.realpath) == '.xcassets'
    end

    xcassets_file_refs = file_refs_for_path xcassets_files

    if !xcassets_file_refs.empty?
      copy_resource_buildphase = copy_files_phase('Copy Xcassets', :resources)
      xcassets_file_refs.each do |xcassets|
        copy_resource_buildphase.add_file_reference(xcassets)
      end
    end
  end

  def add_vendored_frameworks

    add_file_accessors_paths_to_group(:vendored_frameworks)
    frameworks_files = @fileAccessor.vendored_frameworks
    frameworks_files_refs = file_refs_for_path(frameworks_files)

    frameworks_files_refs.each do |ref|
      @target.frameworks_build_phase.add_file_reference(ref, true)
    end

    if !frameworks_files_refs.empty?
      copy_framework_phase = copy_files_phase('Copy Frameworks', :frameworks)
      frameworks_files_refs.each do |ref|
        copy_framework_phase.add_file_reference(ref)
      end
    end

    search_paths = '$(inherited)'
    frameworks_files.each do |file|
      relative_dir = file.relative_path_from(@project.path.dirname).dirname
      search_paths = search_paths + " $(SRCROOT)/" + relative_dir.to_s
    end
    #
    @target.build_configurations.each do |c|
      c.build_settings['FRAMEWORK_SEARCH_PATHS'] = search_paths
    end
  end

  def add_vendored_libraries
    add_file_accessors_paths_to_group(:vendored_libraries)

    libraries_files = @fileAccessor.vendored_libraries
    libraries_files_refs = file_refs_for_path(libraries_files)

    libraries_files_refs.each do |ref|
      @target.frameworks_build_phase.add_file_reference(ref, true)
    end

    search_paths = '$(inherited)'
    libraries_files.each do |file|
      relative_dir = file.relative_path_from(@project.path.dirname).dirname
      search_paths = search_paths + " $(PROJECT_DIR)/" + relative_dir.to_s
    end
    
    @target.build_configurations.each do |c|
      c.build_settings['LIBRARY_SEARCH_PATHS'] = search_paths
    end
  end

  def add_resource_bundles
    add_file_accessors_paths_to_group(:resource_bundle_files)

    files_path = @fileAccessor.resource_bundle_files

    resource_bundles = @fileAccessor.resource_bundles

    resource_bundles.each_pair do |key, value|
      files_refs = file_refs_for_path(value)
      if !files_refs.empty?
        copy_phase = copy_files_phase("Copy Resource Bundle #{key}", :products_directory,key)
        files_refs.each do |ref|
          copy_phase.add_file_reference(ref)
        end
      end
    end
  end

  def add_prefix_header_file
    generator = Pod::Generator::PrefixHeader.new([@fileAccessor], Pod::Platform.ios)
    prefix_path = @root_path.join "#{@podspec.name}-prefix.pch"

    update_changed_file(generator, prefix_path)
    group = group_for_path_group(prefix_path , project.main_group)
    group.new_reference(prefix_path.realpath)

    @target.build_configurations.each do |c|
      relative_path = prefix_path.relative_path_from(@project.path.dirname)
      c.build_settings['GCC_PREFIX_HEADER'] = relative_path.to_s
    end

    File.open(prefix_path, 'a') { |f| f.puts "\n#ifndef DEBUG \n\t#define NSLog(...) \n#endif" }
  end

  #-----------------group----------------#
  def add_file_accessors_paths_to_group(file_accessor_key)
      @file_accessors.each do |file_accessor|
        paths = file_accessor.send(file_accessor_key)
        paths = allowable_project_paths(paths)
        paths.each do |path|
          group = group_for_path_group(path, project.main_group)
          file_ref = group.new_reference(path.realpath)
          @refs_by_absolute_path[path.realpath] = file_ref
        end
      end
  end

  def allowable_project_paths(paths)
    lproj_paths = Set.new
    lproj_paths_with_files = Set.new
    allowable_paths = paths.select do |path|
      path_str = path.to_s

      # We add the directory for a Core Data model, but not the items in it.
      next if path_str =~ /.*\.xcdatamodeld\/.+/i

      # We add the directory for a Core Data migration mapping, but not the items in it.
      next if path_str =~ /.*\.xcmappingmodel\/.+/i

      # We add the directory for an asset catalog, but not the items in it.
      next if path_str =~ /.*\.xcassets\/.+/i

      next if path_str =~ /.*\.xcodeproj\/.+/i

      if path_str =~ /\.lproj(\/|$)/i
        # If the element is an .lproj directory then save it and potentially
        # add it later if we don't find any contained items.
        if path_str =~ /\.lproj$/i && path.directory?
          lproj_paths << path
          next
        end

        # Collect the paths for the .lproj directories that contain files.
        lproj_path = /(^.*\.lproj)\/.*/i.match(path_str)[1]
        lproj_paths_with_files << Pathname(lproj_path)

        # Directories nested within an .lproj directory are added as file
        # system references so their contained items are not added directly.
        next if path.dirname.dirname == lproj_path
      end

      true
    end
    # Only add the path for the .lproj directories that do not have anything
    # within them added as well. This generally happens if the glob within the
    # resources directory was not a recursive glob.
    allowable_paths + lproj_paths.subtract(lproj_paths_with_files).to_a
  end

  def group_for_path_group(absolute_pathname,group)
    relative_base = @root_path
    relative_pathname = absolute_pathname.relative_path_from(relative_base)
    relative_dir = relative_pathname.dirname
    lproj_regex = /\.lproj/i

    path = relative_base

    relative_dir.each_filename do |name|
      break if name.to_s =~ lproj_regex
      next if name == '.'
      path += name
      group = group[name] || group.new_group(name, path)
    end

    if relative_dir.basename.to_s =~ lproj_regex
      group_name = variant_group_name(absolute_pathname)
      lproj_parent_dir = absolute_pathname.dirname.dirname
      group = @variant_groups_by_path_and_name[[lproj_parent_dir, group_name]] ||
          group.new_variant_group(group_name, lproj_parent_dir)
      @variant_groups_by_path_and_name[[lproj_parent_dir, group_name]] ||= group
    end

    group
  end

  def file_refs_for_path(file_paths)
    file_refs = file_paths.map do |file_path|
      @refs_by_absolute_path[file_path.realpath]
    end
    file_refs.delete(nil)
    file_refs
  end

  def variant_group_name(path)
    unless path.to_s.downcase.include?('.lproj/')
      raise ArgumentError, 'Only localized resources can be added to variant groups.'
    end

    # When using Base Internationalization for XIBs and Storyboards a strings
    # file is generated with the same name as the XIB/Storyboard in each .lproj
    # directory:
    #   Base.lproj/MyViewController.xib
    #   fr.lproj/MyViewController.strings
    #
    # In this scenario we want the variant group to be the same as the XIB or Storyboard.
    #
    # Base Internationalization: https://developer.apple.com/library/ios/documentation/MacOSX/Conceptual/BPInternational/InternationalizingYourUserInterface/InternationalizingYourUserInterface.html
    if path.extname.downcase == '.strings'
      %w(.xib .storyboard).each do |extension|
        possible_interface_file = path.dirname.dirname + 'Base.lproj' + path.basename.sub_ext(extension)
        return possible_interface_file.basename.to_s if possible_interface_file.exist?
      end
    end
    path.basename.to_s
  end

  def clear_group
    # project.main_group.clear

    group_names = ["Class","class","Resource","#{podspec.name}","#{@podspec.name}-prefix.pch"]
    main_group = project.main_group

    group_names.each do |name|
      group = main_group[name]
      if !group.nil?
        group.remove_from_project
      end
    end
  end

  def update_changed_file(generator, path)
    support_files_temp_dir = root_path.join('temp')
    if path.exist?
      generator.save_as(support_files_temp_dir)
      unless FileUtils.identical?(support_files_temp_dir, path)
        FileUtils.mv(support_files_temp_dir, path)
      end
    else
      generator.save_as(path)
    end
    support_files_temp_dir.rmtree if support_files_temp_dir.exist?
  end



  def modify_spec_file
    spec_hash = @podspec.to_hash
    vendored_frameworks_array = []
    vendored_frameworks_array << "#{spec_hash["name"]}.framework"

    if @fileAccessor.vendored_frameworks.count > 0
      vendored_frameworks_array << "#{spec_hash["name"]}.framework/Frameworks/*.framework"
    end
   spec_hash["vendored_frameworks"] = vendored_frameworks_array
   spec_hash.delete("default_subspecs")
  
    new_spec = Pod::Specification.from_hash(spec_hash)
    spec_json = new_spec.to_pretty_json
    spec_json_file = File.new(@root_path.join("#{@podspec.name}.podspec.json").to_s, "w+")
    spec_json_file.puts(spec_json)
    puts spec_json
    spec_json_file.close
    # 如果原来有podspec，删除掉
    defaultSpecPath = @root_path.join("#{@podspec.name}.podspec")
    if File::exist?(defaultSpecPath)
      File.delete(defaultSpecPath)
    end
  end

  def copy_files_phase(name, symbol_dst_subfolder, dst_path = nil)
    copy_files_phases = @target.copy_files_build_phases.select do |phase|
      phase.name == name
    end
    copy_files_phase = copy_files_phases.first  || @target.new_copy_files_build_phase(name)
    copy_files_phase.symbol_dst_subfolder_spec = symbol_dst_subfolder

    unless dst_path.nil?
      copy_files_phase.dst_path = dst_path
    end

    copy_files_phase
  end

end
