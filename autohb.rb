#!/usr/bin/env ruby

require 'optparse'
require 'awesome_print'

class AutoHB 
    def initialize
        @options = {}
        @curTitle = Title.new
        @titles = Array.new
        @discTitle = ''
        @contentType = nil
        self.parse_options
    end

    def parse_options
        optparse = OptionParser.new do |opts|
            opts.banner = "Usage: blah"
            opts.on('-f', '--file FILE', 'example input file') do |file|
                @options[:file] = file
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
        f = File.open @options[:file] 
        f.read
    end

    def parse_duration(duration)
        parts = duration.split ':'
        Time.gm 1970, 1, 1, parts[0], parts[1], parts[2]
    end

    def parse_output(data)
        isin = ParseFlags.new
        data.each_line do |line|
            if !line.include? '+'
                next
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
    
    def film_or_tv
        times = Hash.new
        main = nil
        maintime = nil
        cumulative = nil
        previous = nil
        episode_threshold = 120
        total_threshold = 20
        episode_groups = Array.new
        group = nil
        @titles.each do |title|
            if !title.nil?
                if title.ismain
                    main = title.number
                    maintime = title.duration
                end
                times[title.number] = title.duration
            end
        end
        ap "maintime"
        ap maintime
        ap maintime.to_i
        times.each do |number,time|
            ap "time"
            ap time
            ap time.to_i
            if time != maintime
                ap "cuml1"
                ap cumulative
                ap cumulative.to_i
                if cumulative.nil?
                    cumulative = time
                    group = Array[Hash[:number => number, :time => time]]
                else 
                    puts "thresh"
                    ap group[0][:time].to_i-episode_threshold
                    if time.to_i < group[0][:time].to_i-episode_threshold
                        if cumulative.to_i >= maintime.to_i-total_threshold and cumulative.to_i <= maintime.to_i+total_threshold
                            episode_groups.push group
                        end
                        group = Array.new
                        cumulative = Time.gm 1970, 1, 1, 0, 0, 0
                    end
                    cumulative = cumulative+time.to_i
                    group.push Hash[:number => number, :time => time]
                end
            end
            ap "cuml2"
            ap cumulative
            ap cumulative.to_i
        end
        if cumulative.to_i >= maintime.to_i-total_threshold and cumulative.to_i <= maintime.to_i+total_threshold
            episode_groups.push = group
        end
        ap episode_groups
    end

    def main
        begin
            data = self.scan_disc
            self.parse_output data
            self.film_or_tv
            #ap @titles
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
