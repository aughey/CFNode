fs = require 'fs'
_ = require './underscore-min'
crypto = require 'crypto'
BLOCKSIZE = 1048576

# This is a poor mans class to create a function
# that only allows a certain number of callers to be
# outstanding at the same time.  The pattern looks like this:
#
# limiter = make_allow_only(10)
# limiter (release) ->
#	# when called, i'm one of the allowed 10
#   do_my_stuff()
#   release() # Tell the limiter I'm done and others can run
make_allow_only = (count) ->
	available = count;
	waiting = []
	release = ->
		if waiting.length > 0
			next = waiting.pop()
			process.nextTick ->
				next(release)
		else
			available += 1

	return (cb) ->
		if available > 0
			available -= 1
			process.nextTick ->
				cb(release)
		else
			waiting.push cb

# Create a limiter that only allows 10 outstanding open calls
open_limiter = make_allow_only(10)

myreadstream = (file) ->
	events = require 'events'
	emitter = new events.EventEmitter
	process.nextTick ->
		fs.open file,"r", (err,fd) ->
			if err
				emitter.emit 'error',err
				emitter.removeAllListeners()
				return
			readdata = ->
				buffer = new Buffer(BLOCKSIZE)
				fs.read fd,buffer,0,BLOCKSIZE,null,(err,l,buffer) ->
					if l == 0
						fs.close fd
						emitter.emit 'end'
						emitter.removeAllListeners()
					else
						buffer.length = l
						emitter.emit 'data',buffer
						readdata()
			readdata();
	return emitter

process_stream = (s,file,stats,whendone) ->
	s.on 'data', (buffer) ->
		sha = crypto.createHash 'sha1'
		sha.update buffer

		console.log "Read #{buffer.length} bytes from stream #{file} #{sha.digest('hex')}"
	s.on 'end', ->
		whendone()
	s.on 'error', ->
		console.log "error reading stream #{file}"
		whendone()

process_file = (file,stats,whendone) ->
	open_limiter (release) ->
		console.log "Processing file #{file}"
		s = myreadstream file
		process_stream s,file,stats, ->
			release()
			whendone file,null

process_directory = (dir,whendone) ->
	dirobj = {}
	pending = 1
	thisdone = (file,fileinfo) ->
		throw "pending should not be 0 called by #{file} within #{dir}" if pending == 0
		pending -= 1;
		return if pending > 0
		console.log "Done Processing #{dir}"
		whendone dir

	console.log "Processing directory #{dir}"
	fs.readdir dir, (err,files) ->
		if err
			thisdone "ME",null
			return

		pending += files.length
		_.each files, (file) ->
			fullpath = "#{dir}/#{file}"
			fs.stat fullpath, (err,stats) ->
				if err
					thisdone "ERR",null
					return
				if stats.isDirectory()
					process_directory fullpath,thisdone
				else
					process_file fullpath,stats,thisdone

argv = process.argv.slice()
node = argv.shift()
script = argv.shift()
_.each argv, (dir) ->
	process_directory dir, ->
		console.log("ALL DONE!")