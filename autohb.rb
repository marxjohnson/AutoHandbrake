#!/usr/bin/env ruby

require 'optparse'
require 'duration'
require 'mattscilipoti-rdialog'

class AutoHB
    def initialize
        @options = {
            :device => nil,
            :directory => nil,
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
            :min_duration => nil,
            :extension => "mp4",
            :no_flatpak => false
        }
        @curTitle = Title.new
        @titles = Array.new
        @disc_title = ''
        @contentType = nil
        @episode_groups = Array.new
        @titles_to_rip = Array.new
        @subtitle_to_rip = nil
        @queue = Array.new
        @dialog = RDialog.new
        if File.exist? '/usr/bin/gdialog'
            @dialog.path_to_dialog = '/usr/bin/gdialog'
        end
        @dialog.backtitle = "Auto Handbrake"

        self.parse_options
        begin
            hb = `HandBrakeCLI --version 2>/dev/null`
        rescue
            hb = ''
        end
        begin
            flatpak = `flatpak run --command=HandBrakeCLI fr.handbrake.ghb --version 2>/dev/null`
        rescue
            flatpak = ''
        end
        if !@options[:no_flatpak] and !flatpak.empty?
            @command = 'flatpak run --command=HandBrakeCLI fr.handbrake.ghb'
        elsif !hb.empty?
            @command = 'HandBrakeCLI'
        else
            @dialog.msgbox 'HandBrakeCLI could not be found. Please install it.'
            exit
        end

        if @options[:device].nil? and @options[:directory].nil?
            validsource = false
            default = self.detect_device
        
            while !validsource
                question = 'Enter drive or directory:'
                answer = @dialog.inputbox(question, 0, 0, "\"#{default}\"").strip
                if File.blockdev?(answer)
                    @options[:device] = answer
                    validsource = true
                elsif File.directory?(answer)
                    @options[:directory] = answer
                    validsource = true
                else
                    default = answer
                end
            end
        end

        if @options[:directory].nil?
            self.verify_device
        else
            self.verify_directory
            @options[:eject] = false
        end
    end

    def detect_device
        device = Dir["/dev/dvd*"].pop
        if device.nil?
            device = Dir["/dev/cdrom*"].pop
        end
        return device
    end

    def verify_device
        if @options[:device].nil?
            @dialog.msgbox "No DVD drive was found, and none specified. Exiting."
            exit
        end
    end

    def verify_directory
        if !Dir.exist? @options[:directory]
            @dialog.msgbox "Specified directory was not found."
            exit
        end
        files = Array.new
        Dir.new(@options[:directory]).each do |filename|
            path = @options[:directory] + '/' + filename
            if File.file?(path) && File.readable?(path)
                mime_type = `file --mime -b "#{path}"`.chomp
                if mime_type.start_with? 'video/'
                    files.push filename
                end
            end
        end

        if files.empty?
            @dialog.msgbox "No videos found in directory. Exiting."
        end

        @files = files
    end

    def parse_options
        optparse = OptionParser.new do |opts|
            opts.banner = "Usage: autohb [options]"
            opts.on('-i', "--input DEVICE", "Input device (DVD or Blu-Ray drive) [Default: detect]") do |device|
            @options[:device] = device
            end
            opts.on('-d', "--directory DIR", "Input directory containing videos to convert") do |directory|
                @options[:directory] = directory
            end
            opts.on('-o', "--output DIR", "Base directory for output files [Default: ~/Videos]") do |output|
            @options[:output] = output
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
            opts.on('--preset PRESET', "Handbrake preset to use (list with `HandBrakeCLI -z`), or custom preset exported from Handbrake GUI as a JSON file [default: Normal]") do |preset|
                @options[:preset] = preset
            end
            opts.on('--[no-]eject', "Eject disc when done [default: true]") do |eject|
                @options[:eject] = eject
            end
            opts.on('-m', '--min-duration [DURATION]', "Min duration") do |duration|
                @options[:min_duration] = duration
            end
            opts.on('--extension EXTENSION', "File extension for output file [default: mp4]") do |extension|
                @options[:extension] = extension
            end
            opts.on('--no-flatpak', "Dont use the Flatpak version of HandBrakeCLI, even if its installed.") do |no_flatpak|
                @options[:no_flatpak] = true
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

    def scan(input)
        if @options[:file]
            f = File.open @options[:file]
            f.read
        else
            min_duration = ""
            if @options[:min_duration]
                min_duration = " --min-duration #{@options[:min_duration]}"
            end
            `#{@command} -i "#{input}"#{min_duration} -t 0 --scan 2>&1`
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
        parts = duration.to_s.split ':'
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
                    duration = self.parse_duration parts[3]
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
        longest_title = nil
        @titles.each do |title|
            if !title.nil?
                if title.ismain
                    @main = title.number
                    mainduration = title.duration
                else
                    if title.duration > durations[longest_title]
                        longest_title = title.number
                    end
                end
                durations[title.number] = title.duration
            end
        end
        if @main.nil?
            @main = longest_title
            mainduration = durations[@main]
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
    end

    def push_group cumulative, maintime, total_threshold, group
        begin
            if cumulative >= maintime-total_threshold and cumulative <= maintime+total_threshold
                @episode_groups.push group.sort {|a,b| a[:number] <=> b[:number]}
            end
        rescue NoMethodError
            @dialog.msgbox "Could not find titles, probably due to an error reading the disc. Try cleaning the disc or check your optical drive. If the problem persists, you can debug further by running '#{@command} -i /dev/cdrom -t 0' and analysing the output."
            exit
        end
    end

    def confirm_episode_group group
        message = "One Episode Group Found:\n"
        message += self.get_group_listing group
        message += "Rip these titles?"
        @dialog.yesno message
    end

    def select_episode_group
        message = "Multiple possible episode groups found.\n"
        message += "Which group do you want to rip? (Cancel for none)\n"
        groups = Array.new
        @episode_groups.each_with_index do |group,index|
            groups.push [index.to_s, self.get_group_listing(group)]
        end
        answer = @dialog.radiolist message, groups
        if answer
            return answer
        else
            return nil
        end
    end

    def get_group_listing group
        listing = ""
        group.each do |episode|
            listing += self.get_title_listing episode[:number], episode[:duration], ","
        end
        listing
    end

    def get_title_listing number, duration, separator = "\n"
        ismain = ""
        if number == @main
            ismain = "(Main Feature)"
        end
        "Title #{number} [%02d:%02d:%02d] #{ismain}#{separator}" % [duration.hours, duration.minutes, duration.seconds]
    end

    def confirm_main_title
        maintime = @titles[@main.to_i].duration
        message = "Single main feature found:\n"
        message += "Title #{@main} [#{maintime}]\n"
        message += "Rip this feature?"
        @dialog.yesno message
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
        message = "No titles selected. The following titles were found.\nSelect the titles you wish to rip."
        numbers = Array.new
        @titles.each do |title|
            if !title.nil?
                numbers.push [' '+title.number, self.get_title_listing(title.number, title.duration)]
            end
        end
        begin
            answer = @dialog.checklist message, numbers
            if answer == false
                exit
            else
                answer.each do |title| title.lstrip! end
                @titles_to_rip = answer
            end
        rescue
            exit
        end
    end

    def add_subtitles?
        message = "Add subtitles with default settings?\n"
        lang = @options[:default_subtitles]
        forced = @options[:subtitles_forced] ? "yes" : "no"
        burned = @options[:subtitles_burned] ? "yes" : "no"
        message += "(Language #{lang}, Forced Only: #{forced}, Burned in: #{burned}) \n"
        if @dialog.yesno message
            @subtitle_to_rip = "scan -N #{@options[:default_subtitles]}"
        else
            return false
        end
    end

    def get_subtitle_track lang
        if lang == "scan"
            return lang
        end
        subtitles = @titles[@titles_to_rip.first].subtitles
        subtitles.each do |subtitle|
            if subtitle.lang == lang
                return subtitle.number
            end
        end
    end

    def get_subtitles
        title = @titles_to_rip.first ? @titles_to_rip.first.to_i : 1
        subtitles = @titles[title].subtitles
        message = "The following subtitle tracks were found,\n"
        default = nil
        numbers = Array.new
        subtitles.each do |subtitle|
            if subtitle.nil?
                next
            end
            if default.nil? and subtitle.lang == @options[:default_subtitle]
                default = subtitle.number
            end
            numbers.push [' ' + subtitle.number.to_s, subtitle.lang, default == subtitle.number]
        end
        message += "select the track you want to rip."
        begin
            answer = @dialog.radiolist message, numbers
            return answer.strip.to_s
        rescue
            exit
        end
    end

    def get_title
        if @options[:default_title].nil?
            if @options[:directory]
                default = @options[:directory].split('/').pop
            else
                default = @disc_title
            end
        else
            default = @options[:default_title]
        end
        message = "Enter the title for file and folder naming."
        invalid = " Enter a valid filename (Letters, numbers, _ - or ., not starting with - or .)"

        valid = nil
        while valid != true do
            question = message
            if valid == false
                question += invalid
            end
            answer = @dialog.inputbox(question, 0, 0, "\"#{default}\"")
            validation = /^[A-Za-z_0-9][A-Za-z_0-9\-. ]*$/.match answer
            if !validation.nil?
                valid = true
                answer = answer.strip()
            else
                valid = false
                default = answer
            end
        end
        return answer
    end

    def get_season
        message = "Enter season number for episode naming (Leave blank for none)."
        invalid = "\nPlease enter numbers only"
        default = @options[:default_season]
        if default.nil?
            default = ''
        end

        valid = nil
        while valid != true do
            question = message
            if valid == false
                question += invalid
            end
            begin
                answer = @dialog.inputbox(message, 0, 0, default)
                validation = /^[0-9]*$/.match answer
                if !validation.nil?
                    valid = true
                    answer = answer.to_i
                else
                    valid = false
                    default = answer
                end
            rescue
                answer = ''
            end
        end
        return answer
    end

    def get_first_episode
        message = "Enter first episode number for episode naming"
        invalid = "\nPlease enter a number"
        default = @options[:default_first_episode]
        if default.nil?
            default = ''
        end

        valid = nil
        while valid != true do
            question = message
            if valid == false
                question += invalid
            end
            begin
                answer = @dialog.inputbox(message, 0, 0, default)
                validation = /^[0-9]+$/.match answer
                if !validation.nil?
                    valid = true
                    answer = answer.to_i
                else
                    valid = false
                    default = answer
                end
            rescue
                answer = ''
            end
        end
        return answer
    end

    def main
        begin
            if @files == nil
                data = self.scan @options[:device]
                self.parse_output data

                self.find_episode_groups
                if @episode_groups.length > 0
                    if @episode_groups.length > 1
                        # Display groups and prompt for choice
                        group = @episode_groups[self.select_episode_group.to_i]
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
                    @dialog.msgbox "No titles selected, exiting\n"
                    exit
                end

            else
                path = @options[:directory] + '/' + @files[0]
                data = self.scan path
                self.parse_output data
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

            multipletitles = (@titles_to_rip.length > 1 or @files.length > 1 or !@options[:first_episode].nil?)
            if multipletitles and @options[:season].nil?
                @options[:season] = self.get_season
            end

            if multipletitles and @options[:first_episode].nil?
               @options[:first_episode] = self.get_first_episode
            end

            # Build commands to rip titles
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
            if @options[:preset].end_with? ".json"
                preset = "--preset-import-file \"#{@options[:preset]}\" --preset=\"#{File.basename(@options[:preset], ".json")}\""
            elsif
                preset = "--preset=\"#{@options[:preset]}\""
            end

            folder_name = "#{@options[:output]}/#{@options[:title]}"
            if !File.exists? folder_name
                Dir.mkdir folder_name
            end
            episode = " "
            if !@options[:season].nil?
                episode += "S%02d" % @options[:season]
            end
            if !@options[:first_episode].nil?
                episode_number = @options[:first_episode].to_i
                episode += "E%02d"
            end
            if episode == " "
                episode = ""
            end

            outputtemplate = "#{folder_name}/#{@options[:title]}#{episode}.#{@options[:extension]}"

            if @options[:directory].nil?
                @titles_to_rip.each do |title_number|
                    outputpath = outputtemplate % episode_number
                    if !episode_number.nil?
                        episode_number += 1
                    end
                    title = @titles[title_number.to_i]
                    command = "#{@command} -i #{@options[:device]} -o \"#{outputpath}\" #{preset} -t #{title_number} #{subtitle}"
                    @queue.push command
                end
            else
                @files.each do |file|
                    outputpath = outputtemplate % episode_number
                    if !episode_number.nil?
                        episode_number += 1
                    end
                    inputpath = @options[:directory] + '/' + file
                    command = "#{@command} -i \"#{inputpath}\" -o \"#{outputpath}\" #{preset} -t 1 #{subtitle}"
                    @queue.push command
                end
            end

            commandqueue = "Command Queue Created:\n"
            commandqueue += @queue.join("\n")
            commandqueue += "\n\nProcess this command queue?"
            if @dialog.yesno commandqueue.gsub('"', '\"'), @queue.length + 8, 80
                # Run Commands, yay!
                @queue.each do |command|
                    system command
                end
            else
                @dialog.msgbox "Queue not processed, exiting"
            end
            if @options[:eject]
                system "eject #{@options[:device]}"
            end
            system "clear" or system "cls"
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
