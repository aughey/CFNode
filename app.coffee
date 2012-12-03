fs = require 'fs'
_ = require './underscore-min'
crypto = require 'crypto'
nStore = require 'nstore'
BLOCKSIZE = 4096

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
						buffer = buffer.slice(0,l)
						emitter.emit 'data',buffer
						readdata()
			readdata();
	return emitter

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

unroll = (cb) ->
	return ->
		args = arguments
		process.nextTick ->
			cb.apply undefined, args

shastore = nStore.new 'data/shas.db', ->
	# Create a limiter that only allows 10 outstanding open calls
	open_limiter = make_allow_only(10)

	store_buffer = (buffer, cb) ->
		sha = crypto.createHash 'sha1'
		sha.update buffer
		digest = sha.digest('hex')
		console.log "digest is #{digest} with buffer len #{buffer.length}"
		process.nextTick ->
			cb digest
		return
		shastore.save digest,buffer, (err) ->
			cb digest

	store_object = (obj,cb) ->
		store_buffer JSON.stringify(obj),cb

	process_stream = (s,file,stats,whendone) ->
		shas = [];

		pending = 1
		s.on 'data', (buffer) ->
			index = shas.length
			shas.push 0
			pending += 1
			store_buffer buffer, (key) ->
				shas[index] = key
				raise "pending cannot be zero" if pending == 0
				pending -= 1
				whendone(shas) if pending == 0
		s.on 'end', ->
			console.log "done with file #{file}"
			raise "pending cannot be zero" if pending == 0
			pending -= 1
			whendone(shas) if pending == 0
		s.on 'error', ->
			console.log "error reading stream #{file}"
			whendone(null)

	process_file = (file,stats,whendone) ->
		open_limiter (release) ->
			console.log "Processing file #{file}"
			s = myreadstream file
			process_stream s,file,stats, (shas) ->
				release()
				if !shas
					whendone(null)
					return
				me = {
					stats: stats
					fullpath: file
					shas: shas
				}
				console.log "Stored file #{file}"
				console.log JSON.stringify(me,null,2)
				store_object me, (key) ->
					whendone key

	nonnulllist = (list) ->
		return _.filter list, (e) ->
			return !_.isNull(e)

	process_directory = (dir,whendone) ->
		dirobj = {}
		pending = 1

		dirresults = {
			fullpath: dir
			files: []
			directories: []
		}
		thisdone = (file) ->
			throw "pending should not be 0 called by #{file} within #{dir}" if pending == 0
			pending -= 1;
			return if pending > 0
			console.log "directory #{dir} done"
			dirresults.files = nonnulllist(dirresults.files);
			dirresults.directories = nonnulllist(dirresults.directories);
			store_object dirresults, (key) ->
				console.log JSON.stringify(dirresults,null,2)
				whendone key

		console.log "Processing directory #{dir}"
		fs.readdir dir, (err,files) ->
			if err || files.length == 0
				thisdone()
				return
			files = files.sort();

			pending = files.length
			p = files
			_.each files, (file,index) ->
				fullpath = "#{dir}/#{file}"
				fs.stat fullpath, (err,stats) ->
					if err
						thisdone()
						return
					# Keep the useful stats values
					usefulstats = _.pick(stats,'mode','uid','gid')
					if stats.isDirectory()
						process_directory fullpath, (result) ->
							if result
								dirresults.directories[index] = {
									filename: file
									key: result
								}
							thisdone(file)
					else if stats.isSymbolicLink()
						# Ignore this for now
					else if stats.isFile()
						console.log stats
						process_file fullpath, usefulstats, (result) ->
							if result
								dirresults.files[index] = {
									filename: file
									key: result
								}
							thisdone(file)

	argv = process.argv.slice()
	node = argv.shift()
	script = argv.shift()
	_.each argv, (dir) ->
		process_directory dir, (result) ->
			console.log("ALL DONE!")
			console.log(JSON.stringify(result,null," "))