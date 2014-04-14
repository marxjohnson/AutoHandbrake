#!/usr/bin/env ruby

require 'optparse'
require 'awesome_print'

class AutoHB 
    def initialize
        @options = {}
        @curTitle = Title.new
        @titles = Array.new
        self.parseOptions
    end

    def parseOptions
        optparse = OptionParser.new do |opts|
            opts.banner = "Usage: blah"
            opts.on('-f', '--file FILE', 'example input file') do |file|
                @options[:file] = file
            end
        end

        optparse.parse!

    end

    def appendTitle
        if @curTitle.number
            @titles[@curTitle.number.to_i] = @curTitle
            @curTitle = Title.new
        end
    end

    def main
        begin
            isin = ParseFlags.new
            File.open @options[:file] do |file|
                file.readlines.each do |line|
                    if !line.include? '+'
                        next
                    end
                    parts = line.strip.split
                    if line.start_with? "+"
                        self.appendTitle
                        @curTitle.number = line.match(/title (\d+):/)[1]
                        isin.meta = true;
                    elsif line.start_with? "  +"
                        case parts[1]
                        when 'duration:'
                            @curTitle.duration = parts[2]
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
                            duration = parts[7]
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
                self.appendTitle
            end
        ap @titles
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
