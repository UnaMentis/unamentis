#!/usr/bin/env ruby
# xcode-project-helper.rb
# Helper script for programmatically modifying Xcode project files
# Uses the xcodeproj gem (same as CocoaPods/fastlane)

# Add user gem directory to load path (for --user-install gems)
user_gem_dir = File.expand_path('~/.gem/ruby')
if Dir.exist?(user_gem_dir)
  Dir.glob("#{user_gem_dir}/*/gems/*/lib").each { |path| $LOAD_PATH.unshift(path) }
end

require 'xcodeproj'
require 'pathname'
require 'fileutils'
require 'json'

class XcodeProjectHelper
  def initialize(project_path)
    @project_path = project_path
    @project = Xcodeproj::Project.open(project_path)
    @main_target = @project.targets.find { |t| t.product_type == 'com.apple.product-type.application' }
  end

  # Add Swift source files to the project
  def add_source_files(file_paths, options = {})
    target = resolve_target(options[:target])
    results = []

    file_paths.each do |file_path|
      result = add_single_source_file(file_path, target, options)
      results << result
    end

    @project.save
    results
  end

  # Resolve target from name or return default
  def resolve_target(target_option)
    return @main_target if target_option.nil?
    return target_option unless target_option.is_a?(String)

    # Look up target by name
    found = @project.targets.find { |t| t.name == target_option }
    unless found
      warn "Warning: Target '#{target_option}' not found; falling back to '#{@main_target.name}'"
    end
    found || @main_target
  end

  # Add a framework or xcframework
  def add_framework(framework_path, options = {})
    target = resolve_target(options[:target])
    embed = options[:embed] || false

    abs_path = File.expand_path(framework_path)

    unless File.exist?(abs_path)
      return { success: false, error: "Framework not found: #{abs_path}" }
    end

    # Check if already added
    existing = find_file_reference(framework_path)
    if existing
      # Framework exists - but check if we need to add embedding
      if embed
        # Check if already embedded
        embed_phase = target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks }
        already_embedded = embed_phase && embed_phase.files.any? { |f| f.file_ref == existing }

        unless already_embedded
          # Framework is linked but not embedded - add embedding
          unless embed_phase
            embed_phase = target.new_copy_files_build_phase('Embed Frameworks')
            embed_phase.symbol_dst_subfolder_spec = :frameworks
          end
          embed_phase.add_file_reference(existing)
          @project.save
          return { success: true, path: framework_path, embedded: true, action: 'added_embedding' }
        end

        return { success: false, error: "Framework already in project and embedded: #{framework_path}" }
      end

      return { success: false, error: "Framework already in project: #{framework_path}" }
    end

    # Find or create Frameworks group
    frameworks_group = @project.main_group.find_subpath('Frameworks', true) ||
                       @project.main_group.new_group('Frameworks')

    # Add file reference
    file_ref = frameworks_group.new_reference(abs_path)
    file_ref.source_tree = '<group>'

    # Calculate relative path from project
    project_dir = File.dirname(@project_path)
    rel_path = Pathname.new(abs_path).relative_path_from(Pathname.new(project_dir)).to_s
    file_ref.path = rel_path

    # Add to frameworks build phase (Link Binary With Libraries)
    target.frameworks_build_phase.add_file_reference(file_ref)

    # Optionally embed the framework
    if embed
      embed_phase = target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks }
      unless embed_phase
        embed_phase = target.new_copy_files_build_phase('Embed Frameworks')
        embed_phase.symbol_dst_subfolder_spec = :frameworks
      end
      embed_phase.add_file_reference(file_ref)
    end

    @project.save
    { success: true, path: framework_path, embedded: embed }
  end

  # List all source files in the project
  def list_source_files
    files = []
    @project.files.each do |file|
      next unless file.path&.end_with?('.swift')
      files << {
        path: file.path,
        name: file.name,
        source_tree: file.source_tree
      }
    end
    files.sort_by { |f| f[:path] || '' }
  end

  # Verify project integrity
  def verify
    issues = []

    # Check all file references point to existing files
    project_dir = File.dirname(@project_path)
    @project.files.each do |file|
      next unless file.path

      full_path = case file.source_tree
                  when '<group>'
                    File.join(project_dir, file.path)
                  when 'SOURCE_ROOT'
                    File.join(project_dir, file.path)
                  when '<absolute>'
                    file.path
                  else
                    File.join(project_dir, file.path)
                  end

      unless File.exist?(full_path)
        issues << { type: 'missing_file', path: file.path, expected: full_path }
      end
    end

    # Check for duplicate file references
    paths = @project.files.map(&:path).compact
    duplicates = paths.group_by { |p| p }.select { |_, v| v.size > 1 }.keys
    duplicates.each do |dup|
      issues << { type: 'duplicate_reference', path: dup }
    end

    # Check all Swift files are in build phase
    @main_target.source_build_phase.files.map(&:file_ref).compact.map(&:path)

    {
      valid: issues.empty?,
      issues: issues,
      file_count: @project.files.count,
      target_count: @project.targets.count
    }
  end

  private

  def add_single_source_file(file_path, target, options)
    abs_path = File.expand_path(file_path)

    unless File.exist?(abs_path)
      return { success: false, path: file_path, error: "File not found: #{abs_path}" }
    end

    # Check if already in project
    existing = find_file_reference(file_path)
    if existing
      return { success: false, path: file_path, error: "File already in project" }
    end

    # Determine the group based on file path
    group = find_or_create_group_for_path(file_path, options[:group])

    # Add file reference
    file_ref = group.new_reference(abs_path)
    file_ref.source_tree = '<group>'

    # Set relative path
    project_dir = File.expand_path(File.dirname(@project_path))
    rel_path = Pathname.new(abs_path).relative_path_from(Pathname.new(project_dir)).to_s
    file_ref.path = rel_path

    # Add to source build phase
    target.source_build_phase.add_file_reference(file_ref)

    { success: true, path: file_path, group: group.display_name }
  end

  def find_file_reference(file_path)
    basename = File.basename(file_path)
    @project.files.find { |f| f.path&.end_with?(basename) }
  end

  def find_or_create_group_for_path(file_path, explicit_group = nil)
    return @project.main_group.find_subpath(explicit_group, true) if explicit_group

    # Parse the file path to determine group
    parts = file_path.split('/')

    # Find the main source directory (UnaMentis, UnaMentisTests, etc.)
    source_dir_index = parts.index { |p| p == 'UnaMentis' || p == 'UnaMentisTests' || p == 'UnaMentisUITests' }

    return @project.main_group unless source_dir_index

    # Build the group path
    group_parts = parts[source_dir_index...-1]  # Exclude the filename

    current_group = @project.main_group
    group_parts.each do |part|
      existing = current_group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == part }
      current_group = existing || current_group.new_group(part)
    end

    current_group
  end
