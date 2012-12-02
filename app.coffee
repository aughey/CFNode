fs = require 'fs'
_ = require './underscore-min'

process_file = (file,stats,whendone) ->
	return

process_directory = (dir,whendone) ->
	console.log "Processing directory #{dir}"
	dirobj = {}
	pending = 1
	whendone = (file,fileinfo) ->
		pending -= 1;
		return if pending > 0
		console.log "Done Processing #{dir}"

	fs.readdir dir, (err,files) ->
		return if err

		_.each files, (file) ->
			fullpath = "#{dir}/#{file}"
			fs.stat fullpath, (err,stats) ->
				if stats.isDirectory()
					process_directory fullpath
				else
					process_file
					console.log "#{fullpath} #{JSON.stringify(stats)}"

	whendone(null,null);

argv = process.argv.slice()
node = argv.shift()
script = argv.shift()
_.each(argv,process_directory)