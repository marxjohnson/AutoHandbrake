#!/usr/bin/env ruby

require 'optparse'
require 'awesome_print'
require 'duration'
require 'highline/import'

class AutoHB 
    def initialize
        @options = {
	    :device => nil,
	    :output => Dir.home+"/Videos",
	    :subtitles => nil,
	    :default_subtitles => "eng",
	    :subtitles_forced => true, 
	    :subtitles_burned => true, 
	    :title => nil,
	    :default_title => nil,
	    :season => nil,
	    :default_season => nil,
	    :first_episode => nil,
	    :default_first_episode => "1",
	    :eject => true,
	    :preset => "Normal",
            :min_duration => nil
	}
	self.detect_device
        @curTitle = Title.new
        @titles = Array.new
        @disc_title = ''
        @contentType = nil
        @episode_groups = Array.new
	@titles_to_rip = Array.new
	@subtitle_to_rip = nil
	@queue = Array.new

        self.parse_options
	self.verify_device
    end

    def detect_device
	@options[:device] = Dir["/dev/dvd*"].pop
        if @options[:device].nil?
            @options[:device] = Dir["/dev/cdrom*"].pop
        end
    end

    def verify_device
	if @options[:device].nil?
	    puts "No DVD drive was found, and none specified. Exiting."
	    exit
	end
    end

    def parse_options
        optparse = OptionParser.new do |opts|
            opts.banner = "Usage: autohb [options]"
	    opts.on('-i', "--input DEVICE", "Input device (DVD or Blu-Ray drive) [Default: detect]") do |device|
	       @options[:device] = device
	    end	       
	    opts.on('-o', "--output DIR", "Base directory for output files [Default: ~/Videos]") do |device|
	       @options[:output] = device
	    end	       
            opts.on('--file FILE', 'example input file') do |file|
                @options[:file] = file
            end
	    opts.on('-S', '--subtitles LANG', "Subtitle language (3 letter code, don\'t ask agaain)") do |lang|
		@options[:subtitles] = lang
	    end
	    opts.on('-s', '--default-subtitles LANG', "Subtitle language (3 letter code) [default: eng]") do |lang|
		@options[:default_subtitles] = lang
	    end
	    opts.on('-f', '--[no-]subtitles-forced', "Only include forced subtitles [default: true]") do |f|
		@options[:subtitles_forced] = f
	    end
	    opts.on('-b', '--[no-]subtitles-burned', "Burn-in subtitles [default: true]") do |b|
		@options[:subtitles_burned] = b
	    end
	    opts.on('-T', '--title TITLE', "Title for file naming (won't ask again)") do |title|
		@options[:title] = title
	    end
	    opts.on('-t', '--default-title TITLE', "Default title for file naming [default: read from disc]") do |title|
		@options[:default_title] = title
	    end
	    opts.on('-S', '--season NUMBER', "Season number for file naming (won't ask again)") do |season|
		@options[:season] = season
	    end
	    opts.on('-s', '--default-season NUMBER', "Default season number for file naming [default: read from disc or ask]") do |season|
		@options[:default_season] = season
	    end
	    opts.on('-E', '--episode NUMBER', "First episode number for file naming (won't ask again)") do |episode|
		@options[:first_episode] = episode
	    end
	    opts.on('-e', '--default-episode EPISODE', "Default first episode number for file naming [default: 1]") do |episode|
		@options[:default_episode] = episode
	    end
	    opts.on('--preset PRESET', "Handbrake preset to use (list with `HandBrakeCLI -z`) [default: Normal]") do |preset|
		@options[:preset] = preset
	    end
	    opts.on('--[no-]eject', "Eject disc when done [default: true]") do |eject|
		@options[:eject] = eject
	    end
	    opts.on('-m', '--min-duration [DURATION]', "Min duration") do |duration|
		@options[:min_duration] = duration
	    end
        end

        optparse.parse!

    end

    def append_title
        if @curTitle.number
            @titles[@curTitle.number.to_i] = @curTitle
            @curTitle = Title.new
        end
    end

    def scan_disc
	if @options[:file]
	    f = File.open @options[:file] 
	    f.read
	else
            min_duration = ""
            if @options[:min_duration]
                min_duration = " --min-duration #{@options[:min_duration]}"
            end
	    `HandBrakeCLI -i #{@options[:device]}#{min_duration} -t 0 --scan 2>&1`
	end
    end

    def parse_disc_title(line) 
	parts = line.split
	rawtitle = parts.pop
	titleparts = Array.new
	if rawtitle.include? "SEASON"
	    titleparts = rawtitle.split "SEASON"
	    title = titleparts[0]
	elsif rawtitle.include? "SERIES"
	    titleparts = rawtitle.split "SERIES"
	    title = titleparts[0]
	else
	    title = rawtitle
	end

	if titleparts != Array.new
	    @disc_season = titleparts[1].match(/\d+/)[0]
	end

	@disc_title = title.split("_").map {|words| words.capitalize}.join(" ").strip
    end

    def parse_duration(duration)
        parts = duration.split ':'
	Duration.new :hours => parts[0].to_i, :minutes => parts[1].to_i, :seconds => parts[2].to_i
    end

    def parse_output(data)
        isin = ParseFlags.new
        data.each_line do |line|
            if !line.include? '+'
		if line.include? "DVD Title:"
		    self.parse_disc_title line
		else
		    next
		end
            end
            parts = line.strip.split
            if line.start_with? "+"
                self.append_title
                @curTitle.number = line.match(/title (\d+):/)[1]
                isin.meta = true;
            elsif line.start_with? "  +"
                case parts[1]
                when 'duration:'
                    @curTitle.duration = self.parse_duration parts[2]
                when 'Main'
                    @curTitle.ismain = true
                when 'angle(s)'
                    @curTitle.angles = parts[3].to_i
                when 'chapters:'
                    isin.chapters = true
                when 'audio'
                    isin.audios = true
                when 'subtitle'
                    isin.subtitles = true
                end
            elsif line.start_with? "    +"
                if isin.chapters
                    number = parts[1].sub(':', '').to_i
                    duration = self.parse_duration parts[7]
                    chapter = Chapter.new number, duration
                    @curTitle.chapters[number] = chapter
                elsif isin.audios
                    number = parts[1].sub(',', '').to_i
                    lang = parts[2]
                    mode = nil
                    description = nil
                    line.scan /\((.+?)\)/ do |m|
                        if m[0].end_with? 'ch'
                            mode = m[0]
                        elsif m[0] != 'AC3' and !m[0].start_with? 'iso'
                            description = m[0]
                        end
                    end
                    @curTitle.audios[number] = Audio.new number, lang, mode, description
                elsif isin.subtitles
                    number = parts[1].sub(',', '').to_i
                    lang = parts[2]
                   @curTitle.subtitles[number] = Subtitle.new number, lang
                end
            end
        end
        self.append_title
    end
    
    def find_episode_groups
        durations = Hash.new
        @main = nil
        mainduration = nil
        cumulative = Duration.new
        previous = nil
        episode_threshold = 140
        total_threshold = 20
        @episode_groups = Array.new
        group = nil
        @titles.each do |title|
            if !title.nil?
                if title.ismain
                    @main = title.number
                    mainduration = title.duration
                end
                durations[title.number] = title.duration
            end
        end
        durations = durations.sort {|a,b|
          b[1] <=> a[1] 
        }
        durations.each do |number,duration|
            if duration != mainduration
                if cumulative == Duration.new
                    cumulative = duration
                    group = Array[Hash[:number => number, :duration => duration]]
                else
                    if !group.empty? and duration < group[0][:duration]-episode_threshold
			self.push_group cumulative, mainduration, total_threshold, group
                        group = Array.new
                        cumulative = Duration.new
                    end
                    cumulative = cumulative+duration
                    group.push Hash[:number => number, :duration => duration]
                end
            end
        end
	self.push_group cumulative, mainduration, total_threshold, group
        ap @episode_groups
    end

    def push_group cumulative, maintime, total_threshold, group
        if cumulative >= maintime-total_threshold and cumulative <= maintime+total_threshold
            @episode_groups.push group.sort {|a,b| a[:number] <=> b[:number]}
        end
    end

    def confirm_episode_group group
	message = "One Episde Group Found:\n"
	message += self.get_group_listing group
	message += "Rip these titles? [Y/n]:"
	a = ask(message) do |q| 
	    q.default = "Y"
	    q.validate = /^[YNyn]$/
	    q.responses[:not_valid] = "Enter Y or N "
	end
	a.index(/^[nN]$/).nil?
    end

    def select_episode_group
	message = "Multiple possible episode groups found:\n"
	@episode_groups.each do |index,group|
	    message += "Group #{index}:\n"
	    message += self.get_group_listing group
	end
	options = @episode_groups.each_index {|x| x}
	message += "Which group do you want to rip? (n for none) [#{options}]\n"
	a = ask(message) do |q|
	    q.default = 0
	    q.validate = /^[#{options}nN]$/
	    q.responses[:not_valid] = "Enter #{options.split("").join(",")} or N "
	end
	if a.index(/^[nN]$/).nil?
	    return a.to_i
	else
	    return nil
	end
    end

    def get_group_listing group
	listing = ""
	group.each do |episode|
	    listing += self.get_title_listing episode[:number], episode[:duration]
	end
	listing
    end

    def get_title_listing number, duration
	ismain = ""
	if number == @main
	    ismain = "(Main Feature)"
	end
	"Title #{number} [%02d:%02d:%02d] #{ismain}\n" % [duration.hours, duration.minutes, duration.seconds]
    end
    	

    def confirm_main_title
	maintime = @titles[@main.to_i].duration
	message = "Single main feature found:\n"
	message += "Title #{@main} [#{maintime}]\n"
	message += "Rip this feature? [Y/n]"
	a = ask(message) do |q|
	    q.default = "Y"
	    q.validate = /^[YyNn]$/
	    q.responses[:not_valid] = "Enter Y or N"
	end
	a.index(/^[nN]$/).nil?
    end

    def rip_episode_group group
	group.each do |episode|
	    @titles_to_rip.push episode[:number]
	end
    end

    def rip_main_title
	@titles_to_rip.push @main
    end

    def select_titles
	message = "No titles selected. The following titles were found:\n"
	numbers = Array.new
	@titles.each do |title|
	    if !title.nil?
		message += self.get_title_listing title.number, title.duration
		numbers.push title.number
	    end
	end
	message += "Enter the title numbers to rip, separated by commas (e.g. enter \"2,3,5\" for titles 2, 3 and 5), or q to quit\n"
	a = ask(message) do |q|
	    q.validate = /^(q|((#{numbers.join "|"}),?)+)$/ 
	    q.responses[:not_valid] = "Enter a list of numbers from #{numbers.join ","} or q"
	end
	if a == "q"
	    exit
	else
	    @titles_to_rip = a.split ","
	end
    end

    def add_subtitles?
	message = "Add subtitles with default settings? (Y/n)\n"
	lang = @options[:default_subtitles]
	forced = @options[:subtitles_forced] ? "yes" : "no"
	burned = @options[:subtitles_burned] ? "yes" : "no"
	message += "(Language #{lang}, Forced Only: #{forced}, Burned in: #{burned}) \n"
	a = ask(message) do |q|
	    q.validate = /^[YyNn]$/
	    q.default = "y"
	    q.responses[:not_valid] = "Enter Y or N"
	end
	if a.index(/^[nN]$/).nil?
	    @subtitle_to_rip = "scan -N #{@options[:default_subtitles]}"
	else
	    return false
	end
    end

    def get_subtitle_track lang
	if lang == "scan"
	    return lang
	end
	subtitles = @titles[@titles_to_rip.pop].subtitles
	subtitles.each do |subtitle|
	    if subtitle.lang == lang
		return subtitle.number
	    end
	end
    end

    def get_subtitles
	subtitles = @titles[@titles_to_rip.pop.to_i].subtitles
	message = "The following subtitle tracks were found:\n"
	default = nil
	numbers = Array.new
	subtitles.each do |subtitle|
	    if subtitle.nil?
	      next
	    end
	    message += "#{subtitle.number}: #{subtitle.lang}\n"
	    if default.nil? and subtitle.lang == @options[:default_subtitle]
		default = subtitle.number
	    end
	    numbers.push subtitle.number
	end
	message += "Enter the number of the track you want to rip (n for none)"
	if !default.nil?
	    message += " [default: #{default}]"
	end
	message += ":\n"
	a = ask(message) do |q|
	    if !default.nil?
		q.default = default
	    end
	    q.validate = /^([nN]|(#{numbers.join "|"}))$/ 
	    q.responses[:not_valid] = "Enter a numbers from #{numbers.join ","} or N"
	end
	if a.index(/^[nN]$/).nil?
	    return a
	else
	    return nil
	end
    end

    def get_title
	if @options[:default_title].nil?
	    default = @disc_title
	else
	    default = @options[:default_title]
	end
	message = "Enter the title for file and folder naming"
	ask(message) do |q|
	    q.default = default
	    q.validate = /^[A-Za-z_0-9][A-Za-z_0-9\-. ]*$/
	    q.responses[:not_valid] = "Enter a valid filename (Letters, numbers, _ - or ., not starting with - or .)"
	end
    end

    def get_season
	message = "Enter season number for episode naming (n for none)"
	a = ask(message) do |q|
	    q.default = @options[:default_season]
	    q.validate = /^([0-9]+|[nN])$/
	    q.responses[:not_valid] = "Enter a number, or N for none"
	end
	if a.index(/^[nN]$/).nil?
	    return a
	else
	    return nil
	end
    end

    def get_first_episode
	message = "Enter first episode number for episode naming"
	a = ask(message) { |q|
	    q.default = @options[:default_first_episode]
	    q.validate = /^[0-9]+$/
	    q.responses[:no_valid] = "Enter a number"
	}
    end

    def main
        begin
            data = self.scan_disc
            self.parse_output data
            self.find_episode_groups
            if @episode_groups.length > 0
                if @episode_groups.length > 1
                    # Display groups and prompt for choice
		    group = self.select_episode_group
		    if group.nil?
			if self.confirm_main_title
			    self.rip_main_title
			end
		    else
			self.rip_episode_group group
		    end 
                else
                    # Display group and confirm
		    group = @episode_groups.pop
		    if self.confirm_episode_group group
			self.rip_episode_group group
		    end
                end
            else
                # Display main title and confirm
		if self.confirm_main_title
		    self.rip_main_title
		end
            end
	    
	    if @titles_to_rip.length == 0
		self.select_titles
	    end

	    if @titles_to_rip.length == 0
		puts "No titles selected, exiting\n"
		exit
	    end

	    if @options[:subtitles].nil?
		if !self.add_subtitles?
		    @subtitle_to_rip = self.get_subtitles
		end
	    else
		@subtitle_to_rip = self.get_subtitle_track @options[:subtitles]
	    end

	    if @options[:title].nil?
		@options[:title] = self.get_title
	    end

	    if @titles_to_rip.length > 1 and @options[:season].nil?
		@options[:season] = self.get_season
	    end

	    if @titles_to_rip.length > 1 and @options[:first_episode].nil?
		@options[:first_episode] = self.get_first_episode
	    end
            
            # Build commands to rip titles
	    episode_number = @options[:first_episode].to_i
	    subtitle = ""
	    if !@subtitle_to_rip.nil?
		subtitle += "--subtitle #{@subtitle_to_rip}"
		if @options[:subtitles_forced]
		    subtitle += " -F"
		end
		if @options[:subtitles_burned]
		    subtitle += " --subtitle-burn"
		end
	    end
	    @titles_to_rip.each do |title_number|
		title = @titles[title_number.to_i]
		episode = " "
		if !@options[:season].nil?
		    episode += "S%02d" % @options[:season]
		end
		if !@options[:first_episode].nil?
		    episode += "E%02d" % episode_number
		    episode_number += 1
		end
		if episode == " "
		    episode = ""
		end
		
		folder_name = "#{@options[:output]}/#{@options[:title]}"
		if !File.exists? folder_name
		    Dir.mkdir folder_name
		end
		filename = "#{folder_name}/#{@options[:title]}#{episode}.mp4"
		command = "HandBrakeCLI -i #{@options[:device]} -o \"#{filename}\" --preset=\"#{@options[:preset]}\" -t #{title_number} #{subtitle}"
		@queue.push command
	    end
	    # Run Commands, yay!
	    @queue.each do |command|
		puts command
	    end
        end
    end
end

class Title
    attr_accessor :number, :ismain, :duration, :size, :chapters, :audios, :subtitles, :angles

    def initialize
        @number = nil
        @ismain = false
        @duration = nil
        @size = nil
        @chapters = Array.new
        @audios = Array.new
        @subtitles = Array.new
        @angles = 1
    end
end

class Chapter
    attr_accessor :number, :duration

    def initialize(number, duration)
        @number = number
        @duration = duration
    end
end

class Audio
    attr_accessor :number, :lang, :description, :mode

    def initialize(number, lang, mode, description='')
        @number = number
        @lang = lang
        @mode = mode
        @description = description
    end
end

class Subtitle
    attr_accessor :number, :lang
    
    def initialize(number, lang)
        @number = number
        @lang = lang
    end
end

class ParseFlags
    attr_reader :meta, :chapters, :audios, :subtitles

    def initialize
        self.setfalse
    end

    def setfalse
        @meta = false
        @chapters = false
        @audios = false
        @subtitles = false
    end

    def meta=(val)
        self.setfalse
        @meta = val
    end

    def chapters=(val)
        self.setfalse
        @chapters = val
    end
    
    def audios=(val)
        self.setfalse
        @audios = val
    end

    def subtitles=(val)
        self.setfalse
        @subtitles = val
    end
end

program = AutoHB.new()
program.main
