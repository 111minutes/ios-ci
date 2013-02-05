require "rubygems"
require "pp"

class XBuildOutputParser
	attr_accessor :io

	def parse_step(string)
		result = {}
		has_error = string.include?("error:")
		
		first_line = string.lines.to_a[0].strip
		cmd = first_line.split(" ").first.strip
		result[:type] = cmd
		result[:arg] = "#{first_line.gsub(cmd, '').strip}"
		if has_error
			buffer = []
			error_matched = false
			string.lines.each do |line|
				if not error_matched and line.include? "error:"
					error_matched = true
				end
				if error_matched
					buffer << line
				end
			end
			result[:errors] = buffer.join("")
		end
 		result
	end

	def initialize(io)
		self.io = io
	end

	def parse
		puts "Building"
		buffer = ""
		steps = []
		self.io.each do |line|
			buffer.strip!
			if line == "\n" and not buffer.empty? and buffer != nil
				steps << parse_step(buffer)
				buffer = ""
				printf "-"
			else
				buffer << line
			end
		end
		puts ""
		errors = steps.select {|step| step[:errors] and step[:type] != "CopyPNGFile" and step[:type] != "While" }
		
		if errors.empty?
			code_sign = steps.select {|step| step[:type] == "CodeSign" }.last
			puts "Done!"
			return "#{Dir.pwd}/#{code_sign[:arg]}"
		else 
			puts "Errors:"	
			errors.each do |error|
				puts "\nAction type:#{error[:type]}"
				puts "Log:\n #{error[:errors]}"
			end
			return false
		end
	end
end

class XBuildCommand	
	attr_accessor :workspace
	attr_accessor :scheme
	attr_accessor :configuration
	attr_accessor :build_action
	attr_accessor :obj_root
	attr_accessor :sym_root
	attr_accessor :before_build
	attr_accessor :after_build

	def self.run(&config_block)
		cmd = self.new
		config_block.call(cmd)
		cmd.run
	end

	def run
		self.before_build.call if self.before_build

		cmd = "xcodebuild"
		params = []

		params << "-workspace #{self.workspace}.xcworkspace" if self.workspace
		params << "-scheme #{self.scheme}" if self.scheme
		params << "-configuration #{self.configuration}" if self.configuration
		params << "#{self.build_action}" if self.build_action
		pwd = Dir.pwd
		params << "OBJROOT=#{pwd}/#{self.obj_root}" if self.obj_root
		params << "SYMROOT=#{pwd}/#{self.sym_root}" if self.sym_root

		cmd = "#{cmd} #{params.join(' ')}"

		parser = XBuildOutputParser.new(IO.popen(cmd))

		app_path = parser.parse

		if app_path
			self.after_build.call(app_path) if self.after_build	
		end
	end
end

class XPackageCommand
	
	def self.run(path)
		self.new.run(path)
	end

	def run(path)

		path = path.scan(/^\/[\/\w-]+\/\w+\.app/).first

		basename = File.basename(path).gsub("app", "ipa")
		ipa_path = "#{Dir.pwd}/#{basename}"
		puts "PackageApplication at path #{path}"
		
		cmd = "xcrun"
		params = []

		params << "--sdk iphoneos"
		params << "PackageApplication"
		params << "-v \"#{path}\""
		params << "-o \"#{ipa_path}\""
		
		output = `#{cmd} #{params.join(' ')}`
		
		puts "Result: #{output.scan(/Results at '(.*)'/).flatten.last}"
	end
end

XBuildCommand.run do |cmd|
	cmd.before_build = Proc.new do 
		`rm -rf build`
		if File.exists?("Pods")
			system "pod update"  
		else 
			system "pod install"
		end
	end

	cmd.workspace = "FNConnect"
	cmd.scheme = "FNConnect"
	cmd.configuration = "Release"
	cmd.build_action = "build"
	cmd.obj_root = "build"
	cmd.sym_root = "build"
	cmd.after_build = Proc.new do |path|
		XPackageCommand.run path
	end
end