end

# CLI interface
if __FILE__ == $0
  require 'optparse'

  options = {
    project: 'UnaMentis.xcodeproj',
    embed: false
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} <command> [options] [files...]"

    opts.on('-p', '--project PATH', 'Project file path') { |v| options[:project] = v }
    opts.on('-t', '--target NAME', 'Target name') { |v| options[:target] = v }
    opts.on('-g', '--group PATH', 'Group path') { |v| options[:group] = v }
    opts.on('--embed', 'Embed framework') { options[:embed] = true }
    opts.on('--json', 'Output JSON') { options[:json] = true }
  end

  begin
    parser.parse!
  rescue OptionParser::InvalidOption => e
    STDERR.puts e.message
    STDERR.puts parser
    exit 1
  end

  command = ARGV.shift

  unless command
    puts parser
    exit 1
  end

  # Find project file
  project_path = if File.exist?(options[:project])
                   options[:project]
                 elsif File.exist?(File.join(Dir.pwd, options[:project]))
                   File.join(Dir.pwd, options[:project])
                 else
                   STDERR.puts "Project not found: #{options[:project]}"
                   exit 1
                 end

  helper = XcodeProjectHelper.new(project_path)

  case command
  when 'add-files', 'add-source'
    if ARGV.empty?
      STDERR.puts "No files specified"
      exit 1
    end
    results = helper.add_source_files(ARGV, options)
    if options[:json]
      puts JSON.pretty_generate(results)
    else
      results.each do |r|
        if r[:success]
          puts "Added: #{r[:path]} -> #{r[:group]}"
        else
          puts "Failed: #{r[:path]} - #{r[:error]}"
        end
      end
    end

  when 'add-framework'
    if ARGV.empty?
      STDERR.puts "No framework specified"
      exit 1
    end
    result = helper.add_framework(ARGV.first, options)
    if options[:json]
      puts JSON.pretty_generate(result)
    else
      if result[:success]
        embed_status = result[:embedded] ? ' (embedded)' : ''
        action = result[:action] == 'added_embedding' ? 'Added embedding to' : 'Added framework:'
        puts "#{action} #{result[:path]}#{embed_status}"
      else
        puts "Failed: #{result[:error]}"
      end
    end

  when 'list-files', 'list'
    files = helper.list_source_files
    if options[:json]
      puts JSON.pretty_generate(files)
    else
      files.each { |f| puts f[:path] }
    end

  when 'verify'
    result = helper.verify
    if options[:json]
      puts JSON.pretty_generate(result)
    else
      if result[:valid]
        puts "Project valid: #{result[:file_count]} files, #{result[:target_count]} targets"
      else
        puts "Project has issues:"
        result[:issues].each do |issue|
          puts "  #{issue[:type]}: #{issue[:path]}"
        end
      end
    end

  else
    STDERR.puts "Unknown command: #{command}"
    STDERR.puts "Commands: add-files, add-framework, list-files, verify"
    exit 1
  end
end
