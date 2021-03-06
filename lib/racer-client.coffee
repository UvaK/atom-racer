{BufferedProcess} = require 'atom'
_ = require 'underscore-plus'
fs = require 'fs'
temp = require('temp').track()
path = require 'path'

module.exports =
class RacerClient
  racer_bin: null
  rust_src: null
  project_path: null
  candidates: null

  check_generator = (racer_action) ->
    (editor, row, col, cb) ->
      if !@process_env_vars()
        console.error("Your racer package is not properly configured.")
        cb null
        return

      temp_folder_path = path.dirname(editor.getPath())
      original_file_name = path.basename(editor.getPath())
      # temp_folder_path will be '.' for unsaved files
      if temp_folder_path == "."
        temp_folder_path = @project_path

      tempOptions =
        prefix: original_file_name + ".racertmp_"
        dir: temp_folder_path


      temp.open tempOptions, (err, info) =>
        if err
          console.error(err)
          cb null
        else
          tempFilePath = info.path
          cb null unless tempFilePath

          text = editor.getText()
          fs.writeFileSync tempFilePath, text
          fs.close(info.fd);
          options =
            command: @racer_bin
            args: [racer_action, row + 1, col, tempFilePath]
            stdout: (output) =>
              parsed = @parse_single(output)
              @candidates.push(parsed) if parsed
              return
            exit: (code) =>
              @candidates = _.uniq(_.compact(_.flatten(@candidates)), (e) => e.word + e.file + e.type )
              cb @candidates
              temp.cleanup()
              return

          @candidates = []
          process = new BufferedProcess(options)
          return
      return

  check_completion: check_generator("complete")

  check_definition: check_generator("find-definition")

  process_env_vars: ->
    config_is_valid = true

    if !@racer_bin?
      conf_bin = atom.config.get("racer.racerBinPath")
      if conf_bin
        try
          stats = fs.lstatSync(conf_bin);
          if stats?.isFile()
            @racer_bin = conf_bin
    if !@racer_bin?
      config_is_valid = false
      console.error("racer.racerBinPath should point to the Racer binary executable")

    if !@rust_src?
      conf_src = atom.config.get("racer.rustSrcPath")
      if conf_src
        try
          stats = fs.lstatSync(conf_src);
          if stats?.isDirectory()
            @rust_src = conf_src
    if !@rust_src?
      config_is_valid = false
      console.error("racer.rustSrcPath should point to the Rustc sourcecode directory")

    if config_is_valid
      process.env.RUST_SRC_PATH = @rust_src

    return config_is_valid

  parse_single: (line) ->
    matches = []
    rcrgex = /MATCH (\w*)\,(\d*)\,(\d*)\,([^\,]*)\,(\w*)\,.*\n/mg
    while match = rcrgex.exec(line)
      if match?.length > 4
        candidate = {word: match[1], line: parseInt(match[2], 10), column: parseInt(match[3], 10), filePath: match[4], file: "this", type: match[5]}
        if path.extname(match[4]).indexOf(".racertmp_") == 0
          candidate.filePath = match[4].replace(/\.racertmp_.*?$/, "")
        else
          candidate.file = path.basename(match[4])
        matches.push(candidate)
    return matches
