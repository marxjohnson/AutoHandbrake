AutoHandbrake
=============

A command-line wizard to speed up ripping DVDs with HandBrakeCLI.

Scans DEVICE for titles and subtitles, attempts to detect groups of episodes, then creates
and executes HandBrakeCLI commands based on command-line arugments or answers to interactive
prompts.

When scanning, any titles shorter than DURATION (if specified) will be ignored.  The script
will look at the remaining titles and attempt to find a group of sequential, similar-length 
titles matching the length of the DVD's main feature.  If found, it will offer to rip this
group as a set of sequentially-numbered episodes, otherwise it will offer to rip the main
feature.  If detection is unsuccessful or incorrect, the user can override the titles to be
ripped.

    Requirements:
        HandBrakeCLI
        Ruby >= 2
        Ruby gems: optparse, duration, mattscilipoti-rdialog

    Usage: autohb [options]
        -i, --input DEVICE               Input device (DVD or Blu-Ray drive) [Default: detect]
        -o, --output DIR                 Base directory for output files [Default: ~/Videos]
            --file FILE                  example input file
            --subtitles LANG             Subtitle language (3 letter code, don't ask agaain)
            --default-subtitles LANG     Subtitle language (3 letter code) [default: eng]
        -f, --[no-]subtitles-forced      Only include forced subtitles [default: true]
        -b, --[no-]subtitles-burned      Burn-in subtitles [default: true]
        -T, --title TITLE                Title for file naming (won't ask again)
        -t, --default-title TITLE        Default title for file naming [default: read from disc]
        -S, --season NUMBER              Season number for file naming (won't ask again)
        -s, --default-season NUMBER      Default season number for file naming [default: read from disc or ask]
        -E, --episode NUMBER             First episode number for file naming (won't ask again)
        -e, --default-episode EPISODE    Default first episode number for file naming [default: 1]
            --preset PRESET              Handbrake preset to use (list with `HandBrakeCLI -z`) [default: Normal]
            --[no-]eject                 Eject disc when done [default: true]
        -m, --min-duration [DURATION]    Min duration

    Examples:
        autohb.rb # Scan all titles on the default device (/dev/dvd or /dev/cdrom and prompt for all questions)
        autohb.rb -i /dev/sr0 -o /mnt/media -m 240 # Scan all titles over 240 seconds (4 minutes) from /dev/sr0,
            # output files to /mnt/media, prompt for all questions.
        autohb.rb -T "The Simpsons" -S 5 -E 4 # Pre-set the first episode file name to "The Simpsons S05E04" and 
            # name the remaining episodes sequentially, skipping these questions in the wizard.
        autohb.rb -t "The Simpsons" -s 5 -e 4 # Default the first episode file name to "The Simpsons S05E04" and 
            # name the remaining episodes sequentially, but allow these to be overridden in the wizard.
